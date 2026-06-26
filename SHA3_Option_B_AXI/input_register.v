`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 18.03.2026 18:52:04
// Design Name:
// Module Name: input_register
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


// ============================================
// Block 1: INPUT REGISTER
// SHA-3 Hardware Accelerator
// ============================================
// Captures 64-bit input word and forwards to
// Padder. Passes is_last and byte_count flags
// so Padder knows where to insert 0x06 pad.
//
// byte_count = number of valid bytes in word
//   Range : 1 to 8  (needs 4 bits)
//   Reset : 0 (invalid/idle state)
// ============================================

module input_register (
    input  wire        clk,            // Clock
    input  wire        rst_n,          // Active-low reset
    input  wire [63:0] msg_in,         // 64-bit input word
    input  wire        valid_in,       // HIGH when msg_in has valid data
    input  wire        is_last,        // HIGH when this is the final word
    input  wire [3:0]  byte_count,     // Valid bytes in this word (1-8)

    output reg  [63:0] msg_out,        // Registered output to Padder
    output reg         valid_out,      // HIGH when msg_out is valid
    output reg         last_out,       // HIGH when msg_out is the final word
    output reg  [3:0]  byte_count_out  // Valid byte count forwarded to Padder
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_out        <= 64'h0000000000000000;
            valid_out      <= 1'b0;
            last_out       <= 1'b0;
            byte_count_out <= 4'b0000;
        end
        else begin
            if (valid_in) begin
                msg_out        <= msg_in;      // Capture input word
                valid_out      <= 1'b1;        // Signal data is ready
                last_out       <= is_last;     // Forward last-word flag
                byte_count_out <= byte_count;  // Forward byte count to Padder
            end
            else begin
                valid_out      <= 1'b0;
                last_out       <= 1'b0;
                byte_count_out <= 4'b0000;
            end
        end
    end

endmodule
