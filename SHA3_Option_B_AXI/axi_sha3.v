`timescale 1ns/1ps
// ============================================================================
// axi_sha3 : AXI4-Lite slave wrapper around sha3_top  (Option B)
// ----------------------------------------------------------------------------
// This is the faithful Section IV artifact: a real five-channel AXI4-Lite
// slave. A processor (AXI master) reads/writes the register map below as if
// it were memory; internally an FSM replays the stored words into the SHA-3
// core one-per-cycle and latches the digest.
//
// Bus width: 32-bit data, 32-bit address (AXI4-Lite, no bursts).
// Each 64-bit Keccak lane is two 32-bit registers (LO then HI), since the
// bus is 32-bit -- identical map to the Option A wrapper.
//
//   Offset   Name           Access  Meaning
//   0x00     DATA0_LO       W       lane 0 [31:0]
//   0x04     DATA0_HI       W       lane 0 [63:32]
//   ...                             lanes 0..16 (0x00..0x87)
//   0x88     LANE_COUNT     W       valid lanes (1..17)
//   0x8C     LAST_BYTECNT   W       valid bytes in final lane (1..8)
//   0x90     START          W       write 1 to begin
//   0x94     DONE           R       1 = complete (sticky)
//   0xA0..0xBC  HASH0..7    R       256-bit digest, low word first
//
// Single-block messages only (matches sha3_top with use_feedback=0).
// ============================================================================

module axi_sha3 #(
    parameter ADDR_W = 32,
    parameter DATA_W = 32
)(
    input  wire                  ACLK,
    input  wire                  ARESETN,   // active-low, AXI convention

    // ---- Write address channel ----
    input  wire [ADDR_W-1:0]     AWADDR,
    input  wire                  AWVALID,
    output reg                   AWREADY,

    // ---- Write data channel ----
    input  wire [DATA_W-1:0]     WDATA,
    input  wire [DATA_W/8-1:0]   WSTRB,
    input  wire                  WVALID,
    output reg                   WREADY,

    // ---- Write response channel ----
    output reg  [1:0]            BRESP,
    output reg                   BVALID,
    input  wire                  BREADY,

    // ---- Read address channel ----
    input  wire [ADDR_W-1:0]     ARADDR,
    input  wire                  ARVALID,
    output reg                   ARREADY,

    // ---- Read data channel ----
    output reg  [DATA_W-1:0]     RDATA,
    output reg  [1:0]            RRESP,
    output reg                   RVALID,
    input  wire                  RREADY
);

    localparam [1:0] OKAY = 2'b00;

    wire rst_n = ARESETN;

    // ----------------------------------------------------------------
    // Register file + control state, same as Option A
    // ----------------------------------------------------------------
    reg [63:0]  lane [0:16];
    reg [4:0]   lane_count;
    reg [3:0]   last_bytecnt;
    reg         start_pulse;
    reg [255:0] hash_latched;
    reg         done_sticky;
    integer     k;

    // SHA-3 core hookup
    reg  [63:0]  core_msg;
    reg          core_valid;
    reg          core_last;
    reg  [3:0]   core_bytecnt;
    wire [255:0] core_hash;
    wire         core_hash_valid;

    sha3_top u_sha3 (
        .clk        (ACLK),
        .rst_n      (rst_n),
        .msg_in     (core_msg),
        .valid_in   (core_valid),
        .is_last    (core_last),
        .byte_count (core_bytecnt),
        .hash_out   (core_hash),
        .hash_valid (core_hash_valid)
    );

    localparam S_IDLE=2'd0, S_FEED=2'd1, S_HASH=2'd2, S_DONE=2'd3;
    reg [1:0] state;
    reg [4:0] feed_idx;

    // ================================================================
    // WRITE channel logic
    // ----------------------------------------------------------------
    // Accept address and data independently; perform the register
    // update when BOTH have been captured. Then issue B response.
    // ================================================================
    reg                  aw_seen, w_seen;
    reg [ADDR_W-1:0]     aw_addr_q;
    reg [DATA_W-1:0]     w_data_q;

    wire        do_write = aw_seen && w_seen;
    wire [7:0]  w_off    = aw_addr_q[7:0];

    // ================================================================
    // Main sequential block: AXI write handshakes, register file, FSM
    // ================================================================
    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            AWREADY <= 1'b0; WREADY <= 1'b0;
            BVALID  <= 1'b0; BRESP  <= OKAY;
            aw_seen <= 1'b0; w_seen <= 1'b0;
            aw_addr_q <= {ADDR_W{1'b0}};
            w_data_q  <= {DATA_W{1'b0}};

            for (k=0;k<17;k=k+1) lane[k] <= 64'd0;
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
            // ---- defaults ----
            start_pulse <= 1'b0;
            core_valid  <= 1'b0;
            core_last   <= 1'b0;

            // ---------- Write address handshake ----------
            // assert AWREADY for one cycle when an address arrives and we
            // haven't latched one yet
            if (AWVALID && !aw_seen && !AWREADY) begin
                AWREADY   <= 1'b1;
                aw_addr_q <= AWADDR;
                aw_seen   <= 1'b1;
            end else begin
                AWREADY <= 1'b0;
            end

            // ---------- Write data handshake ----------
            if (WVALID && !w_seen && !WREADY) begin
                WREADY   <= 1'b1;
                w_data_q <= WDATA;
                w_seen   <= 1'b1;
            end else begin
                WREADY <= 1'b0;
            end

            // ---------- Perform the write + B response ----------
            if (do_write && !BVALID) begin
                // commit the register update
                case (w_off)
                    8'h88: lane_count   <= w_data_q[4:0];
                    8'h8C: last_bytecnt <= w_data_q[3:0];
                    8'h90: if (w_data_q[0]) start_pulse <= 1'b1;
                    default: begin
                        if (w_off <= 8'h87) begin
                            if (w_off[2] == 1'b0)
                                lane[w_off[7:3]][31:0]  <= w_data_q;
                            else
                                lane[w_off[7:3]][63:32] <= w_data_q;
                        end
                    end
                endcase
                // raise response, clear the seen flags
                BVALID  <= 1'b1;
                BRESP   <= OKAY;
                aw_seen <= 1'b0;
                w_seen  <= 1'b0;
            end else if (BVALID && BREADY) begin
                BVALID <= 1'b0;   // response accepted by master
            end

            // ================= SHA-3 driving FSM =================
            case (state)
                S_IDLE: begin
                    if (start_pulse) begin
                        done_sticky <= 1'b0;
                        feed_idx    <= 5'd0;
                        state       <= S_FEED;
                    end
                end
                S_FEED: begin
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
                    if (core_hash_valid) begin
                        hash_latched <= core_hash;
                        done_sticky  <= 1'b1;
                        state        <= S_DONE;
                    end
                end
                S_DONE: begin
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

    // ================================================================
    // READ channel logic
    // ----------------------------------------------------------------
    // Accept a read address, then drive RDATA + RVALID until accepted.
    // ================================================================
    reg [7:0] ar_off;

    always @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            ARREADY <= 1'b0;
            RVALID  <= 1'b0;
            RRESP   <= OKAY;
            RDATA   <= {DATA_W{1'b0}};
            ar_off  <= 8'd0;
        end else begin
            // address handshake
            if (ARVALID && !ARREADY && !RVALID) begin
                ARREADY <= 1'b1;
                ar_off  <= ARADDR[7:0];
            end else begin
                ARREADY <= 1'b0;
            end

            // produce data one cycle after accepting the address
            if (ARREADY) begin
                RVALID <= 1'b1;
                RRESP  <= OKAY;
                case (ar_off)
                    8'h94: RDATA <= {31'd0, done_sticky};
                    8'hA0: RDATA <= hash_latched[31:0];
                    8'hA4: RDATA <= hash_latched[63:32];
                    8'hA8: RDATA <= hash_latched[95:64];
                    8'hAC: RDATA <= hash_latched[127:96];
                    8'hB0: RDATA <= hash_latched[159:128];
                    8'hB4: RDATA <= hash_latched[191:160];
                    8'hB8: RDATA <= hash_latched[223:192];
                    8'hBC: RDATA <= hash_latched[255:224];
                    default: RDATA <= 32'd0;
                endcase
            end else if (RVALID && RREADY) begin
                RVALID <= 1'b0;   // data accepted by master
            end
        end
    end

endmodule
