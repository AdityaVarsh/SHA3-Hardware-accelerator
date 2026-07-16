`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 04:39:00
// Design Name:
// Module Name: round_unit
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
// Block 4: ROUND UNIT (Keccak-f)
// SHA-3 Hardware Accelerator (SHA3-256)
// ============================================
// Performs 24 rounds of Keccak-f permutation.
// Each round: θ → ρ → π → χ → ι
// Iterative architecture: one round per cycle.
// Latency: 24 clock cycles after state_valid.
//
// State: 1600 bits = 5x5 matrix of 64-bit lanes
// Lane[x][y] at bits [64*(5y+x)+63 : 64*(5y+x)]
//
// All loops/2D arrays fully expanded for
// Verilog-2001 compatibility.
// All rotation constants use 6-bit literals.
// ROT uses 7-bit arithmetic to avoid overflow.
// ============================================

module round_unit (
    input  wire          clk,
    input  wire          rst_n,

    // From Block 3: State Formation
    input  wire [1599:0] state,        // 1600-bit initial state
    input  wire          state_valid,  // HIGH one cycle: state ready

    // To Block 3: feedback / Block 5: output
    output reg  [1599:0] hash_out,     // State after 24 rounds
    output reg           hash_valid,   // HIGH one cycle when done

    // Waveform visibility
    output reg  [4:0]    round_cnt     // Current round number 0-23
);

    // Internal state register
    reg [1599:0] s;
    reg          running;

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
    // ROT: 64-bit left rotation by n bits
    // Uses 7-bit intermediate to avoid
    // 6-bit overflow when computing 64-n
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
    // get_lane: extract Lane[x][y] from state
    // Uses case statement - no variable
    // part-select for Verilog-2001 compat.
    // Lane[x][y] = state[64*(5y+x) +: 64]
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
    // keccak_f: one complete round
    // θ → ρ → π → χ → ι
    // All 2D arrays flattened to named vars.
    // All loops fully unrolled.
    // All rotation constants use 6'd prefix.
    // All get_lane calls use 3'd prefix.
    // ----------------------------------------
    function [1599:0] keccak_f;
        input [1599:0] st;
        input [4:0]    rnd;

        // θ: column parities and mixing
        reg [63:0] C0,C1,C2,C3,C4;
        reg [63:0] D0,D1,D2,D3,D4;

        // After θ: A[x][y] → named Axy
        reg [63:0] A00,A10,A20,A30,A40;
        reg [63:0] A01,A11,A21,A31,A41;
        reg [63:0] A02,A12,A22,A32,A42;
        reg [63:0] A03,A13,A23,A33,A43;
        reg [63:0] A04,A14,A24,A34,A44;

        // After ρ: Ar[x][y] → named Arxy
        reg [63:0] Ar00,Ar10,Ar20,Ar30,Ar40;
        reg [63:0] Ar01,Ar11,Ar21,Ar31,Ar41;
        reg [63:0] Ar02,Ar12,Ar22,Ar32,Ar42;
        reg [63:0] Ar03,Ar13,Ar23,Ar33,Ar43;
        reg [63:0] Ar04,Ar14,Ar24,Ar34,Ar44;

        // After π: Ap[x][y] → named Apxy
        reg [63:0] Ap00,Ap10,Ap20,Ap30,Ap40;
        reg [63:0] Ap01,Ap11,Ap21,Ap31,Ap41;
        reg [63:0] Ap02,Ap12,Ap22,Ap32,Ap42;
        reg [63:0] Ap03,Ap13,Ap23,Ap33,Ap43;
        reg [63:0] Ap04,Ap14,Ap24,Ap34,Ap44;

        // After χ and ι: Ac[x][y] → named Acxy
        reg [63:0] Ac00,Ac10,Ac20,Ac30,Ac40;
        reg [63:0] Ac01,Ac11,Ac21,Ac31,Ac41;
        reg [63:0] Ac02,Ac12,Ac22,Ac32,Ac42;
        reg [63:0] Ac03,Ac13,Ac23,Ac33,Ac43;
        reg [63:0] Ac04,Ac14,Ac24,Ac34,Ac44;

        reg [1599:0] out;

        begin
            // ============================
            // θ Step 1: column parities
            // C[x] = XOR of all lanes
            //        in column x (y=0..4)
            // ============================
            C0=get_lane(st,3'd0,3'd0)
              ^get_lane(st,3'd0,3'd1)
              ^get_lane(st,3'd0,3'd2)
              ^get_lane(st,3'd0,3'd3)
              ^get_lane(st,3'd0,3'd4);
            C1=get_lane(st,3'd1,3'd0)
              ^get_lane(st,3'd1,3'd1)
              ^get_lane(st,3'd1,3'd2)
              ^get_lane(st,3'd1,3'd3)
              ^get_lane(st,3'd1,3'd4);
            C2=get_lane(st,3'd2,3'd0)
              ^get_lane(st,3'd2,3'd1)
              ^get_lane(st,3'd2,3'd2)
              ^get_lane(st,3'd2,3'd3)
              ^get_lane(st,3'd2,3'd4);
            C3=get_lane(st,3'd3,3'd0)
              ^get_lane(st,3'd3,3'd1)
              ^get_lane(st,3'd3,3'd2)
              ^get_lane(st,3'd3,3'd3)
              ^get_lane(st,3'd3,3'd4);
            C4=get_lane(st,3'd4,3'd0)
              ^get_lane(st,3'd4,3'd1)
              ^get_lane(st,3'd4,3'd2)
              ^get_lane(st,3'd4,3'd3)
              ^get_lane(st,3'd4,3'd4);

            // ============================
            // θ Step 2: mixing
            // D[x]=C[x-1]^ROT(C[x+1],1)
            // indices mod 5
            // ============================
            D0=C4^ROT(C1,6'd1);
            D1=C0^ROT(C2,6'd1);
            D2=C1^ROT(C3,6'd1);
            D3=C2^ROT(C4,6'd1);
            D4=C3^ROT(C0,6'd1);

            // ============================
            // θ Step 3: apply to all lanes
            // A[x][y] = Lane[x][y] ^ D[x]
            // ============================
            A00=get_lane(st,3'd0,3'd0)^D0;
            A10=get_lane(st,3'd1,3'd0)^D1;
            A20=get_lane(st,3'd2,3'd0)^D2;
            A30=get_lane(st,3'd3,3'd0)^D3;
            A40=get_lane(st,3'd4,3'd0)^D4;
            A01=get_lane(st,3'd0,3'd1)^D0;
            A11=get_lane(st,3'd1,3'd1)^D1;
            A21=get_lane(st,3'd2,3'd1)^D2;
            A31=get_lane(st,3'd3,3'd1)^D3;
            A41=get_lane(st,3'd4,3'd1)^D4;
            A02=get_lane(st,3'd0,3'd2)^D0;
            A12=get_lane(st,3'd1,3'd2)^D1;
            A22=get_lane(st,3'd2,3'd2)^D2;
            A32=get_lane(st,3'd3,3'd2)^D3;
            A42=get_lane(st,3'd4,3'd2)^D4;
            A03=get_lane(st,3'd0,3'd3)^D0;
            A13=get_lane(st,3'd1,3'd3)^D1;
            A23=get_lane(st,3'd2,3'd3)^D2;
            A33=get_lane(st,3'd3,3'd3)^D3;
            A43=get_lane(st,3'd4,3'd3)^D4;
            A04=get_lane(st,3'd0,3'd4)^D0;
            A14=get_lane(st,3'd1,3'd4)^D1;
            A24=get_lane(st,3'd2,3'd4)^D2;
            A34=get_lane(st,3'd3,3'd4)^D3;
            A44=get_lane(st,3'd4,3'd4)^D4;

            // ============================
            // ρ: bitwise rotation
            // FIPS-202 offsets, 6'd prefix
            // ============================
            Ar00=ROT(A00,6'd0);  Ar10=ROT(A10,6'd1);
            Ar20=ROT(A20,6'd62); Ar30=ROT(A30,6'd28);
            Ar40=ROT(A40,6'd27); Ar01=ROT(A01,6'd36);
            Ar11=ROT(A11,6'd44); Ar21=ROT(A21,6'd6);
            Ar31=ROT(A31,6'd55); Ar41=ROT(A41,6'd20);
            Ar02=ROT(A02,6'd3);  Ar12=ROT(A12,6'd10);
            Ar22=ROT(A22,6'd43); Ar32=ROT(A32,6'd25);
            Ar42=ROT(A42,6'd39); Ar03=ROT(A03,6'd41);
            Ar13=ROT(A13,6'd45); Ar23=ROT(A23,6'd15);
            Ar33=ROT(A33,6'd21); Ar43=ROT(A43,6'd8);
            Ar04=ROT(A04,6'd18); Ar14=ROT(A14,6'd2);
            Ar24=ROT(A24,6'd61); Ar34=ROT(A34,6'd56);
            Ar44=ROT(A44,6'd14);

            // ============================
            // π: lane permutation
            // new[y][2x+3y mod5]=old[x][y]
            // All 25 entries verified against
            // FIPS-202 formula
            // ============================
            Ap00=Ar00; Ap10=Ar11; Ap20=Ar22;
            Ap30=Ar33; Ap40=Ar44; Ap01=Ar30;
            Ap11=Ar41; Ap21=Ar02; Ap31=Ar13;
            Ap41=Ar24; Ap02=Ar10; Ap12=Ar21;
            Ap22=Ar32; Ap32=Ar43; Ap42=Ar04;
            Ap03=Ar40; Ap13=Ar01; Ap23=Ar12;
            Ap33=Ar23; Ap43=Ar34; Ap04=Ar20;
            Ap14=Ar31; Ap24=Ar42; Ap34=Ar03;
            Ap44=Ar14;

            // ============================
            // χ: non-linear step
            // A'[x][y] = A[x][y] ^
            // ((~A[x+1 mod5][y]) &
            //   A[x+2 mod5][y])
            // All 5 rows fully expanded
            // ============================
            // Row y=0
            Ac00=Ap00^((~Ap10)&Ap20);
            Ac10=Ap10^((~Ap20)&Ap30);
            Ac20=Ap20^((~Ap30)&Ap40);
            Ac30=Ap30^((~Ap40)&Ap00);
            Ac40=Ap40^((~Ap00)&Ap10);
            // Row y=1
            Ac01=Ap01^((~Ap11)&Ap21);
            Ac11=Ap11^((~Ap21)&Ap31);
            Ac21=Ap21^((~Ap31)&Ap41);
            Ac31=Ap31^((~Ap41)&Ap01);
            Ac41=Ap41^((~Ap01)&Ap11);
            // Row y=2
            Ac02=Ap02^((~Ap12)&Ap22);
            Ac12=Ap12^((~Ap22)&Ap32);
            Ac22=Ap22^((~Ap32)&Ap42);
            Ac32=Ap32^((~Ap42)&Ap02);
            Ac42=Ap42^((~Ap02)&Ap12);
            // Row y=3
            Ac03=Ap03^((~Ap13)&Ap23);
            Ac13=Ap13^((~Ap23)&Ap33);
            Ac23=Ap23^((~Ap33)&Ap43);
            Ac33=Ap33^((~Ap43)&Ap03);
            Ac43=Ap43^((~Ap03)&Ap13);
            // Row y=4
            Ac04=Ap04^((~Ap14)&Ap24);
            Ac14=Ap14^((~Ap24)&Ap34);
            Ac24=Ap24^((~Ap34)&Ap44);
            Ac34=Ap34^((~Ap44)&Ap04);
            Ac44=Ap44^((~Ap04)&Ap14);

            // ============================
            // ι: XOR round constant into
            // Lane[0][0] only, after χ
            // ============================
            Ac00 = Ac00 ^ get_rc(rnd);

            // ============================
            // Pack: 25 explicit assignments
            // Lane[x][y]→out[64*(5y+x)+:64]
            // ============================
            out[63:0]     =Ac00; out[127:64]   =Ac10;
            out[191:128]  =Ac20; out[255:192]  =Ac30;
            out[319:256]  =Ac40; out[383:320]  =Ac01;
            out[447:384]  =Ac11; out[511:448]  =Ac21;
            out[575:512]  =Ac31; out[639:576]  =Ac41;
            out[703:640]  =Ac02; out[767:704]  =Ac12;
            out[831:768]  =Ac22; out[895:832]  =Ac32;
            out[959:896]  =Ac42; out[1023:960] =Ac03;
            out[1087:1024]=Ac13; out[1151:1088]=Ac23;
            out[1215:1152]=Ac33; out[1279:1216]=Ac43;
            out[1343:1280]=Ac04; out[1407:1344]=Ac14;
            out[1471:1408]=Ac24; out[1535:1472]=Ac34;
            out[1599:1536]=Ac44;

            keccak_f = out;
        end
    endfunction

    // ----------------------------------------
    // Combinational: next round result
    // state_valid has higher priority than
    // running - handles restart correctly
    // ----------------------------------------
    wire [1599:0] next_round;
    assign next_round = state_valid ? keccak_f(state, 5'd0)  :
                        running     ? keccak_f(s, round_cnt) :
                        1600'b0;

    // ----------------------------------------
    // Sequential: iterative 24 rounds
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s          <= 1600'b0;
            hash_out   <= 1600'b0;
            hash_valid <= 1'b0;
            round_cnt  <= 5'd0;
            running    <= 1'b0;
        end
        else begin
            hash_valid <= 1'b0; // default

            if (state_valid) begin
                // Load state, apply round 0
                s         <= next_round;
                round_cnt <= 5'd1;
                running   <= 1'b1;
            end
            else if (running) begin
                if (round_cnt < 5'd23) begin
                    // Rounds 1-22
                    s         <= next_round;
                    round_cnt <= round_cnt + 1;
                end
                else begin
                    // Round 23: final
                    s          <= next_round;
                    hash_out   <= next_round;
                    hash_valid <= 1'b1;
                    running    <= 1'b0;
                    round_cnt  <= 5'd0;
                end
            end
        end
    end

endmodule