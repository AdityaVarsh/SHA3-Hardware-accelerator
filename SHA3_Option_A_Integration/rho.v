`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 14:20:40
// Design Name:
// Module Name: rho
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
// Block 4b: RHO FUNCTION
// SHA-3 Keccak-f Step Mapping
// ============================================
// Applies fixed bitwise rotation to each lane.
// Input : 1600-bit state (output of theta)
// Output: 1600-bit state after rho
//
// Rotation offsets (FIPS-202 verified):
// Lane[0][0]=0,  Lane[1][0]=1,  Lane[2][0]=62
// Lane[3][0]=28, Lane[4][0]=27, Lane[0][1]=36
// Lane[1][1]=44, Lane[2][1]=6,  Lane[3][1]=55
// Lane[4][1]=20, Lane[0][2]=3,  Lane[1][2]=10
// Lane[2][2]=43, Lane[3][2]=25, Lane[4][2]=39
// Lane[0][3]=41, Lane[1][3]=45, Lane[2][3]=15
// Lane[3][3]=21, Lane[4][3]=8,  Lane[0][4]=18
// Lane[1][4]=2,  Lane[2][4]=61, Lane[3][4]=56
// Lane[4][4]=14
// ============================================

module rho (
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out
);

    // ----------------------------------------
    // ROT: 64-bit left rotation
    // ----------------------------------------
function [63:0] ROT;
    input [63:0] val;
    input [5:0]  n;
    begin
        if (n == 6'd0)
            ROT = val;
        else
            ROT = (val << n) | (val >> (64 - n));
    end
endfunction

    // ----------------------------------------
    // Combinational logic
    // ----------------------------------------
    always @(*) begin
// Row y=0
state_out[63:0]     = ROT(state_in[63:0],     6'd0);   // Lane[0][0]
state_out[127:64]   = ROT(state_in[127:64],   6'd1);   // Lane[1][0]
state_out[191:128]  = ROT(state_in[191:128],  6'd62);  // Lane[2][0]
state_out[255:192]  = ROT(state_in[255:192],  6'd28);  // Lane[3][0]
state_out[319:256]  = ROT(state_in[319:256],  6'd27);  // Lane[4][0]
// Row y=1
state_out[383:320]  = ROT(state_in[383:320],  6'd36);  // Lane[0][1]
state_out[447:384]  = ROT(state_in[447:384],  6'd44);  // Lane[1][1]
state_out[511:448]  = ROT(state_in[511:448],  6'd6);   // Lane[2][1]
state_out[575:512]  = ROT(state_in[575:512],  6'd55);  // Lane[3][1]
state_out[639:576]  = ROT(state_in[639:576],  6'd20);  // Lane[4][1]
// Row y=2
state_out[703:640]  = ROT(state_in[703:640],  6'd3);   // Lane[0][2]
state_out[767:704]  = ROT(state_in[767:704],  6'd10);  // Lane[1][2]
state_out[831:768]  = ROT(state_in[831:768],  6'd43);  // Lane[2][2]
state_out[895:832]  = ROT(state_in[895:832],  6'd25);  // Lane[3][2]
state_out[959:896]  = ROT(state_in[959:896],  6'd39);  // Lane[4][2]
// Row y=3
state_out[1023:960] = ROT(state_in[1023:960], 6'd41);  // Lane[0][3]
state_out[1087:1024]= ROT(state_in[1087:1024],6'd45);  // Lane[1][3]
state_out[1151:1088]= ROT(state_in[1151:1088],6'd15);  // Lane[2][3]
state_out[1215:1152]= ROT(state_in[1215:1152],6'd21);  // Lane[3][3]
state_out[1279:1216]= ROT(state_in[1279:1216],6'd8);   // Lane[4][3]
// Row y=4
state_out[1343:1280]= ROT(state_in[1343:1280],6'd18);  // Lane[0][4]
state_out[1407:1344]= ROT(state_in[1407:1344],6'd2);   // Lane[1][4]
state_out[1471:1408]= ROT(state_in[1471:1408],6'd61);  // Lane[2][4]
state_out[1535:1472]= ROT(state_in[1535:1472],6'd56);  // Lane[3][4]
state_out[1599:1536]= ROT(state_in[1599:1536],6'd14);  // Lane[4][4]
    end

endmodule
