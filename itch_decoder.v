`timescale 1ns / 1ps

module itch_decoder (
    input wire clk,
    input wire rst,
    input wire [7:0] data_in, // 1 byte of raw network data 
    input wire valid_in, // Tells us if the data is real
    
    output reg [7:0] msg_type, // E.g., 'A' for Add Order
    output reg [31:0] order_shares, // Extracted quantity
    output reg [31:0] order_price, // Extracted price
    output reg order_valid // Pulse HIGH when a full order is parsed
   );
   
   // FSM States
   localparam [2:0]
    IDLE = 3'd0,
    READ_LEN_1 = 3'd1,
    READ_LEN_2 = 3'd2,
    READ_TYPE = 3'd3,
    READ_PAYLOAD = 3'd4;
   
   
   reg [2:0] state, next_state;
      
   reg [15:0] msg_length;
   reg [15:0] byte_count;
   
   // Sequential Logic: Move to next state on every clock tick
   always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        byte_count <= 0;
        msg_length <= 0;
        order_shares <= 0;
        order_price <= 0;
        order_valid <= 0;
        msg_type <= 0;
      end else if (valid_in) begin
        state <= next_state;
        order_valid <= 0; // Default to 0 unless message is finished
        
        case (next_state)
            IDLE: begin
                byte_count <= 0;
            end
            READ_LEN_1: begin
                msg_length[15:8] <= data_in; // 1st half of length
            end
            READ_LEN_2: begin
                msg_length[7:0] <= data_in;
            end
            READ_TYPE: begin
                msg_type <= data_in;
                byte_count <= 1;
            end
            READ_PAYLOAD: begin
                byte_count <= byte_count + 1;
                
                if (msg_type == 8'h41) begin
                    if (byte_count == 20) order_shares[31:24] <= data_in;
                    if (byte_count == 21) order_shares[23:16] <= data_in;
                    if (byte_count == 22) order_shares[15:8] <= data_in;
                    if (byte_count == 23) order_shares[7:0] <= data_in;
                    
                    if (byte_count == 32) order_price[31:24] <= data_in;
                    if (byte_count == 33) order_price[23:16] <= data_in;
                    if (byte_count == 34) order_price[15:8] <= data_in;
                    if (byte_count == 35) order_price[7:0] <= data_in;
              end
              
              // Did we reach the end of message?
              if (byte_count == msg_length -1) begin
                if (msg_type == 8'h41) order_valid <= 1;
              end
           end
        endcase
     end else begin
        order_valid <= 0;
   end
 end
 
 // Combo logic 
 always @(*) begin
    next_state = state;
    
    case (state)
        IDLE: if (valid_in) next_state = READ_LEN_1;
        READ_LEN_1: next_state = READ_LEN_2;
        READ_LEN_2: next_state = READ_TYPE;
        READ_TYPE: next_state = READ_PAYLOAD;
        READ_PAYLOAD: if (byte_count == msg_length -1) next_state = IDLE;
     endcase
    end
  endmodule