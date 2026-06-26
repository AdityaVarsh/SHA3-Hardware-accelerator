`timescale 1ns/1ps
// ============================================================================
// sha3_mmio : Memory-mapped wrapper around the SHA-3 core (Option A)
// ----------------------------------------------------------------------------
// Bridges a simple CPU memory interface (addr / wdata / rd / we / rdata) to
// the sha3_top core, which wants 64-bit words fed one-per-cycle with valid_in.
//
// This is the analogue of the AXI wrapper from Section IV, but stripped of the
// AXI handshake -- it speaks the same plain memory interface your pipeline's
// MEM stage already uses for Data_Mem.
//
// 32-bit register map (offsets relative to the accelerator base address).
// The CPU is 32-bit, but the core wants 64-bit lanes, so each lane is written
// as two 32-bit halves (LO then HI).
//
//   Offset   Name              Access  Meaning
//   ------   ----------------  ------  --------------------------------------
//   0x00     DATA0_LO          W       lane 0, bits [31:0]
//   0x04     DATA0_HI          W       lane 0, bits [63:32]
//   0x08     DATA1_LO          W       lane 1, bits [31:0]
//   0x0C     DATA1_HI          W       lane 1, bits [63:32]
//   ...      ...               ...     (17 lanes => offsets 0x00 .. 0x87)
//   0x88     LANE_COUNT        W       number of valid lanes (1..17)
//   0x8C     LAST_BYTECNT      W       valid bytes in the final lane (1..8)
//   0x90     START             W       write 1 to begin hashing
//   0x94     DONE              R       1 = hash complete (sticky)
//   0xA0     HASH0             R       digest bits [31:0]   (read after DONE)
//   0xA4     HASH1             R       digest bits [63:32]
//   0xA8     HASH2             R       digest bits [95:64]
//   ...                                up to HASH7 at 0xBC (digest[255:224])
//
// NOTE: single-block messages only (<= 1088 bits / 17 lanes), matching the
// current sha3_top which hardwires use_feedback=0. That covers short strings
// like "abc". Multi-block support would require wiring the feedback path.
// ============================================================================

module sha3_mmio (
    input  wire        clk,
    input  wire        rst,        // active-high reset (matches your pipeline)

    // Simple CPU-side memory interface (same shape as Data_Mem)
    input  wire [31:0] addr,       // byte offset within the accelerator window
    input  wire [31:0] wdata,
    input  wire        we,         // write enable (this access targets accel)
    input  wire        rd,         // read enable
    output reg  [31:0] rdata
);

    // ----------------------------------------------------------------
    // active-low reset for the SHA-3 core (it uses rst_n)
    // ----------------------------------------------------------------
    wire rst_n = ~rst;

    // ----------------------------------------------------------------
    // Register file
    // 17 lanes x 64 bits, stored as 34 x 32-bit halves
    // ----------------------------------------------------------------
    reg [63:0] lane [0:16];
    reg [4:0]  lane_count;       // how many lanes the message uses (1..17)
    reg [3:0]  last_bytecnt;     // valid bytes in the final lane (1..8)
    reg        start_pulse;      // 1-cycle trigger into the FSM

    reg [255:0] hash_latched;    // captured digest
    reg         done_sticky;     // stays high until START clears it

    integer k;

    // ----------------------------------------------------------------
    // Address decode (lower 8 bits choose the register)
    // ----------------------------------------------------------------
    wire [7:0] off = addr[7:0];

    // ----------------------------------------------------------------
    // FSM state
    // ----------------------------------------------------------------
    localparam S_IDLE    = 2'd0;
    localparam S_FEED    = 2'd1;
    localparam S_HASH    = 2'd2;
    localparam S_DONE    = 2'd3;

    reg [1:0]  state;
    reg [4:0]  feed_idx;         // which lane we are feeding (0..lane_count-1)

    // ----------------------------------------------------------------
    // Signals driven INTO the SHA-3 core
    // ----------------------------------------------------------------
    reg  [63:0] core_msg;
    reg         core_valid;
    reg         core_last;
    reg  [3:0]  core_bytecnt;

    wire [255:0] core_hash;
    wire         core_hash_valid;

    sha3_top u_sha3 (
        .clk        (clk),
        .rst_n      (rst_n),
        .msg_in     (core_msg),
        .valid_in   (core_valid),
        .is_last    (core_last),
        .byte_count (core_bytecnt),
        .hash_out   (core_hash),
        .hash_valid (core_hash_valid)
    );

    // ----------------------------------------------------------------
    // WRITE path + FSM (sequential)
    // ----------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (k = 0; k < 17; k = k + 1) lane[k] <= 64'd0;
            lane_count   <= 5'd1;
            last_bytecnt <= 4'd8;
            start_pulse  <= 1'b0;
            done_sticky  <= 1'b0;
            hash_latched <= 256'd0;
            state        <= S_IDLE;
            feed_idx     <= 5'd0;
            core_msg     <= 64'd0;
            core_valid   <= 1'b0;
            core_last    <= 1'b0;
            core_bytecnt <= 4'd8;
        end else begin
            // defaults each cycle
            start_pulse <= 1'b0;
            core_valid  <= 1'b0;
            core_last   <= 1'b0;

            // ---------- CPU writes ----------
            if (we) begin
                case (off)
                    8'h88: lane_count   <= wdata[4:0];
                    8'h8C: last_bytecnt <= wdata[3:0];
                    8'h90: begin
                        if (wdata[0]) start_pulse <= 1'b1; // trigger
                    end
                    default: begin
                        // data lane halves: offsets 0x00..0x87
                        // even 8-byte stride: lane = off[7:3], half = off[2]
                        if (off <= 8'h87) begin
                            if (off[2] == 1'b0)
                                lane[off[7:3]][31:0]  <= wdata; // LO half
                            else
                                lane[off[7:3]][63:32] <= wdata; // HI half
                        end
                    end
                endcase
            end

            // ---------- FSM ----------
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        done_sticky <= 1'b0;   // clear previous result
                        feed_idx    <= 5'd0;
                        state       <= S_FEED;
                    end
                end

                S_FEED: begin
                    // present one lane per cycle to the core
                    core_msg   <= lane[feed_idx];
                    core_valid <= 1'b1;
                    if (feed_idx == (lane_count - 5'd1)) begin
                        core_last    <= 1'b1;
                        core_bytecnt <= last_bytecnt;
                        state        <= S_HASH;
                    end else begin
                        core_last    <= 1'b0;
                        core_bytecnt <= 4'd8;
                        feed_idx     <= feed_idx + 5'd1;
                    end
                end

                S_HASH: begin
                    // wait for the core to finish its 24 rounds
                    if (core_hash_valid) begin
                        hash_latched <= core_hash;
                        done_sticky  <= 1'b1;
                        state        <= S_DONE;
                    end
                end

                S_DONE: begin
                    // stay done until a new START arrives
                    if (start_pulse) begin
                        done_sticky <= 1'b0;
                        feed_idx    <= 5'd0;
                        state       <= S_FEED;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------------------
    // READ path (combinational, matches Data_Mem read style)
    // ----------------------------------------------------------------
    always @(*) begin
        rdata = 32'd0;
        if (rd) begin
            case (off)
                8'h94: rdata = {31'd0, done_sticky};
                8'hA0: rdata = hash_latched[31:0];
                8'hA4: rdata = hash_latched[63:32];
                8'hA8: rdata = hash_latched[95:64];
                8'hAC: rdata = hash_latched[127:96];
                8'hB0: rdata = hash_latched[159:128];
                8'hB4: rdata = hash_latched[191:160];
                8'hB8: rdata = hash_latched[223:192];
                8'hBC: rdata = hash_latched[255:224];
                default: rdata = 32'd0;
            endcase
        end
    end

endmodule
