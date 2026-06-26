`timescale 1ns/1ps
// ============================================
// sha1_core_opt : area-optimised variant
// ============================================
// Same behaviour as sha1_core, but the message
// schedule is a SHIFT REGISTER with FIXED taps
// instead of a circular buffer with a moving index.
//
//   consume  : Wt = m[0]
//   feedback : new = ROTL1(m[0]^m[2]^m[8]^m[13])
//   shift    : m[i]<=m[i+1]; m[15]<=new
//
// Because the taps (0,2,8,13) never move, the 16:1
// dynamic read-muxes of the indexed version collapse
// into fixed wiring -> large LUT saving in the core.
// ============================================

module sha1_core_opt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [511:0] block_in,
    input  wire         start,
    input  wire         first_block,
    input  wire         last_block,
    output reg  [159:0] hash_out,
    output reg          done
);
    localparam [31:0] IH0=32'h67452301, IH1=32'hEFCDAB89, IH2=32'h98BADCFE,
                      IH3=32'h10325476, IH4=32'hC3D2E1F0;
    localparam [31:0] K0=32'h5A827999, K1=32'h6ED9EBA1,
                      K2=32'h8F1BBCDC, K3=32'hCA62C1D6;

    reg [31:0] H0,H1,H2,H3,H4;
    reg [31:0] a,b,c,d,e;
    reg [31:0] m [0:15];
    reg [6:0]  rnd;
    reg        last_r;
    localparam IDLE=2'd0, RUN=2'd1, FIN=2'd2;
    reg [1:0] st;
    integer i;

    function [31:0] ROTL; input [31:0] x; input [5:0] n;
        begin ROTL=(x<<n)|(x>>(6'd32-n)); end endfunction

    reg [31:0] wt, ft, kt, tt, neww;
    always @(*) begin
        wt   = m[0];                                   // fixed tap
        neww = ROTL(m[0]^m[2]^m[8]^m[13], 6'd1);       // fixed taps
        if      (rnd<7'd20) begin ft=(b&c)|((~b)&d);            kt=K0; end
        else if (rnd<7'd40) begin ft=b^c^d;                    kt=K1; end
        else if (rnd<7'd60) begin ft=(b&c)|(b&d)|(c&d);        kt=K2; end
        else                begin ft=b^c^d;                    kt=K3; end
        tt = ROTL(a,6'd5) + ft + e + kt + wt;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=IDLE; done<=1'b0; hash_out<=160'd0; rnd<=7'd0; last_r<=1'b0;
            {H0,H1,H2,H3,H4}<={IH0,IH1,IH2,IH3,IH4};
            {a,b,c,d,e}<={IH0,IH1,IH2,IH3,IH4};
            for(i=0;i<16;i=i+1) m[i]<=32'd0;
        end else begin
            done<=1'b0;
            case(st)
            IDLE: if (start) begin
                last_r<=last_block;
                if (first_block) begin
                    {H0,H1,H2,H3,H4}<={IH0,IH1,IH2,IH3,IH4};
                    {a,b,c,d,e}<={IH0,IH1,IH2,IH3,IH4};
                end else {a,b,c,d,e}<={H0,H1,H2,H3,H4};
                for(i=0;i<16;i=i+1) m[i]<=block_in[511-32*i -:32];
                rnd<=7'd0; st<=RUN;
            end
            RUN: begin
                e<=d; d<=c; c<=ROTL(b,6'd30); b<=a; a<=tt;
                for(i=0;i<15;i=i+1) m[i]<=m[i+1];      // shift
                m[15]<=neww;                           // append
                if (rnd==7'd79) st<=FIN; else rnd<=rnd+7'd1;
            end
            FIN: begin
                H0<=H0+a; H1<=H1+b; H2<=H2+c; H3<=H3+d; H4<=H4+e;
                if (last_r) begin
                    hash_out<={H0+a,H1+b,H2+c,H3+d,H4+e}; done<=1'b1;
                end
                st<=IDLE;
            end
            endcase
        end
    end
endmodule
