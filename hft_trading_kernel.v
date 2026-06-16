`timescale 1ns / 1ps
// =============================================================================
// Module: hft_trading_kernel
// -----------------------------------------------------------------------------
// Top-level RTL Kernel wrapper for Vitis / XRT packaging.
//
// This is the module that `package_xo.tcl` will wrap into a .xo object.
// It presents:
//   - One AXI-Stream slave  (512-bit)  connected to the CMAC RX path
//   - One AXI-Stream master (512-bit)  for TX responses (stubbed – wire to 0
//     until your response encoder is ready)
//   - The two 32-bit scalar outputs visible to the host via AXI-Lite s_axi_ctrl
//
// The kernel clock is driven by the CMAC reference (nominally 322 MHz on U55C).
// The itch_decoder/order_book are designed for ≥100 MHz – they will be fine.
// =============================================================================

module hft_trading_kernel (
    // -------------------------------------------------------------------------
    // Kernel clock & reset (driven by Vitis shell)
    // -------------------------------------------------------------------------
    input  wire         ap_clk,
    input  wire         ap_rst_n,          // active-LOW from shell

    // -------------------------------------------------------------------------
    // AXI-Stream IN  (from CMAC RX – 512-bit bus)
    // -------------------------------------------------------------------------
    input  wire [511:0] rx_axis_tdata,
    input  wire [63:0]  rx_axis_tkeep,
    input  wire         rx_axis_tvalid,
    output wire         rx_axis_tready,
    input  wire         rx_axis_tlast,

    // -------------------------------------------------------------------------
    // AXI-Stream OUT (to CMAC TX – stubbed for now)
    // -------------------------------------------------------------------------
    output wire [511:0] tx_axis_tdata,
    output wire [63:0]  tx_axis_tkeep,
    output wire         tx_axis_tvalid,
    input  wire         tx_axis_tready,
    output wire         tx_axis_tlast,

    // -------------------------------------------------------------------------
    // AXI-Lite control (host-visible scalars)
    // -------------------------------------------------------------------------
    // Vitis auto-generates this interface; we expose best_bid/ask through it.
    // For now we tie the s_axi_ctrl lines to a minimal always-ready slave.
    // Replace with a proper AXI-Lite register file when you need host readback.
    input  wire [11:0]  s_axi_ctrl_awaddr,
    input  wire         s_axi_ctrl_awvalid,
    output wire         s_axi_ctrl_awready,
    input  wire [31:0]  s_axi_ctrl_wdata,
    input  wire [3:0]   s_axi_ctrl_wstrb,
    input  wire         s_axi_ctrl_wvalid,
    output wire         s_axi_ctrl_wready,
    output wire [1:0]   s_axi_ctrl_bresp,
    output wire         s_axi_ctrl_bvalid,
    input  wire         s_axi_ctrl_bready,
    input  wire [11:0]  s_axi_ctrl_araddr,
    input  wire         s_axi_ctrl_arvalid,
    output wire         s_axi_ctrl_arready,
    output wire [31:0]  s_axi_ctrl_rdata,
    output wire [1:0]   s_axi_ctrl_rresp,
    output wire         s_axi_ctrl_rvalid,
    input  wire         s_axi_ctrl_rready
);

    // -------------------------------------------------------------------------
    // Internal wiring
    // -------------------------------------------------------------------------
    wire        rst_sync;          // synchronous active-high reset
    wire [7:0]  byte_data;
    wire        byte_valid;
    wire [31:0] best_bid, best_ask;

    // Synchronise the active-low shell reset to our clock domain
    assign rst_sync = ~ap_rst_n;

    // -------------------------------------------------------------------------
    // 1. 512→8 AXI-Stream adapter
    // -------------------------------------------------------------------------
    axis_512_to_8_adapter #(
        .DATA_W (512),
        .KEEP_W (64)
    ) u_adapter (
        .clk            (ap_clk),
        .rst            (rst_sync),
        .s_axis_tdata   (rx_axis_tdata),
        .s_axis_tkeep   (rx_axis_tkeep),
        .s_axis_tvalid  (rx_axis_tvalid),
        .s_axis_tready  (rx_axis_tready),
        .s_axis_tlast   (rx_axis_tlast),
        .byte_out        (byte_data),
        .byte_valid      (byte_valid)
    );

    // -------------------------------------------------------------------------
    // 2. ITCH parser + Limit Order Book (your existing top module)
    // -------------------------------------------------------------------------
    top_parser_to_lob u_top (
        .clk                (ap_clk),
        .rst                (rst_sync),
        .network_data_in    (byte_data),
        .network_valid_in   (byte_valid),
        .best_bid_price     (best_bid),
        .best_ask_price     (best_ask)
    );

    // -------------------------------------------------------------------------
    // 3. TX path stub (tie off until response encoder is implemented)
    // -------------------------------------------------------------------------
    assign tx_axis_tdata  = {512{1'b0}};
    assign tx_axis_tkeep  = {64{1'b0}};
    assign tx_axis_tvalid = 1'b0;
    assign tx_axis_tlast  = 1'b0;

    // -------------------------------------------------------------------------
    // 4. Minimal AXI-Lite slave stub
    //    best_bid readable at offset 0x010, best_ask at 0x018
    // -------------------------------------------------------------------------
    reg [31:0] axi_rdata_r;
    reg        axi_rvalid_r;
    reg        axi_arready_r;

    assign s_axi_ctrl_awready = 1'b1;
    assign s_axi_ctrl_wready  = 1'b1;
    assign s_axi_ctrl_bresp   = 2'b00;
    assign s_axi_ctrl_bvalid  = 1'b1;
    assign s_axi_ctrl_rdata   = axi_rdata_r;
    assign s_axi_ctrl_rresp   = 2'b00;
    assign s_axi_ctrl_rvalid  = axi_rvalid_r;
    assign s_axi_ctrl_arready = axi_arready_r;

    always @(posedge ap_clk) begin
        if (rst_sync) begin
            axi_rdata_r  <= 32'd0;
            axi_rvalid_r <= 1'b0;
            axi_arready_r<= 1'b0;
        end else begin
            axi_arready_r <= s_axi_ctrl_arvalid;
            if (s_axi_ctrl_arvalid) begin
                case (s_axi_ctrl_araddr)
                    12'h010 : axi_rdata_r <= best_bid;
                    12'h018 : axi_rdata_r <= best_ask;
                    default : axi_rdata_r <= 32'hDEADBEEF;
                endcase
                axi_rvalid_r <= 1'b1;
            end else if (s_axi_ctrl_rready) begin
                axi_rvalid_r <= 1'b0;
            end
        end
    end

endmodule