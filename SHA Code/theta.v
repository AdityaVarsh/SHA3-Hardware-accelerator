`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 13:36:55
// Design Name:
// Module Name: theta
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
// Block 4a: THETA FUNCTION
// SHA-3 Keccak-f Step Mapping
// ============================================
// Computes θ step of Keccak-f permutation.
//
// Step 1: C[x] = XOR of all lanes in column x
// Step 2: D[x] = C[x-1] ^ ROT(C[x+1], 1)
// Step 3: A[x][y] = Lane[x][y] ^ D[x]
//
// Input : 1600-bit state
// Output: 1600-bit state after θ
// ============================================

module theta (
    input  wire [1599:0] state_in,
    output reg  [1599:0] state_out
);

    // ----------------------------------------
    // ROT: 64-bit left rotation
    // ----------------------------------------
    function [63:0] ROT;
        input [63:0] val;
        input [5:0]  n;
        reg   [6:0]  rshift;
        begin
            if (n == 6'd0)
                ROT = val;
            else begin
                rshift = 7'd64 - {1'b0, n};
                ROT    = (val << n) | (val >> rshift);
            end
        end
    endfunction

    // ----------------------------------------
    // get_lane: extract Lane[x][y]
    // ----------------------------------------
    function [63:0] get_lane;
        input [1599:0] st;
        input [2:0]    x;
        input [2:0]    y;
        reg   [4:0]    idx;
        begin
            idx = ({2'b00,y} * 3'd5) + {2'b00,x};
            case (idx)
                5'd0 : get_lane=st[63:0];
                5'd1 : get_lane=st[127:64];
                5'd2 : get_lane=st[191:128];
                5'd3 : get_lane=st[255:192];
                5'd4 : get_lane=st[319:256];
                5'd5 : get_lane=st[383:320];
                5'd6 : get_lane=st[447:384];
                5'd7 : get_lane=st[511:448];
                5'd8 : get_lane=st[575:512];
                5'd9 : get_lane=st[639:576];
                5'd10: get_lane=st[703:640];
                5'd11: get_lane=st[767:704];
                5'd12: get_lane=st[831:768];
                5'd13: get_lane=st[895:832];
                5'd14: get_lane=st[959:896];
                5'd15: get_lane=st[1023:960];
                5'd16: get_lane=st[1087:1024];
                5'd17: get_lane=st[1151:1088];
                5'd18: get_lane=st[1215:1152];
                5'd19: get_lane=st[1279:1216];
                5'd20: get_lane=st[1343:1280];
                5'd21: get_lane=st[1407:1344];
                5'd22: get_lane=st[1471:1408];
                5'd23: get_lane=st[1535:1472];
                5'd24: get_lane=st[1599:1536];
                default: get_lane=64'h0;
            endcase
        end
    endfunction

    // ----------------------------------------
    // C and D intermediate values
    // ----------------------------------------
    reg [63:0] C0,C1,C2,C3,C4;
    reg [63:0] D0,D1,D2,D3,D4;

    // ----------------------------------------
    // After θ lanes
    // ----------------------------------------
    reg [63:0] A00,A10,A20,A30,A40;
    reg [63:0] A01,A11,A21,A31,A41;
    reg [63:0] A02,A12,A22,A32,A42;
    reg [63:0] A03,A13,A23,A33,A43;
    reg [63:0] A04,A14,A24,A34,A44;

    // ----------------------------------------
    // Combinational logic
    // ----------------------------------------
    always @(*) begin

        // ==========================
        // Step 1: Column parities
        // ==========================
        C0=get_lane(state_in,3'd0,3'd0)
          ^get_lane(state_in,3'd0,3'd1)
          ^get_lane(state_in,3'd0,3'd2)
          ^get_lane(state_in,3'd0,3'd3)
          ^get_lane(state_in,3'd0,3'd4);

        C1=get_lane(state_in,3'd1,3'd0)
          ^get_lane(state_in,3'd1,3'd1)
          ^get_lane(state_in,3'd1,3'd2)
          ^get_lane(state_in,3'd1,3'd3)
          ^get_lane(state_in,3'd1,3'd4);

        C2=get_lane(state_in,3'd2,3'd0)
          ^get_lane(state_in,3'd2,3'd1)
          ^get_lane(state_in,3'd2,3'd2)
          ^get_lane(state_in,3'd2,3'd3)
          ^get_lane(state_in,3'd2,3'd4);

        C3=get_lane(state_in,3'd3,3'd0)
          ^get_lane(state_in,3'd3,3'd1)
          ^get_lane(state_in,3'd3,3'd2)
          ^get_lane(state_in,3'd3,3'd3)
          ^get_lane(state_in,3'd3,3'd4);

        C4=get_lane(state_in,3'd4,3'd0)
          ^get_lane(state_in,3'd4,3'd1)
          ^get_lane(state_in,3'd4,3'd2)
          ^get_lane(state_in,3'd4,3'd3)
          ^get_lane(state_in,3'd4,3'd4);

        // ==========================
        // Step 2: Mixing
        // D[x]=C[x-1]^ROT(C[x+1],1)
        // ==========================
        D0=C4^ROT(C1,6'd1);
        D1=C0^ROT(C2,6'd1);
        D2=C1^ROT(C3,6'd1);
        D3=C2^ROT(C4,6'd1);
        D4=C3^ROT(C0,6'd1);

        // ==========================
        // Step 3: Apply to all lanes
        // A[x][y]=Lane[x][y]^D[x]
        // ==========================
        A00=get_lane(state_in,3'd0,3'd0)^D0;
        A10=get_lane(state_in,3'd1,3'd0)^D1;
        A20=get_lane(state_in,3'd2,3'd0)^D2;
        A30=get_lane(state_in,3'd3,3'd0)^D3;
        A40=get_lane(state_in,3'd4,3'd0)^D4;
        A01=get_lane(state_in,3'd0,3'd1)^D0;
        A11=get_lane(state_in,3'd1,3'd1)^D1;
        A21=get_lane(state_in,3'd2,3'd1)^D2;
        A31=get_lane(state_in,3'd3,3'd1)^D3;
        A41=get_lane(state_in,3'd4,3'd1)^D4;
        A02=get_lane(state_in,3'd0,3'd2)^D0;
        A12=get_lane(state_in,3'd1,3'd2)^D1;
        A22=get_lane(state_in,3'd2,3'd2)^D2;
        A32=get_lane(state_in,3'd3,3'd2)^D3;
        A42=get_lane(state_in,3'd4,3'd2)^D4;
        A03=get_lane(state_in,3'd0,3'd3)^D0;
        A13=get_lane(state_in,3'd1,3'd3)^D1;
        A23=get_lane(state_in,3'd2,3'd3)^D2;
        A33=get_lane(state_in,3'd3,3'd3)^D3;
        A43=get_lane(state_in,3'd4,3'd3)^D4;
        A04=get_lane(state_in,3'd0,3'd4)^D0;
        A14=get_lane(state_in,3'd1,3'd4)^D1;
        A24=get_lane(state_in,3'd2,3'd4)^D2;
        A34=get_lane(state_in,3'd3,3'd4)^D3;
        A44=get_lane(state_in,3'd4,3'd4)^D4;

        // ==========================
        // Pack result
        // ==========================
        state_out[63:0]     =A00;
        state_out[127:64]   =A10;
        state_out[191:128]  =A20;
        state_out[255:192]  =A30;
        state_out[319:256]  =A40;
        state_out[383:320]  =A01;
        state_out[447:384]  =A11;
        state_out[511:448]  =A21;
        state_out[575:512]  =A31;
        state_out[639:576]  =A41;
        state_out[703:640]  =A02;
        state_out[767:704]  =A12;
        state_out[831:768]  =A22;
        state_out[895:832]  =A32;
        state_out[959:896]  =A42;
        state_out[1023:960] =A03;
        state_out[1087:1024]=A13;
        state_out[1151:1088]=A23;
        state_out[1215:1152]=A33;
        state_out[1279:1216]=A43;
        state_out[1343:1280]=A04;
        state_out[1407:1344]=A14;
        state_out[1471:1408]=A24;
        state_out[1535:1472]=A34;
        state_out[1599:1536]=A44;
    end

endmodule