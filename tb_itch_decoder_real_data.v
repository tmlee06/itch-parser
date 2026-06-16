`timescale 1ns / 1ps

module tb_itch_decoder_real_data();

    // Inputs to the Top Module
    reg clk;
    reg rst;
    reg [7:0] data_in;
    reg valid_in;

    // Outputs from the Top Module
    wire [31:0] best_bid_price;
    wire [31:0] best_ask_price;

    // Memory array to hold the hex file data
    reg [7:0] rom_memory [0:2000]; 
    integer i;

    // INSTANTIATE THE NEW TOP MODULE
    top_parser_to_lob uut (
        .clk(clk),
        .rst(rst),
        .network_data_in(data_in),
        .network_valid_in(valid_in),
        .best_bid_price(best_bid_price),
        .best_ask_price(best_ask_price)
    );

    // Clock generation (10ns period = 100MHz clock)
    always #5 clk = ~clk;

    initial begin
        // Initialize Inputs
        clk = 0;
        rst = 1;
        data_in = 0;
        valid_in = 0;

        // Load the real SPY hex data
        $readmemh("sim_data.hex", rom_memory);

        // Wait 100 ns for global reset to finish
        #100;
        rst = 0;
        #20;

        // Start streaming data into the top module
        valid_in = 1;
        for (i = 0; i < 2000; i = i + 1) begin
            if (rom_memory[i] === 8'hxx) begin
                valid_in = 0;
                $display("End of valid hex data reached at index %d", i);
                break;
            end
            
            data_in = rom_memory[i];
            #10; 
        end
        
        valid_in = 0;
        
        #200;
        $finish;
    end

endmodule