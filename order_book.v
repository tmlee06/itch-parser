`timescale 1ns / 1ps

module order_book (
    input wire clk,
    input wire rst,
    
    // Inputs coming from the ITCH parser
    input wire [7:0]  incoming_msg_type,
    input wire [31:0] incoming_shares,
    input wire [31:0] incoming_price,
    input wire        incoming_valid,

    // Outputs going to the trading strategy/testbench
    output reg [31:0] best_bid_price,
    output reg [31:0] best_ask_price
);

    always @(posedge clk) begin
        if (rst) begin
            best_bid_price <= 32'd0;
            best_ask_price <= 32'd0;
        end else if (incoming_valid) begin
            // Placeholder: Future logic for sorting the book goes here.
            // For now, it just holds its value.
            best_bid_price <= best_bid_price;
            best_ask_price <= best_ask_price;
        end
    end

endmodule