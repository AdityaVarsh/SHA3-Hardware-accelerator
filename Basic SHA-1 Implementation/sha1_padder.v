`timescale 1ns/1ps
// ============================================
// Block 2: SHA-1 PADDER  (was: padder.v)
// ============================================
// SHA-1 differs from SHA-3 padding in three ways:
//
//   1. Block size is 512 bits = 8 x 64-bit words
//      (SHA-3 rate was 1088 bits = 17 lanes).
//   2. The pad byte is 0x80 (a single '1' bit then
//      zeros), NOT 0x06. There is no domain byte.
//   3. The 64-bit big-endian MESSAGE BIT-LENGTH is
//      appended in the final 8 bytes of the last
//      block. SHA-3 had no length field.
//
// Also: SHA-1 processes the message big-endian, so
// (unlike the SHA-3 build_lane) there is NO byte
// swap. The first byte received is the MSB of M[0].
//
// In 64-bit-word terms the length lands neatly in
// the 8th word (wblk[7]) of the block:
//   block_out[63:32] = M[14] = length[63:32]
//   block_out[31:0]  = M[15] = length[31:0]
//
// Output packing (big-endian, M[0] in the MSBs):
//   block_out = { word0, word1, ..., word7 }
//   block_out[511:480] = M[0], block_out[31:0] = M[15]
//
// LIMITATION (documented, same gap as SHA-3 top):
//   When the data + 0x80 leave no room for the
//   length, a SECOND block is required. That path
//   IS implemented here (state EMIT2), but the
//   simple sha1_top does not yet sequence two
//   blocks against an 80-cycle-busy core. All three
//   provided test vectors are single-block, so this
//   does not affect them. Multi-block streaming
//   needs core-ready back-pressure at the top.
// ============================================

module sha1_padder (
    input  wire        clk,
    input  wire        rst_n,

    // From Block 1: Input Register
    input  wire [63:0] msg_in,        // big-endian word (first byte = MSB)
    input  wire        valid_in,
    input  wire        is_last,
    input  wire [3:0]  byte_count,    // valid bytes in last word (0-8)

    // To Block 3: SHA-1 core
    output reg  [511:0] block_out,    // full 512-bit block
    output reg          padd_done,    // HIGH one cycle when block ready
    output reg          is_last_block // HIGH when this is the final block
);

    // 8 x 64-bit word storage for the block under construction.
    // Only indices 0..6 are ever stored here; index 7 is always
    // supplied live (msg_in) at emit time, so there is no stale
    // combinational read (the bug class your SHA-3 padder hit).
    reg [63:0] wblk [0:6];
    reg [2:0]  word_cnt;     // 0..7 position of next incoming word
    reg [63:0] msg_bits;     // running message length in BITS

    // Pending state for the 2-block path
    reg [63:0] pend_len;
    reg        pend_80;      // 1 => 0x80 still needs to go in block-2 word0

    localparam COLLECT = 1'b0,
               EMIT2   = 1'b1;
    reg state;

    integer i;

    // ----------------------------------------
    // build_last: place 0x80 right after the valid
    // bytes of the final (partial) word. Big-endian:
    // valid bytes occupy the top, 0x80 follows.
    // For byte_count==8 the word is full data and
    // 0x80 must spill into the next word (handled by
    // the caller, not here).
    // ----------------------------------------
    function [63:0] build_last;
        input [63:0] m;
        input [3:0]  k;
        begin
            case (k)
                4'd0: build_last = 64'h8000000000000000;
                4'd1: build_last = {m[63:56], 8'h80, 48'h0};
                4'd2: build_last = {m[63:48], 8'h80, 40'h0};
                4'd3: build_last = {m[63:40], 8'h80, 32'h0};
                4'd4: build_last = {m[63:32], 8'h80, 24'h0};
                4'd5: build_last = {m[63:24], 8'h80, 16'h0};
                4'd6: build_last = {m[63:16], 8'h80, 8'h0};
                4'd7: build_last = {m[63:8],  8'h80};
                4'd8: build_last = m;            // full word; 0x80 spills
                default: build_last = 64'h8000000000000000;
            endcase
        end
    endfunction

    // next-block assembly scratch
    reg [63:0] nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7;
    reg [63:0] lastword;
    reg [63:0] len_now;
    reg [2:0]  p;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_cnt      <= 3'd0;
            msg_bits      <= 64'd0;
            padd_done     <= 1'b0;
            is_last_block <= 1'b0;
            block_out     <= 512'd0;
            pend_len      <= 64'd0;
            pend_80       <= 1'b0;
            state         <= COLLECT;
            for (i=0;i<7;i=i+1) wblk[i] <= 64'd0;
        end
        else begin
            padd_done     <= 1'b0;   // default: single-cycle pulse
            is_last_block <= 1'b0;

            case (state)
            // ============================================
            COLLECT: begin
                if (valid_in) begin
                    if (!is_last) begin
                        // ---- normal full 64-bit data word ----
                        if (word_cnt < 3'd7) begin
                            wblk[word_cnt] <= msg_in;
                            word_cnt       <= word_cnt + 3'd1;
                            msg_bits       <= msg_bits + 64'd64;
                        end
                        else begin
                            // 8th word completes a full data block
                            block_out     <= {wblk[0],wblk[1],wblk[2],wblk[3],
                                              wblk[4],wblk[5],wblk[6], msg_in};
                            padd_done     <= 1'b1;
                            is_last_block <= 1'b0;
                            word_cnt      <= 3'd0;
                            msg_bits      <= msg_bits + 64'd64;
                        end
                    end
                    else begin
                        // ---- last word: apply SHA-1 padding ----
                        p        = word_cnt;
                        lastword = build_last(msg_in, byte_count);
                        len_now  = msg_bits + ({60'd0, byte_count} << 3); // +bytes*8

                        // start from stored data + zeros
                        nb0 = (p>3'd0)?wblk[0]:64'd0;
                        nb1 = (p>3'd1)?wblk[1]:64'd0;
                        nb2 = (p>3'd2)?wblk[2]:64'd0;
                        nb3 = (p>3'd3)?wblk[3]:64'd0;
                        nb4 = (p>3'd4)?wblk[4]:64'd0;
                        nb5 = (p>3'd5)?wblk[5]:64'd0;
                        nb6 = (p>3'd6)?wblk[6]:64'd0;
                        nb7 = 64'd0;

                        if (byte_count != 4'd8) begin
                            // 0x80 fits inside the partial last word at p
                            case (p)
                              3'd0: nb0 = lastword; 3'd1: nb1 = lastword;
                              3'd2: nb2 = lastword; 3'd3: nb3 = lastword;
                              3'd4: nb4 = lastword; 3'd5: nb5 = lastword;
                              3'd6: nb6 = lastword; 3'd7: nb7 = lastword;
                            endcase
                            if (p <= 3'd6) begin
                                // single block: length in word7
                                nb7 = len_now;
                                block_out <= {nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7};
                                padd_done <= 1'b1; is_last_block <= 1'b1;
                                word_cnt <= 3'd0; msg_bits <= 64'd0;
                            end
                            else begin
                                // p==7: data+0x80 fills word7, length -> block2
                                block_out <= {nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7};
                                padd_done <= 1'b1; is_last_block <= 1'b0;
                                pend_len <= len_now; pend_80 <= 1'b0;
                                state <= EMIT2;
                            end
                        end
                        else begin
                            // byte_count==8: last word is full data; 0x80 spills
                            case (p)
                              3'd0: nb0 = msg_in; 3'd1: nb1 = msg_in;
                              3'd2: nb2 = msg_in; 3'd3: nb3 = msg_in;
                              3'd4: nb4 = msg_in; 3'd5: nb5 = msg_in;
                              3'd6: nb6 = msg_in; 3'd7: nb7 = msg_in;
                            endcase
                            if (p <= 3'd5) begin
                                // 0x80 word at p+1, length in word7, single block
                                case (p)
                                  3'd0: nb1 = 64'h8000000000000000;
                                  3'd1: nb2 = 64'h8000000000000000;
                                  3'd2: nb3 = 64'h8000000000000000;
                                  3'd3: nb4 = 64'h8000000000000000;
                                  3'd4: nb5 = 64'h8000000000000000;
                                  3'd5: nb6 = 64'h8000000000000000;
                                endcase
                                nb7 = len_now;
                                block_out <= {nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7};
                                padd_done <= 1'b1; is_last_block <= 1'b1;
                                word_cnt <= 3'd0; msg_bits <= 64'd0;
                            end
                            else if (p == 3'd6) begin
                                // 0x80 fits in word7, length -> block2
                                nb7 = 64'h8000000000000000;
                                block_out <= {nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7};
                                padd_done <= 1'b1; is_last_block <= 1'b0;
                                pend_len <= len_now; pend_80 <= 1'b0;
                                state <= EMIT2;
                            end
                            else begin
                                // p==7: 8 full data words, 0x80 -> block2 word0
                                block_out <= {nb0,nb1,nb2,nb3,nb4,nb5,nb6,nb7};
                                padd_done <= 1'b1; is_last_block <= 1'b0;
                                pend_len <= len_now; pend_80 <= 1'b1;
                                state <= EMIT2;
                            end
                        end
                    end
                end
            end
            // ============================================
            EMIT2: begin
                block_out <= { (pend_80 ? 64'h8000000000000000 : 64'd0),
                               64'd0,64'd0,64'd0,64'd0,64'd0,64'd0,
                               pend_len };
                padd_done     <= 1'b1;
                is_last_block <= 1'b1;
                word_cnt      <= 3'd0;
                msg_bits      <= 64'd0;
                state         <= COLLECT;
            end
            endcase
        end
    end

endmodule
