`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 19.03.2026 17:37:35
// Design Name:
// Module Name: keccak_round
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
// keccak_round: One complete Keccak-f round
// SHA-3 Hardware Accelerator (SHA3-256)
// ============================================
// Instantiates all 5 step mapping functions:
//   θ → ρ → π → χ → ι
//
// Input : 1600-bit state + 5-bit round number
// Output: 1600-bit state after one full round
// ============================================

// ============================================
// keccak_round: One complete Keccak-f round
// SHA-3 Hardware Accelerator (SHA3-256)
// ============================================
// Instantiates all 5 step mapping functions:
//   θ → ρ → π → χ → ι
//
// Purely combinational - no clock needed.
// Input : 1600-bit state + 5-bit round number
// Output: 1600-bit state after one full round
//
// Files needed:
//   theta.v, rho.v, pi.v, chi.v, iota.v
// ============================================

module keccak_round (
    input  wire [1599:0] state_in,
    input  wire [4:0]    round,
    output wire [1599:0] state_out
);

    // ----------------------------------------
    // Internal wires between steps
    // ----------------------------------------
    wire [1599:0] w_theta; // theta → rho
    wire [1599:0] w_rho;   // rho   → pi
    wire [1599:0] w_pi;    // pi    → chi
    wire [1599:0] w_chi;   // chi   → iota

    // ----------------------------------------
    // Step 1: θ (Theta)
    // ----------------------------------------
    theta u_theta (
        .state_in (state_in),
        .state_out(w_theta)
    );

    // ----------------------------------------
    // Step 2: ρ (Rho)
    // ----------------------------------------
    rho u_rho (
        .state_in (w_theta),
        .state_out(w_rho)
    );

    // ----------------------------------------
    // Step 3: π (Pi)
    // ----------------------------------------
    pi u_pi (
        .state_in (w_rho),
        .state_out(w_pi)
    );

    // ----------------------------------------
    // Step 4: χ (Chi)
    // ----------------------------------------
    chi u_chi (
        .state_in (w_pi),
        .state_out(w_chi)
    );

    // ----------------------------------------
    // Step 5: ι (Iota)
    // ----------------------------------------
    iota u_iota (
        .state_in (w_chi),
        .round    (round),
        .state_out(state_out)
    );

endmodule