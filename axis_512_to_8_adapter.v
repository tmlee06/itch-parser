`timescale 1ns / 1ps
// =============================================================================
// Module: axis_512_to_8_adapter
// -----------------------------------------------------------------------------
// Purpose : Bridges the ESnet/CMAC 512-bit AXI-Stream bus down to the 8-bit
//           byte-serial interface expected by itch_decoder / top_parser_to_lob.
//
// Interface contract
//   - Upstream  (from CMAC RX) : standard AXI-Stream with tvalid/tready/tlast
//                                 and a 64-bit tkeep mask (1 bit per byte).
//   - Downstream (to parser)   : 8-bit data + valid, no back-pressure assumed
//                                 (parser must accept every cycle it is offered
//                                  a byte; add a FIFO in front if it cannot).
//
// Design notes
//   * A 64-entry shift register acts as the byte lane buffer.
//   * When the upstream delivers a beat we latch the 512-bit word and the
//     64-bit tkeep, then clock out one byte per cycle, skipping lanes whose
//     tkeep bit is 0 (rare: only the last beat of a frame may be partial).
//   * tready is de-asserted while we are still draining a previous beat so
//     the upstream never overflows us.  The CMAC's PCS buffers cover the
//     short (~64 cycle) drain window easily at 100 Gbps.
//   * byte_index counts from 0 (lowest-order byte, tdata[7:0]) upward.
//     Ethernet byte order: the CMAC presents the *first-on-wire* byte in
//     tdata[7:0] (little-endian lane packing, per Xilinx PG203).
// =============================================================================

module axis_512_to_8_adapter #(
    parameter DATA_W  = 512,          // CMAC AXI-S tdata width
    parameter KEEP_W  = DATA_W / 8    // = 64
)(
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  wire                 clk,
    input  wire                 rst,          // synchronous active-high

    // -------------------------------------------------------------------------
    // AXI-Stream slave (from CMAC / ESnet RX path)
    // -------------------------------------------------------------------------
    input  wire [DATA_W-1:0]    s_axis_tdata,
    input  wire [KEEP_W-1:0]    s_axis_tkeep,
    input  wire                 s_axis_tvalid,
    output wire                 s_axis_tready,
    input  wire                 s_axis_tlast,  // end-of-frame marker (captured, not used downstream yet)

    // -------------------------------------------------------------------------
    // 8-bit byte stream to itch_decoder
    // -------------------------------------------------------------------------
    output reg  [7:0]           byte_out,
    output reg                  byte_valid
);

    // -------------------------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------------------------
    reg [DATA_W-1:0]  data_buf;        // latched 512-bit word
    reg [KEEP_W-1:0]  keep_buf;        // latched tkeep
    reg [5:0]         byte_index;      // 0..63 – which lane we are currently outputting
    reg               draining;        // 1 while we are clocking out bytes from buf

    // We accept a new beat only when we are not currently draining
    assign s_axis_tready = ~draining;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            draining    <= 1'b0;
            byte_index  <= 6'd0;
            byte_out    <= 8'd0;
            byte_valid  <= 1'b0;
            data_buf    <= {DATA_W{1'b0}};
            keep_buf    <= {KEEP_W{1'b0}};
        end else begin

            // ------------------------------------------------------------------
            // Default: no output this cycle unless overridden below
            // ------------------------------------------------------------------
            byte_valid <= 1'b0;

            if (!draining) begin
                // --------------------------------------------------------------
                // IDLE – waiting for upstream beat
                // --------------------------------------------------------------
                if (s_axis_tvalid && s_axis_tready) begin
                    data_buf   <= s_axis_tdata;
                    keep_buf   <= s_axis_tkeep;
                    byte_index <= 6'd0;
                    draining   <= 1'b1;
                end

            end else begin
                // --------------------------------------------------------------
                // DRAINING – emit one byte per cycle, honour tkeep
                // --------------------------------------------------------------
                if (keep_buf[byte_index]) begin
                    // This lane is valid – send the byte
                    byte_out   <= data_buf[byte_index*8 +: 8];
                    byte_valid <= 1'b1;
                end
                // (if keep bit is 0 we simply skip: byte_valid stays 0)

                if (byte_index == (KEEP_W - 1)) begin
                    // Finished the last lane of this beat
                    draining   <= 1'b0;
                    byte_index <= 6'd0;
                end else begin
                    byte_index <= byte_index + 6'd1;
                end
            end

        end
    end

endmodule