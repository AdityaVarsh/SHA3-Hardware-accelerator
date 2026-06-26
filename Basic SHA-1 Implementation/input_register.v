`timescale 1ns / 1ps
// ============================================
// Block 1: INPUT REGISTER  (UNCHANGED from SHA-3)
// ============================================
// This module is algorithm-agnostic: it just
// registers a 64-bit input word and forwards the
// is_last / byte_count side-band flags. It is
// identical to the SHA-3 version on purpose, so
// the front-end and the AXI wrapper stay the same.
//
// byte_count = number of valid bytes in word (1-8)
//   0 is used only for the empty-message case.
// ============================================

module input_register (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [63:0] msg_in,
    input  wire        valid_in,
    input  wire        is_last,
    input  wire [3:0]  byte_count,

    output reg  [63:0] msg_out,
    output reg         valid_out,
    output reg         last_out,
    output reg  [3:0]  byte_count_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_out        <= 64'h0;
            valid_out      <= 1'b0;
            last_out       <= 1'b0;
            byte_count_out <= 4'd0;
        end
        else begin
            if (valid_in) begin
                msg_out        <= msg_in;
                valid_out      <= 1'b1;
                last_out       <= is_last;
                byte_count_out <= byte_count;
            end
            else begin
                valid_out      <= 1'b0;
                last_out       <= 1'b0;
                byte_count_out <= 4'd0;
            end
        end
    end

endmodule
