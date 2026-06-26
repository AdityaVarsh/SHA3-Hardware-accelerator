`timescale 1ns/1ps
// ============================================
// SHA3-256 Top Module - Iterative keccak_f
// ============================================
module sha3_top (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [63:0]  msg_in,
    input  wire         valid_in,
    input  wire         is_last,
    input  wire [3:0]   byte_count,
    output reg  [255:0] hash_out,
    output reg          hash_valid
);

    // ----------------------------------------
    // Wires: Block 1 → Block 2
    // ----------------------------------------
    wire [63:0]   w_msg;
    wire          w_valid;
    wire          w_last;
    wire [3:0]    w_byte_count;

    // ----------------------------------------
    // Wires: Block 2 → Block 3
    // ----------------------------------------
    wire [1087:0] w_padded_block;
    wire          w_padd_done;

    // ----------------------------------------
    // Wires: Block 3 → Block 4
    // ----------------------------------------
    wire [1599:0] w_state;
    wire          w_state_valid;

    // ----------------------------------------
    // Wires: Block 4 output
    // ----------------------------------------
    wire [1599:0] w_keccak_out;
    wire          w_keccak_done;

    // ----------------------------------------
    // Block 1: Input Register
    // ----------------------------------------
    input_register u_input_register (
        .clk           (clk),
        .rst_n         (rst_n),
        .msg_in        (msg_in),
        .valid_in      (valid_in),
        .is_last       (is_last),
        .byte_count    (byte_count),
        .msg_out       (w_msg),
        .valid_out     (w_valid),
        .last_out      (w_last),
        .byte_count_out(w_byte_count)
    );

    // ----------------------------------------
    // Block 2: Padder
    // ----------------------------------------
    padder u_padder (
        .clk          (clk),
        .rst_n        (rst_n),
        .msg_in       (w_msg),
        .valid_in     (w_valid),
        .is_last      (w_last),
        .byte_count   (w_byte_count),
        .padded_block (w_padded_block),
        .padd_done    (w_padd_done)
    );

    // ----------------------------------------
    // Block 3: State Formation
    // ----------------------------------------
    state_formation u_state_formation (
        .clk          (clk),
        .rst_n        (rst_n),
        .padded_block (w_padded_block),
        .padd_done    (w_padd_done),
        .feedback     (1600'b0),
        .use_feedback (1'b0),
        .state        (w_state),
        .state_valid  (w_state_valid)
    );

    // ----------------------------------------
    // Block 4: Keccak-f (iterative)
    // ----------------------------------------
    keccak_f u_keccak_f (
        .clk      (clk),
        .rst_n    (rst_n),
        .state_in (w_state),
        .start    (w_state_valid),
        .state_out(w_keccak_out),
        .done     (w_keccak_done)
    );

    // ----------------------------------------
    // Output: latch hash when keccak done
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hash_out   <= 256'd0;
            hash_valid <= 1'b0;
        end else begin
            hash_valid <= 1'b0;
            if (w_keccak_done) begin
                hash_valid <= 1'b1;
                // Byte-reverse each 64-bit lane individually
                // Lane[0][0] = w_keccak_out[63:0]
                hash_out[255:192] <= {
                    w_keccak_out[7:0],   w_keccak_out[15:8],
                    w_keccak_out[23:16], w_keccak_out[31:24],
                    w_keccak_out[39:32], w_keccak_out[47:40],
                    w_keccak_out[55:48], w_keccak_out[63:56]
                };
                // Lane[1][0] = w_keccak_out[127:64]
                hash_out[191:128] <= {
                    w_keccak_out[71:64],   w_keccak_out[79:72],
                    w_keccak_out[87:80],   w_keccak_out[95:88],
                    w_keccak_out[103:96],  w_keccak_out[111:104],
                    w_keccak_out[119:112], w_keccak_out[127:120]
                };
                // Lane[2][0] = w_keccak_out[191:128]
                hash_out[127:64] <= {
                    w_keccak_out[135:128], w_keccak_out[143:136],
                    w_keccak_out[151:144], w_keccak_out[159:152],
                    w_keccak_out[167:160], w_keccak_out[175:168],
                    w_keccak_out[183:176], w_keccak_out[191:184]
                };
                // Lane[3][0] = w_keccak_out[255:192]
                hash_out[63:0] <= {
                    w_keccak_out[199:192], w_keccak_out[207:200],
                    w_keccak_out[215:208], w_keccak_out[223:216],
                    w_keccak_out[231:224], w_keccak_out[239:232],
                    w_keccak_out[247:240], w_keccak_out[255:248]
                };
            end
        end
    end

endmodule