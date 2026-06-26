`timescale 1ns/1ps
// ============================================
// SHA-1 TOP MODULE  (was: sha3_top.v)
// ============================================
//   input_register -> sha1_padder -> sha1_core
//
// Single-block messages (all three test vectors)
// work end to end. For multi-block messages the
// top would need to hold off the padder while the
// core is busy (80+ cycles/block) -- the same
// streaming gap the SHA-3 top still has. The
// first_block / last_block plumbing below is the
// hook for that future work.
//
// NOTE: SHA-1 needs NO output byte-swap. The SHA-3
// top byte-reversed each lane (little-endian Keccak);
// SHA-1 is big-endian throughout, so the digest is
// emitted directly.
// ============================================

module sha1_top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [63:0]  msg_in,
    input  wire         valid_in,
    input  wire         is_last,
    input  wire [3:0]   byte_count,
    output reg  [159:0] hash_out,
    output reg          hash_valid
);

    // input_register -> padder
    wire [63:0] w_msg;
    wire        w_valid, w_last;
    wire [3:0]  w_bc;

    // padder -> core
    wire [511:0] w_block;
    wire         w_padd_done;
    wire         w_is_last_block;

    // core output
    wire [159:0] w_hash;
    wire         w_done;

    // first/last-block tracking for the core
    reg  msg_first;          // 1 = next dispatched block is the message's first
    reg  core_start;
    reg  core_first, core_last;

    // ----------------------------------------
    input_register u_input_register (
        .clk(clk), .rst_n(rst_n),
        .msg_in(msg_in), .valid_in(valid_in),
        .is_last(is_last), .byte_count(byte_count),
        .msg_out(w_msg), .valid_out(w_valid),
        .last_out(w_last), .byte_count_out(w_bc)
    );

    sha1_padder u_padder (
        .clk(clk), .rst_n(rst_n),
        .msg_in(w_msg), .valid_in(w_valid),
        .is_last(w_last), .byte_count(w_bc),
        .block_out(w_block), .padd_done(w_padd_done),
        .is_last_block(w_is_last_block)
    );

    sha1_core u_core (
        .clk(clk), .rst_n(rst_n),
        .block_in(w_block), .start(core_start),
        .first_block(core_first), .last_block(core_last),
        .hash_out(w_hash), .done(w_done)
    );

    // ----------------------------------------
    // dispatch a block to the core on padd_done
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_first  <= 1'b1;
            core_start <= 1'b0;
            core_first <= 1'b0;
            core_last  <= 1'b0;
        end
        else begin
            core_start <= 1'b0;          // 1-cycle pulse
            if (w_padd_done) begin
                core_start <= 1'b1;
                core_first <= msg_first;
                core_last  <= w_is_last_block;
                // after the final block, the next block starts a new message
                msg_first  <= w_is_last_block ? 1'b1 : 1'b0;
            end
        end
    end

    // ----------------------------------------
    // latch the digest when the core finishes
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hash_out   <= 160'd0;
            hash_valid <= 1'b0;
        end
        else begin
            hash_valid <= 1'b0;
            if (w_done) begin
                hash_out   <= w_hash;
                hash_valid <= 1'b1;
            end
        end
    end

endmodule
