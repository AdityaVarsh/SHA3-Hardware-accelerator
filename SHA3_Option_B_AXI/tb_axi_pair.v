`timescale 1ns/1ps
// ============================================================================
// tb_axi_pair : connects axi_master_mem  <-->  axi_sha3 over a real AXI4-Lite
// link, and drives the master's CPU-side port the way a stalled MEM stage
// would (assert req/we/addr/wdata, wait while busy). Verifies SHA3-256("abc").
// This proves the full Option B datapath: CPU access -> AXI master -> AXI bus
// -> AXI slave -> SHA-3 core -> back.
// ============================================================================
module tb_axi_pair;
    localparam AW=32, DW=32;
    reg clk, rst;

    // CPU-side of the master
    reg            req, we;
    reg  [AW-1:0]  addr;
    reg  [DW-1:0]  wdata;
    wire [DW-1:0]  rdata;
    wire           busy;

    // AXI link
    wire [AW-1:0] AWADDR; wire AWVALID, AWREADY;
    wire [DW-1:0] WDATA;  wire [DW/8-1:0] WSTRB; wire WVALID, WREADY;
    wire [1:0]    BRESP;  wire BVALID, BREADY;
    wire [AW-1:0] ARADDR; wire ARVALID, ARREADY;
    wire [DW-1:0] RDATA;  wire [1:0] RRESP; wire RVALID, RREADY;

    axi_master_mem #(.AW(AW),.DW(DW)) M (
        .clk(clk), .rst(rst),
        .req(req), .we(we), .addr(addr), .wdata(wdata),
        .rdata(rdata), .busy(busy),
        .M_AWADDR(AWADDR), .M_AWVALID(AWVALID), .M_AWREADY(AWREADY),
        .M_WDATA(WDATA), .M_WSTRB(WSTRB), .M_WVALID(WVALID), .M_WREADY(WREADY),
        .M_BRESP(BRESP), .M_BVALID(BVALID), .M_BREADY(BREADY),
        .M_ARADDR(ARADDR), .M_ARVALID(ARVALID), .M_ARREADY(ARREADY),
        .M_RDATA(RDATA), .M_RRESP(RRESP), .M_RVALID(RVALID), .M_RREADY(RREADY)
    );

    axi_sha3 #(.ADDR_W(AW),.DATA_W(DW)) S (
        .ACLK(clk), .ARESETN(~rst),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

    initial clk=0; always #5 clk=~clk;

    // emulate a stalled MEM stage: present an access, wait until not busy
    task cpu_write;
        input [AW-1:0] a; input [DW-1:0] d;
        begin
            @(posedge clk);
            addr<=a; wdata<=d; we<=1'b1; req<=1'b1;
            wait (busy);               // master accepted the request
            @(posedge clk);
            req<=1'b0;                 // drop request
            wait (!busy);              // hold (stall) until txn done
            @(posedge clk);
        end
    endtask

    task cpu_read;
        input  [AW-1:0] a; output [DW-1:0] d;
        begin
            @(posedge clk);
            addr<=a; we<=1'b0; req<=1'b1;
            wait (busy);
            @(posedge clk);
            req<=1'b0;
            wait (!busy);
            d = rdata;
            @(posedge clk);
        end
    endtask

    integer poll; reg [DW-1:0] dv; reg [255:0] got;
    localparam [255:0] EXP =
        256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532;

    initial begin
        req=0; we=0; addr=0; wdata=0; rst=1;
        repeat(4) @(posedge clk); rst=0; @(posedge clk);

        cpu_write(32'h00, 32'h00000000);
        cpu_write(32'h04, 32'h61626300);
        cpu_write(32'h88, 32'd1);
        cpu_write(32'h8C, 32'd3);
        cpu_write(32'h90, 32'd1);

        dv=0; poll=0;
        while (dv[0]!==1'b1 && poll<200) begin cpu_read(32'h94,dv); poll=poll+1; end
        if (dv[0]!==1'b1) begin $display("TIMEOUT"); $finish; end
        $display("Hash done after %0d CPU->AXI read polls", poll);

        cpu_read(32'hA0,dv); got[31:0]=dv;
        cpu_read(32'hA4,dv); got[63:32]=dv;
        cpu_read(32'hA8,dv); got[95:64]=dv;
        cpu_read(32'hAC,dv); got[127:96]=dv;
        cpu_read(32'hB0,dv); got[159:128]=dv;
        cpu_read(32'hB4,dv); got[191:160]=dv;
        cpu_read(32'hB8,dv); got[223:192]=dv;
        cpu_read(32'hBC,dv); got[255:224]=dv;

        $display("=== Option B full path: CPU -> AXI master -> AXI slave -> SHA-3 ===");
        $display("Got:      %064h", got);
        $display("Expected: %064h", EXP);
        if (got===EXP) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin #300000; $display("GLOBAL TIMEOUT"); $finish; end
endmodule
