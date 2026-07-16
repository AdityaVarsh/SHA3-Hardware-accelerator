`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 14:27:18
// Design Name:
// Module Name: pi
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
// Block 4c: PI FUNCTION
// SHA-3 Keccak-f Step Mapping
// ============================================
// Permutes lane positions.
// Formula: new[x2][y2] = old[x][y]
//   where x2 = y
//         y2 = (2x + 3y) mod 5
//
// Input : 1600-bit state (output of rho)
// Output: 1600-bit state after pi
// ============================================

module pi (
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out
);

    // ----------------------------------------
    // Combinational logic
    // All 25 pi mappings fully expanded
    // ----------------------------------------
always @(*) begin
// new[0][0] = old[0][0]
state_out[63:0]      = state_in[63:0];
// new[0][2] = old[1][0]
state_out[703:640]   = state_in[127:64];
// new[0][4] = old[2][0]
state_out[1343:1280] = state_in[191:128];
// new[0][1] = old[3][0]
state_out[383:320]   = state_in[255:192];
// new[0][3] = old[4][0]
state_out[1023:960]  = state_in[319:256];
// new[1][3] = old[0][1]
state_out[1087:1024] = state_in[383:320];
// new[1][0] = old[1][1]
state_out[127:64]    = state_in[447:384];
// new[1][2] = old[2][1]
state_out[767:704]   = state_in[511:448];
// new[1][4] = old[3][1]
state_out[1407:1344] = state_in[575:512];
// new[1][1] = old[4][1]
state_out[447:384]   = state_in[639:576];
// new[2][1] = old[0][2]
state_out[511:448]   = state_in[703:640];
// new[2][3] = old[1][2]
state_out[1151:1088] = state_in[767:704];
// new[2][0] = old[2][2]
state_out[191:128]   = state_in[831:768];
// new[2][2] = old[3][2]
state_out[831:768]   = state_in[895:832];
// new[2][4] = old[4][2]
state_out[1471:1408] = state_in[959:896];
// new[3][4] = old[0][3]
state_out[1535:1472] = state_in[1023:960];
// new[3][1] = old[1][3]
state_out[575:512]   = state_in[1087:1024];
// new[3][3] = old[2][3]
state_out[1215:1152] = state_in[1151:1088];
// new[3][0] = old[3][3]
state_out[255:192]   = state_in[1215:1152];
// new[3][2] = old[4][3]
state_out[895:832]   = state_in[1279:1216];
// new[4][2] = old[0][4]
state_out[959:896]   = state_in[1343:1280];
// new[4][4] = old[1][4]
state_out[1599:1536] = state_in[1407:1344];
// new[4][1] = old[2][4]
state_out[639:576]   = state_in[1471:1408];
// new[4][3] = old[3][4]
state_out[1279:1216] = state_in[1535:1472];
// new[4][0] = old[4][4]
state_out[319:256]   = state_in[1599:1536];
end

endmodule
