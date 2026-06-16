`timescale 1ns / 1ps

module top_parser_to_lob (
    // System Inputs 
    input wire clk,
    input wire rst,
    input wire [7:0] network_data_in,
    input wire       network_valid_in,

    // System Outputs 
    output wire [31:0] best_bid_price,
    output wire [31:0] best_ask_price
);

    // INTERNAL WIRES (Connecting Parser -> LOB)
    wire [7:0]  parsed_msg_type;
    wire [31:0] parsed_shares;
    wire [31:0] parsed_price;
    wire        parsed_valid;

    // MODULE 1: The ITCH Decoder
    itch_decoder my_parser (
        .clk          (clk),
        .rst          (rst),
        .data_in      (network_data_in),
        .valid_in     (network_valid_in),
        
        .msg_type     (parsed_msg_type),
        .order_shares (parsed_shares),
        .order_price  (parsed_price),
        .order_valid  (parsed_valid) 
    );

    // MODULE 2: The Limit Order Book (LOB)
    order_book my_lob (
        .clk               (clk),
        .rst               (rst),
        
        .incoming_msg_type (parsed_msg_type),
        .incoming_shares   (parsed_shares),
        .incoming_price    (parsed_price),
        .incoming_valid    (parsed_valid),

        .best_bid_price    (best_bid_price),
        .best_ask_price    (best_ask_price)
    );

endmodule