`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 14:35:29
// Design Name:
// Module Name: chi
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
// Block 4d: CHI FUNCTION
// SHA-3 Keccak-f Step Mapping
// ============================================
// Non-linear step - only non-linear in Keccak.
// Formula:
//   A'[x][y] = A[x][y] ^
//              ((~A[(x+1)%5][y]) & A[(x+2)%5][y])
//
// Applied to all 25 lanes, row by row.
// Input : 1600-bit state (output of pi)
// Output: 1600-bit state after chi
// ============================================

module chi (
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out
);

    always @(*) begin

        // ============================
        // Row y=0
        // bits [319:0]
        // ============================
        // x=0: A[0][0]^((~A[1][0])&A[2][0])
        state_out[63:0]    = state_in[63:0]
                           ^ ((~state_in[127:64])
                           &   state_in[191:128]);

        // x=1: A[1][0]^((~A[2][0])&A[3][0])
        state_out[127:64]  = state_in[127:64]
                           ^ ((~state_in[191:128])
                           &   state_in[255:192]);

        // x=2: A[2][0]^((~A[3][0])&A[4][0])
        state_out[191:128] = state_in[191:128]
                           ^ ((~state_in[255:192])
                           &   state_in[319:256]);

        // x=3: A[3][0]^((~A[4][0])&A[0][0])
        state_out[255:192] = state_in[255:192]
                           ^ ((~state_in[319:256])
                           &   state_in[63:0]);

        // x=4: A[4][0]^((~A[0][0])&A[1][0])
        state_out[319:256] = state_in[319:256]
                           ^ ((~state_in[63:0])
                           &   state_in[127:64]);

        // ============================
        // Row y=1
        // bits [639:320]
        // ============================
        // x=0: A[0][1]^((~A[1][1])&A[2][1])
        state_out[383:320] = state_in[383:320]
                           ^ ((~state_in[447:384])
                           &   state_in[511:448]);

        // x=1: A[1][1]^((~A[2][1])&A[3][1])
        state_out[447:384] = state_in[447:384]
                           ^ ((~state_in[511:448])
                           &   state_in[575:512]);

        // x=2: A[2][1]^((~A[3][1])&A[4][1])
        state_out[511:448] = state_in[511:448]
                           ^ ((~state_in[575:512])
                           &   state_in[639:576]);

        // x=3: A[3][1]^((~A[4][1])&A[0][1])
        state_out[575:512] = state_in[575:512]
                           ^ ((~state_in[639:576])
                           &   state_in[383:320]);

        // x=4: A[4][1]^((~A[0][1])&A[1][1])
        state_out[639:576] = state_in[639:576]
                           ^ ((~state_in[383:320])
                           &   state_in[447:384]);

        // ============================
        // Row y=2
        // bits [959:640]
        // ============================
        // x=0: A[0][2]^((~A[1][2])&A[2][2])
        state_out[703:640] = state_in[703:640]
                           ^ ((~state_in[767:704])
                           &   state_in[831:768]);

        // x=1: A[1][2]^((~A[2][2])&A[3][2])
        state_out[767:704] = state_in[767:704]
                           ^ ((~state_in[831:768])
                           &   state_in[895:832]);

        // x=2: A[2][2]^((~A[3][2])&A[4][2])
        state_out[831:768] = state_in[831:768]
                           ^ ((~state_in[895:832])
                           &   state_in[959:896]);

        // x=3: A[3][2]^((~A[4][2])&A[0][2])
        state_out[895:832] = state_in[895:832]
                           ^ ((~state_in[959:896])
                           &   state_in[703:640]);

        // x=4: A[4][2]^((~A[0][2])&A[1][2])
        state_out[959:896] = state_in[959:896]
                           ^ ((~state_in[703:640])
                           &   state_in[767:704]);

        // ============================
        // Row y=3
        // bits [1279:960]
        // ============================
        // x=0: A[0][3]^((~A[1][3])&A[2][3])
        state_out[1023:960]  = state_in[1023:960]
                             ^ ((~state_in[1087:1024])
                             &   state_in[1151:1088]);

        // x=1: A[1][3]^((~A[2][3])&A[3][3])
        state_out[1087:1024] = state_in[1087:1024]
                             ^ ((~state_in[1151:1088])
                             &   state_in[1215:1152]);

        // x=2: A[2][3]^((~A[3][3])&A[4][3])
        state_out[1151:1088] = state_in[1151:1088]
                             ^ ((~state_in[1215:1152])
                             &   state_in[1279:1216]);

        // x=3: A[3][3]^((~A[4][3])&A[0][3])
        state_out[1215:1152] = state_in[1215:1152]
                             ^ ((~state_in[1279:1216])
                             &   state_in[1023:960]);

        // x=4: A[4][3]^((~A[0][3])&A[1][3])
        state_out[1279:1216] = state_in[1279:1216]
                             ^ ((~state_in[1023:960])
                             &   state_in[1087:1024]);

        // ============================
        // Row y=4
        // bits [1599:1280]
        // ============================
        // x=0: A[0][4]^((~A[1][4])&A[2][4])
        state_out[1343:1280] = state_in[1343:1280]
                             ^ ((~state_in[1407:1344])
                             &   state_in[1471:1408]);

        // x=1: A[1][4]^((~A[2][4])&A[3][4])
        state_out[1407:1344] = state_in[1407:1344]
                             ^ ((~state_in[1471:1408])
                             &   state_in[1535:1472]);

        // x=2: A[2][4]^((~A[3][4])&A[4][4])
        state_out[1471:1408] = state_in[1471:1408]
                             ^ ((~state_in[1535:1472])
                             &   state_in[1599:1536]);

        // x=3: A[3][4]^((~A[4][4])&A[0][4])
        state_out[1535:1472] = state_in[1535:1472]
                             ^ ((~state_in[1599:1536])
                             &   state_in[1343:1280]);

        // x=4: A[4][4]^((~A[0][4])&A[1][4])
        state_out[1599:1536] = state_in[1599:1536]
                             ^ ((~state_in[1343:1280])
                             &   state_in[1407:1344]);
    end

endmodule
