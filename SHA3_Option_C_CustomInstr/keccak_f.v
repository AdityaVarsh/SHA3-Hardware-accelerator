`timescale 1ns/1ps
// ============================================
// keccak_f: 24-round Keccak-f permutation
// Iterative implementation - 1 round/cycle
// Takes 24 clock cycles to complete
// ============================================
module keccak_f (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1599:0] state_in,
    input  wire          start,
    output reg  [1599:0] state_out,
    output reg           done
);
    reg [1599:0] state_reg;
    reg [4:0]    round_cnt;
    reg          running;

    wire [1599:0] round_out;

    keccak_round u_round (
        .state_in  (state_reg),
        .round     (round_cnt),
        .state_out (round_out)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running   <= 1'b0;
            done      <= 1'b0;
            round_cnt <= 5'd0;
            state_reg <= 1600'd0;
            state_out <= 1600'd0;
        end else begin
            done <= 1'b0;
            if (start && !running) begin
                state_reg <= state_in;
                round_cnt <= 5'd0;
                running   <= 1'b1;
            end else if (running) begin
                state_reg <= round_out;
                if (round_cnt == 5'd23) begin
                    running   <= 1'b0;
                    done      <= 1'b1;
                    state_out <= round_out;
                end else begin
                    round_cnt <= round_cnt + 5'd1;
                end
            end
        end
    end
endmodule


