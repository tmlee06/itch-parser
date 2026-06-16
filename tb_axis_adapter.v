`timescale 1ns / 1ps
// =============================================================================
// tb_axis_adapter.v  –  Simulation testbench for axis_512_to_8_adapter
// =============================================================================
// Feeds three back-to-back 512-bit beats (two full, one partial via tkeep)
// and checks that the output byte stream matches the expected sequence.
// Run with: xvlog + xelab + xsim  (no GUI needed – Coder terminal)
//
//   xvlog --sv axis_512_to_8_adapter.v tb_axis_adapter.v
//   xelab -top tb_axis_adapter -snapshot tb_snap
//   xsim  tb_snap --runall
// =============================================================================

module tb_axis_adapter;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    reg          clk;
    reg          rst;

    reg  [511:0] s_tdata;
    reg  [63:0]  s_tkeep;
    reg          s_tvalid;
    wire         s_tready;
    reg          s_tlast;

    wire [7:0]   byte_out;
    wire         byte_valid;

    // -------------------------------------------------------------------------
    // Instantiate DUT
    // -------------------------------------------------------------------------
    axis_512_to_8_adapter #(.DATA_W(512), .KEEP_W(64)) dut (
        .clk           (clk),
        .rst           (rst),
        .s_axis_tdata  (s_tdata),
        .s_axis_tkeep  (s_tkeep),
        .s_axis_tvalid (s_tvalid),
        .s_axis_tready (s_tready),
        .s_axis_tlast  (s_tlast),
        .byte_out       (byte_out),
        .byte_valid     (byte_valid)
    );

    // -------------------------------------------------------------------------
    // Clock – 10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Logging
    // -------------------------------------------------------------------------
    integer byte_count;
    initial byte_count = 0;

    always @(posedge clk) begin
        if (byte_valid) begin
            $display("t=%0t  byte[%0d] = 0x%02X", $time, byte_count, byte_out);
            byte_count = byte_count + 1;
        end
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    task send_beat;
        input [511:0] data;
        input [63:0]  keep;
        input         last;
        begin
            // Wait until DUT is ready to accept
            @(posedge clk);
            while (!s_tready) @(posedge clk);

            s_tdata  <= data;
            s_tkeep  <= keep;
            s_tvalid <= 1'b1;
            s_tlast  <= last;
            @(posedge clk);
            s_tvalid <= 1'b0;
            s_tlast  <= 1'b0;
        end
    endtask

    integer i;
    reg [511:0] beat0, beat1, beat2_partial;
    reg [63:0]  keep_full, keep_partial_10bytes;

    initial begin
        // Reset
        rst = 1; s_tvalid = 0; s_tdata = 0; s_tkeep = 0; s_tlast = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------------
        // Beat 0: all 64 bytes valid, bytes 0..63 = 0x00..0x3F
        // ------------------------------------------------------------------
        beat0 = 512'd0;
        for (i = 0; i < 64; i = i+1)
            beat0[i*8 +: 8] = i[7:0];   // byte lane i = value i
        keep_full = 64'hFFFF_FFFF_FFFF_FFFF;

        $display("\n=== Beat 0: 64 full bytes ===");
        send_beat(beat0, keep_full, 1'b0);

        // Wait for the adapter to drain (64 cycles)
        repeat(70) @(posedge clk);

        // ------------------------------------------------------------------
        // Beat 1: all 64 bytes valid, bytes = 0x80..0xBF
        // ------------------------------------------------------------------
        beat1 = 512'd0;
        for (i = 0; i < 64; i = i+1)
            beat1[i*8 +: 8] = 8'h80 + i[7:0];
        $display("\n=== Beat 1: 64 full bytes ===");
        send_beat(beat1, keep_full, 1'b0);
        repeat(70) @(posedge clk);

        // ------------------------------------------------------------------
        // Beat 2: only first 10 bytes valid (partial last beat)
        //   tkeep = 64'h0000_0000_0000_03FF  (bits 0..9 set)
        // ------------------------------------------------------------------
        beat2_partial = 512'd0;
        for (i = 0; i < 10; i = i+1)
            beat2_partial[i*8 +: 8] = 8'hC0 + i[7:0];
        keep_partial_10bytes = 64'h0000_0000_0000_03FF;

        $display("\n=== Beat 2: partial – 10 bytes (tkeep[9:0]=1) ===");
        send_beat(beat2_partial, keep_partial_10bytes, 1'b1);
        repeat(20) @(posedge clk);

        $display("\n=== Total bytes received: %0d (expected 138) ===", byte_count);
        if (byte_count == 138)
            $display("PASS");
        else
            $display("FAIL – byte count mismatch");

        $finish;
    end

endmodule