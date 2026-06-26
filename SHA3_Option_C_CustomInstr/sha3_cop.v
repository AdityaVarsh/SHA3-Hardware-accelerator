`timescale 1ns/1ps
// ============================================================================
// sha3_cop : SHA-3 coprocessor attached to the EX stage (Option C)
// ----------------------------------------------------------------------------
// No memory map. The CPU talks to this block through CUSTOM-0 instructions
// whose operands come straight from the register file (forwarded rs1/rs2) and
// whose results go straight back on the ALU writeback path.
//
// Custom-0 opcode = 7'b0001011, sub-operation selected by funct3:
//
//   funct3  mnemonic    operands                     effect
//   ------  ----------  --------------------------    -------------------------
//   000     SHA.FEED    rs1=lane_lo, rs2=lane_hi      append a 64-bit lane
//   001     SHA.CFG     rs1=lane_count, rs2=bytecnt   set message parameters
//   010     SHA.START   (none)                        begin hashing
//   011     SHA.POLL    rd <- {31'b0, done}           read completion flag
//   100     SHA.READ    rd <- hash word[rs2[2:0]]     read one digest word
//
// FEED/CFG/START are "write" ops (regwrite=0). POLL/READ are "read" ops
// (regwrite=1) and drive cop_result, which the datapath muxes onto the ALU
// result for that instruction.
//
// The hash runs in the background after START; software polls with SHA.POLL
// in a loop, so no pipeline stall is needed (same latency-hiding idea as the
// memory-mapped versions, but via opcodes instead of loads/stores).
//
// Single-block messages only (sha3_top hardwires use_feedback=0).
// ============================================================================

module sha3_cop (
    input  wire        clk,
    input  wire        rst,          // active-high

    // EX-stage control (decoded upstream, valid for one cycle when the
    // custom instruction is in EX)
    input  wire        cop_en,       // a CUSTOM-0 instruction is in EX
    input  wire [2:0]  cop_func,     // funct3 sub-op
    input  wire [31:0] rs1_val,      // forwarded rs1
    input  wire [31:0] rs2_val,      // forwarded rs2

    // result for POLL/READ (combinational, same cycle)
    output reg  [31:0] cop_result
);

    // sub-op encodings
    localparam F_FEED=3'b000, F_CFG=3'b001, F_START=3'b010,
               F_POLL=3'b011, F_READ=3'b100;

    // ----------------------------------------------------------------
    // message storage + control
    // ----------------------------------------------------------------
    reg [63:0]  lane [0:16];
    reg [4:0]   lane_count;
    reg [3:0]   last_bytecnt;
    reg [4:0]   feed_ptr;        // next lane index to fill on FEED
    reg         start_pulse;

    reg [255:0] hash_latched;
    reg         done_sticky;
    integer     k;

    // core hookup
    reg  [63:0]  core_msg;
    reg          core_valid;
    reg          core_last;
    reg  [3:0]   core_bytecnt;
    wire [255:0] core_hash;
    wire         core_hash_valid;

    sha3_top u_sha3 (
        .clk(clk), .rst_n(~rst),
        .msg_in(core_msg), .valid_in(core_valid),
        .is_last(core_last), .byte_count(core_bytecnt),
        .hash_out(core_hash), .hash_valid(core_hash_valid)
    );

    localparam S_IDLE=2'd0, S_FEED=2'd1, S_HASH=2'd2, S_DONE=2'd3;
    reg [1:0] state;
    reg [4:0] fidx;

    // ----------------------------------------------------------------
    // writes from custom instructions + background FSM
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k=0;k<17;k=k+1) lane[k] <= 64'd0;
            lane_count<=5'd1; last_bytecnt<=4'd8; feed_ptr<=5'd0;
            start_pulse<=1'b0; done_sticky<=1'b0; hash_latched<=256'd0;
            state<=S_IDLE; fidx<=5'd0;
            core_msg<=64'd0; core_valid<=1'b0; core_last<=1'b0; core_bytecnt<=4'd8;
        end else begin
            start_pulse <= 1'b0;
            core_valid  <= 1'b0;
            core_last   <= 1'b0;

            if (cop_en) begin
                case (cop_func)
                    F_FEED: begin
                        if (feed_ptr <= 5'd16) begin
                            lane[feed_ptr] <= {rs2_val, rs1_val}; // hi:lo
                            feed_ptr       <= feed_ptr + 5'd1;
                        end
                    end
                    F_CFG: begin
                        lane_count   <= rs1_val[4:0];
                        last_bytecnt <= rs2_val[3:0];
                    end
                    F_START: begin
                        start_pulse <= 1'b1;
                        feed_ptr    <= 5'd0;   // ready for a future message
                    end
                    default: ; // POLL/READ are pure reads
                endcase
            end

            // background hashing FSM
            case (state)
                S_IDLE: if (start_pulse) begin
                            done_sticky<=1'b0; fidx<=5'd0; state<=S_FEED;
                        end
                S_FEED: begin
                    core_msg   <= lane[fidx];
                    core_valid <= 1'b1;
                    if (fidx == (lane_count-5'd1)) begin
                        core_last    <= 1'b1;
                        core_bytecnt <= last_bytecnt;
                        state        <= S_HASH;
                    end else begin
                        core_last    <= 1'b0;
                        core_bytecnt <= 4'd8;
                        fidx         <= fidx + 5'd1;
                    end
                end
                S_HASH: if (core_hash_valid) begin
                            hash_latched<=core_hash; done_sticky<=1'b1; state<=S_DONE;
                        end
                S_DONE: if (start_pulse) begin
                            done_sticky<=1'b0; fidx<=5'd0; state<=S_FEED;
                        end
                default: state<=S_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // combinational read result (POLL / READ)
    // ----------------------------------------------------------------
    always @(*) begin
        cop_result = 32'd0;
        case (cop_func)
            F_POLL: cop_result = {31'd0, done_sticky};
            F_READ: begin
                case (rs2_val[2:0])
                    3'd0: cop_result = hash_latched[31:0];
                    3'd1: cop_result = hash_latched[63:32];
                    3'd2: cop_result = hash_latched[95:64];
                    3'd3: cop_result = hash_latched[127:96];
                    3'd4: cop_result = hash_latched[159:128];
                    3'd5: cop_result = hash_latched[191:160];
                    3'd6: cop_result = hash_latched[223:192];
                    3'd7: cop_result = hash_latched[255:224];
                endcase
            end
            default: cop_result = 32'd0;
        endcase
    end

endmodule
