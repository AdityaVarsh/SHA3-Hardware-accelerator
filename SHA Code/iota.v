`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 17:30:58
// Design Name:
// Module Name: iota
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
// Block 4e: IOTA FUNCTION
// SHA-3 Keccak-f Step Mapping
// ============================================
// XORs round constant into Lane[0][0] only.
// All other 24 lanes pass through unchanged.
//
// Formula:
//   A'[0][0] = A[0][0] ^ RC[round]
//   A'[x][y] = A[x][y]  for all other lanes
//
// Input : 1600-bit state (output of chi)
//         5-bit round number (0-23)
// Output: 1600-bit state after iota
// ============================================

module iota (
    input  wire [1599:0] state_in,
    input  wire [4:0]    round,     // Round number 0-23
    output reg  [1599:0] state_out
);

    // ----------------------------------------
    // get_rc: round constants RC[0..23]
    // FIPS-202 verified
    // ----------------------------------------
    function [63:0] get_rc;
        input [4:0] r;
        begin
            case (r)
                5'd0 : get_rc=64'h0000000000000001;
                5'd1 : get_rc=64'h0000000000008082;
                5'd2 : get_rc=64'h800000000000808A;
                5'd3 : get_rc=64'h8000000080008000;
                5'd4 : get_rc=64'h000000000000808B;
                5'd5 : get_rc=64'h0000000080000001;
                5'd6 : get_rc=64'h8000000080008081;
                5'd7 : get_rc=64'h8000000000008009;
                5'd8 : get_rc=64'h000000000000008A;
                5'd9 : get_rc=64'h0000000000000088;
                5'd10: get_rc=64'h0000000080008009;
                5'd11: get_rc=64'h000000008000000A;
                5'd12: get_rc=64'h000000008000808B;
                5'd13: get_rc=64'h800000000000008B;
                5'd14: get_rc=64'h8000000000008089;
                5'd15: get_rc=64'h8000000000008003;
                5'd16: get_rc=64'h8000000000008002;
                5'd17: get_rc=64'h8000000000000080;
                5'd18: get_rc=64'h000000000000800A;
                5'd19: get_rc=64'h800000008000000A;
                5'd20: get_rc=64'h8000000080008081;
                5'd21: get_rc=64'h8000000000008080;
                5'd22: get_rc=64'h0000000080000001;
                5'd23: get_rc=64'h8000000080008008;
                default: get_rc=64'h0;
            endcase
        end
    endfunction

    // ----------------------------------------
    // Combinational logic
    // ----------------------------------------
    always @(*) begin
        // Pass all lanes through unchanged
        state_out = state_in;

        // XOR round constant into Lane[0][0]
        // Lane[0][0] = state[63:0]
        state_out[63:0] = state_in[63:0] ^ get_rc(round);
    end

endmodule