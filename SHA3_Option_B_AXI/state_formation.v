`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 00:16:59
// Design Name:
// Module Name: state_formation
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
// Block 3: STATE FORMATION
// SHA-3 Hardware Accelerator (SHA3-256)
// ============================================
// Receives 1088-bit padded block from Block 2.
// XORs with selected base state.
// Outputs full 1600-bit state to Round Unit.
//
// First block  (use_feedback=0):
//   state = padded_block XOR 0
//         = padded_block (lower 1088 bits)
//           upper 512 bits = 0
//
// Subsequent   (use_feedback=1):
//   state = padded_block XOR feedback
//
// xor_base is combinational wire - avoids
// NBA stale-value timing issue.
//
// SHA3-256:
//   rate     = 1088 bits
//   capacity =  512 bits
//   state    = 1600 bits
// ============================================

module state_formation (
    input  wire          clk,
    input  wire          rst_n,

    // From Block 2: Padder
    input  wire [1087:0] padded_block,  // 1088-bit padded block
    input  wire          padd_done,     // HIGH one cycle: block ready

    // From Block 4: Round Unit (feedback path)
    input  wire [1599:0] feedback,      // 1600-bit post-round state
    input  wire          use_feedback,  // 0=first block 1=subsequent

    // To Block 4: Round Unit
    output reg  [1599:0] state,         // Full 1600-bit state
    output reg           state_valid    // HIGH one cycle: state ready
);

    // ----------------------------------------
    // Combinational mux: select XOR base
    // use_feedback=0 → zero  (first block)
    // use_feedback=1 → feedback (subsequent)
    // Declared as wire to avoid NBA stale-value
    // issue when reading inside always block
    // ----------------------------------------
    wire [1599:0] xor_base;
    assign xor_base = use_feedback ? feedback : 1600'b0;

    // ----------------------------------------
    // Sequential Logic
    // ----------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= 1600'b0;
            state_valid <= 1'b0;
        end
        else begin
            state_valid <= 1'b0; // default: not valid

            if (padd_done) begin
                // XOR padded block with base state
                // lower 1088 bits (rate)
                state[1087:0]    <= padded_block[1087:0]
                                    ^ xor_base[1087:0];

                // Upper 512 bits (capacity)
                // pass through from base state
                state[1599:1088] <= xor_base[1599:1088];

                // Signal state is ready
                state_valid      <= 1'b1;
            end
        end
    end

endmodule
