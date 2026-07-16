`timescale 1ns / 1ps
// ============================================
// Block 2: PADDER UNIT
// SHA-3 Hardware Accelerator (SHA3-256)
// Multi-block support added.
// ============================================
// BUG FIX (intermediate block emission):
//
// The original code cleared block[0..16] with
// a for-loop at the same clock edge it set
// block[16] and asserted padd_done.
//
// Two problems with that:
//
// 1. NBA conflict: block[16] <= build_lane(...)
//    was overwritten by block[16] <= 0 from the
//    for-loop (last NBA wins). Word 17 became 0.
//
// 2. Message data destroyed: block[0..15] hold
//    words 1-16 accumulated over previous cycles.
//    Clearing them meant padded_block (combinational)
//    read {word17, 0, 0, ..., 0} when padd_done=1
//    the following cycle - completely wrong.
//
// FIX: Remove the for-loop entirely from the
// intermediate block path. block[0..16] are
// overwritten naturally as the next block's
// words arrive (word_cnt resets to 0 and each
// new word is stored in block[word_cnt]).
// ============================================

module padder (
    input  wire        clk,
    input  wire        rst_n,

    // From Block 1: Input Register
    input  wire [63:0] msg_in,          // MSB-packed big-endian word
    input  wire        valid_in,        // Word is valid
    input  wire        is_last,         // This is the last word
    input  wire [3:0]  byte_count,      // Valid bytes in last word (1-8)

    // To Block 3: State Formation
    output reg  [1087:0] padded_block,  // Full padded 1088-bit block
    output reg           padd_done,     // HIGH one cycle when block ready
    output reg           is_last_block  // HIGH when this is the final block
);

    parameter RATE_WORDS = 17; // SHA3-256

    // Internal word storage: 17 x 64-bit lanes
    reg [63:0] block [0:16];

    // Word counter: 0 to 16
    reg [4:0] word_cnt;

    integer i;

    // ----------------------------------------
    // build_lane:
    // Converts MSB-packed big-endian input
    // to little-endian Keccak lane.
    // Inserts 0x06 after valid bytes if last.
    // ----------------------------------------
    function [63:0] build_lane;
        input [63:0] msg;
        input [3:0]  valid_bytes;
        input [0:0]  last;

        reg [7:0]  b0, b1, b2, b3;
        reg [7:0]  b4, b5, b6, b7;
        reg [63:0] lane;

        begin
            b0 = msg[63:56];
            b1 = msg[55:48];
            b2 = msg[47:40];
            b3 = msg[39:32];
            b4 = msg[31:24];
            b5 = msg[23:16];
            b6 = msg[15:8];
            b7 = msg[7:0];

            case (valid_bytes)
                4'd0: lane = 64'h0000000000000000;
                4'd1: lane = {56'h00000000000000,            b0};
                4'd2: lane = {48'h000000000000,          b1, b0};
                4'd3: lane = {40'h0000000000,         b2, b1, b0};
                4'd4: lane = {32'h00000000,        b3, b2, b1, b0};
                4'd5: lane = {24'h000000,       b4, b3, b2, b1, b0};
                4'd6: lane = {16'h0000,     b5, b4, b3, b2, b1, b0};
                4'd7: lane = {8'h00,    b6, b5, b4, b3, b2, b1, b0};
                4'd8: lane = {b7, b6, b5, b4, b3, b2, b1, b0};
                default: lane = 64'h0000000000000000;
            endcase

            if (last) begin
                case (valid_bytes)
                    4'd0: lane[7:0]   = 8'h06;
                    4'd1: lane[15:8]  = 8'h06;
                    4'd2: lane[23:16] = 8'h06;
                    4'd3: lane[31:24] = 8'h06;
                    4'd4: lane[39:32] = 8'h06;
                    4'd5: lane[47:40] = 8'h06;
                    4'd6: lane[55:48] = 8'h06;
                    4'd7: lane[63:56] = 8'h06;
                    4'd8: ; // overflow - 0x06 goes in next word (not handled here)
                    default: ;
                endcase
            end

            build_lane = lane;
        end
    endfunction

    // ----------------------------------------
    // Sequential: word accumulation
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            word_cnt      <= 5'd0;
            padd_done     <= 1'b0;
            is_last_block <= 1'b0;
            for (i = 0; i < RATE_WORDS; i = i + 1)
                block[i] <= 64'h0000000000000000;
        end
        else begin
            padd_done     <= 1'b0; // default
            is_last_block <= 1'b0; // default

            if (valid_in) begin
                if (!is_last) begin
                    // ----------------------------------------
                    // Normal (non-last) word
                    // ----------------------------------------
                    if (word_cnt < (RATE_WORDS - 1)) begin
                        // Still filling the current block
                        block[word_cnt] <= build_lane(msg_in, 4'd8, 1'b0);
                        word_cnt        <= word_cnt + 1;
                    end
                    else begin
                        // word_cnt == 16: this word completes the block.
                        // Store word 17, emit the block, reset counter.
                        //
                        // FIX: Do NOT clear block[0..15] here.
                        // They hold words 1-16 accumulated over the
                        // previous 16 cycles and are needed by
                        // state_formation on the next cycle (padd_done=1).
                        // The next block's incoming words naturally
                        // overwrite block[0..16] as they arrive.
                        block[16]     <= build_lane(msg_in, 4'd8, 1'b0);
                        padd_done     <= 1'b1;
                        is_last_block <= 1'b0; // intermediate block
                        word_cnt      <= 5'd0;
                    end
                end
                else begin
                    // ----------------------------------------
                    // Last word of message: apply padding
                    // ----------------------------------------
                    if (word_cnt != 5'd16)
                        block[word_cnt] <= build_lane(msg_in, byte_count, 1'b1);

                    if (word_cnt == 5'd16)
                        block[16] <= build_lane(msg_in, byte_count, 1'b1)
                                     | 64'h8000000000000000;
                    else
                        block[16] <= 64'h8000000000000000;

                    word_cnt      <= 5'd0;
                    padd_done     <= 1'b1;
                    is_last_block <= 1'b1; // final block
                end
            end
        end
    end

    // ----------------------------------------
    // Combinational: assemble padded_block
    // ----------------------------------------
    always @(*) begin
        padded_block = {
            block[16], block[15], block[14], block[13],
            block[12], block[11], block[10], block[9],
            block[8],  block[7],  block[6],  block[5],
            block[4],  block[3],  block[2],  block[1],
            block[0]
        };
    end

endmodule