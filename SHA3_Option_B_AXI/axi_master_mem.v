`timescale 1ns/1ps
// ============================================================================
// axi_master_mem : MEM-stage adapter that turns a single-cycle CPU memory
// access (lw/sw) into an AXI4-Lite master transaction, stalling the pipeline
// until the transaction completes.
// ----------------------------------------------------------------------------
// The pipeline issues at most one memory access at a time from the MEM stage.
// When the access targets the accelerator (sel_accel), this adapter runs the
// AXI handshake and asserts `busy` (-> pipeline stall) until done. For reads
// it captures RDATA into rdata_out, held stable when not busy.
//
// Because the teaching pipeline has no native "memory busy" stall, we expose
// `busy`; the integrated top ANDs it into pc_write / ifid_write / IF-ID and
// freezes the EX/MEM register so the same access is re-presented until done.
//
// Simplification valid here: only ONE outstanding access, no pipelining of
// AXI transactions. AW and W are issued together (typical AXI4-Lite master).
// ============================================================================

module axi_master_mem #(
    parameter AW = 32,
    parameter DW = 32
)(
    input  wire           clk,
    input  wire           rst,        // active-high

    // CPU side (from MEM stage)
    input  wire           req,        // a memory access is present this cycle
    input  wire           we,         // 1=write (sw), 0=read (lw)
    input  wire [AW-1:0]  addr,
    input  wire [DW-1:0]  wdata,
    output reg  [DW-1:0]  rdata,
    output reg            busy,       // high while the AXI txn is in flight

    // AXI4-Lite master port
    output reg  [AW-1:0]  M_AWADDR,  output reg M_AWVALID, input wire M_AWREADY,
    output reg  [DW-1:0]  M_WDATA,   output reg [DW/8-1:0] M_WSTRB,
    output reg            M_WVALID,  input  wire M_WREADY,
    input  wire [1:0]     M_BRESP,   input  wire M_BVALID, output reg M_BREADY,
    output reg  [AW-1:0]  M_ARADDR,  output reg M_ARVALID, input wire M_ARREADY,
    input  wire [DW-1:0]  M_RDATA,   input wire [1:0] M_RRESP,
    input  wire           M_RVALID,  output reg M_RREADY
);

    localparam S_IDLE=3'd0, S_WADDR=3'd1, S_WRESP=3'd2,
               S_RADDR=3'd3, S_RDATA=3'd4, S_DONE=3'd5;
    reg [2:0] st;

    reg aw_done, w_done;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            st <= S_IDLE; busy <= 1'b0; rdata <= {DW{1'b0}};
            M_AWADDR<=0; M_AWVALID<=0; M_WDATA<=0; M_WSTRB<=0; M_WVALID<=0;
            M_BREADY<=0; M_ARADDR<=0; M_ARVALID<=0; M_RREADY<=0;
            aw_done<=0; w_done<=0;
        end else begin
            case (st)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (req) begin
                        busy <= 1'b1;          // stall pipeline from now
                        if (we) begin
                            M_AWADDR  <= addr; M_AWVALID <= 1'b1;
                            M_WDATA   <= wdata; M_WSTRB <= {(DW/8){1'b1}};
                            M_WVALID  <= 1'b1;
                            M_BREADY  <= 1'b1;
                            aw_done   <= 1'b0; w_done <= 1'b0;
                            st        <= S_WADDR;
                        end else begin
                            M_ARADDR  <= addr; M_ARVALID <= 1'b1;
                            M_RREADY  <= 1'b1;
                            st        <= S_RADDR;
                        end
                    end
                end

                // ---- write: AW + W handshakes ----
                S_WADDR: begin
                    if (M_AWREADY) begin M_AWVALID <= 1'b0; aw_done <= 1'b1; end
                    if (M_WREADY)  begin M_WVALID  <= 1'b0; w_done  <= 1'b1; end
                    if ((aw_done || M_AWREADY) && (w_done || M_WREADY))
                        st <= S_WRESP;
                end
                S_WRESP: begin
                    if (M_BVALID) begin
                        M_BREADY <= 1'b0;
                        st       <= S_DONE;
                    end
                end

                // ---- read: AR then R ----
                S_RADDR: begin
                    if (M_ARREADY) begin
                        M_ARVALID <= 1'b0;
                        st        <= S_RDATA;
                    end
                end
                S_RDATA: begin
                    if (M_RVALID) begin
                        rdata    <= M_RDATA;
                        M_RREADY <= 1'b0;
                        st       <= S_DONE;
                    end
                end

                // ---- one cycle to drop busy, releasing the stall ----
                S_DONE: begin
                    // wait for the CPU to drop req before going idle, so a
                    // single req can never launch two transactions
                    if (!req) begin
                        busy <= 1'b0;
                        st   <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
