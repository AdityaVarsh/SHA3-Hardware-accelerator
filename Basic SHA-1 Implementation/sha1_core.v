`timescale 1ns/1ps
// ============================================
// Block 3+4: SHA-1 CORE
// (replaces state_formation + keccak_f +
//  keccak_round + theta/rho/pi/chi/iota)
// ============================================
// SHA-1 has no permutation steps. One module does
// the whole compression of a 512-bit block:
//
//   * 16-word circular message schedule (W),
//     computed on the fly:
//       W[t] = M[t]                       , t<16
//       W[t] = ROTL1(W[t-3]^W[t-8]
//                    ^W[t-14]^W[t-16])    , t>=16
//     -> only 16 x 32 = 512 FF, not 80 x 32.
//
//   * 80 rounds, one per clock:
//       T = ROTL5(a) + f(t,b,c,d) + e + K(t) + W[t]
//       e=d; d=c; c=ROTL30(b); b=a; a=T
//
//   * f / K change every 20 rounds (FIPS 180-4).
//
// Multi-block support:
//   first_block = 1 -> initialise H to constants
//   first_block = 0 -> continue from current H
//   last_block       -> latched; drives done/hash_out
//
// Latency: ~83 clocks/block (load + 80 + finalise).
//
// Block packing (matches sha1_padder, big-endian):
//   w[0] = block_in[511:480] = M[0]
//   w[15]= block_in[31:0]    = M[15]
//
// Digest (big-endian, H0 first):
//   hash_out[159:128]=H0 ... hash_out[31:0]=H4
// ============================================

module sha1_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [511:0] block_in,
    input  wire         start,        // 1-cycle pulse
    input  wire         first_block,  // init H if 1
    input  wire         last_block,   // emit digest after this block
    output reg  [159:0] hash_out,
    output reg          done
);

    // SHA-1 initial hash value (FIPS 180-4)
    localparam [31:0] IH0 = 32'h67452301;
    localparam [31:0] IH1 = 32'hEFCDAB89;
    localparam [31:0] IH2 = 32'h98BADCFE;
    localparam [31:0] IH3 = 32'h10325476;
    localparam [31:0] IH4 = 32'hC3D2E1F0;

    // round constants
    localparam [31:0] K0 = 32'h5A827999; // t  0..19
    localparam [31:0] K1 = 32'h6ED9EBA1; // t 20..39
    localparam [31:0] K2 = 32'h8F1BBCDC; // t 40..59
    localparam [31:0] K3 = 32'hCA62C1D6; // t 60..79

    reg [31:0] H0,H1,H2,H3,H4;
    reg [31:0] a,b,c,d,e;
    reg [31:0] w [0:15];
    reg [6:0]  rnd;          // 0..79
    reg        last_r;

    localparam IDLE=2'd0, RUN=2'd1, FIN=2'd2;
    reg [1:0] st;

    integer i;

    // 32-bit left-rotate
    function [31:0] ROTL;
        input [31:0] x; input [5:0] n;
        begin ROTL = (x << n) | (x >> (6'd32 - n)); end
    endfunction

    // combinational round signals
    reg  [3:0]  idx;
    reg  [31:0] wt, ft, kt, tt;

    always @(*) begin
        idx = rnd[3:0];
        // message schedule word for this round
        if (rnd < 7'd16)
            wt = w[idx];
        else
            wt = ROTL( w[(idx-4'd3)] ^ w[(idx-4'd8)]
                     ^ w[(idx-4'd14)] ^ w[idx], 6'd1 ); // w[idx]=W[t-16]

        // f-function and constant by quarter
        if (rnd < 7'd20) begin
            ft = (b & c) | ((~b) & d);          // Ch
            kt = K0;
        end else if (rnd < 7'd40) begin
            ft = b ^ c ^ d;                      // Parity
            kt = K1;
        end else if (rnd < 7'd60) begin
            ft = (b & c) | (b & d) | (c & d);    // Maj
            kt = K2;
        end else begin
            ft = b ^ c ^ d;                      // Parity
            kt = K3;
        end

        tt = ROTL(a,6'd5) + ft + e + kt + wt;    // mod 2^32
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= IDLE;
            done     <= 1'b0;
            hash_out <= 160'd0;
            rnd      <= 7'd0;
            last_r   <= 1'b0;
            {H0,H1,H2,H3,H4} <= {IH0,IH1,IH2,IH3,IH4};
            {a,b,c,d,e}      <= {IH0,IH1,IH2,IH3,IH4};
            for (i=0;i<16;i=i+1) w[i] <= 32'd0;
        end
        else begin
            done <= 1'b0;
            case (st)
            IDLE: begin
                if (start) begin
                    last_r <= last_block;
                    // initialise / continue chaining variables
                    if (first_block) begin
                        {H0,H1,H2,H3,H4} <= {IH0,IH1,IH2,IH3,IH4};
                        {a,b,c,d,e}      <= {IH0,IH1,IH2,IH3,IH4};
                    end else begin
                        {a,b,c,d,e}      <= {H0,H1,H2,H3,H4};
                    end
                    // load the 16 message words (big-endian)
                    for (i=0;i<16;i=i+1)
                        w[i] <= block_in[511 - 32*i -: 32];
                    rnd <= 7'd0;
                    st  <= RUN;
                end
            end
            RUN: begin
                // advance chaining variables
                e <= d;
                d <= c;
                c <= ROTL(b,6'd30);
                b <= a;
                a <= tt;
                // store schedule word back into circular buffer
                w[idx] <= wt;
                if (rnd == 7'd79) st <= FIN;
                else             rnd <= rnd + 7'd1;
            end
            FIN: begin
                H0 <= H0 + a;  H1 <= H1 + b;  H2 <= H2 + c;
                H3 <= H3 + d;  H4 <= H4 + e;
                if (last_r) begin
                    hash_out <= {H0+a, H1+b, H2+c, H3+d, H4+e};
                    done     <= 1'b1;
                end
                st <= IDLE;
            end
            endcase
        end
    end

endmodule
