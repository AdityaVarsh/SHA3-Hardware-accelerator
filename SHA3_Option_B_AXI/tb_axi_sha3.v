`timescale 1ns/1ps
// ============================================================================
// tb_axi_sha3 : AXI4-Lite master Bus Functional Model (BFM).
// Drives the real five-channel protocol against axi_sha3 and verifies
// SHA3-256("abc"). This is the same verification approach the paper used.
// ============================================================================
module tb_axi_sha3;

    localparam AW = 32, DW = 32;

    reg              ACLK, ARESETN;

    // write address
    reg  [AW-1:0]    AWADDR;  reg AWVALID;  wire AWREADY;
    // write data
    reg  [DW-1:0]    WDATA;   reg [DW/8-1:0] WSTRB; reg WVALID; wire WREADY;
    // write resp
    wire [1:0]       BRESP;   wire BVALID;  reg BREADY;
    // read address
    reg  [AW-1:0]    ARADDR;  reg ARVALID;  wire ARREADY;
    // read data
    wire [DW-1:0]    RDATA;   wire [1:0] RRESP; wire RVALID; reg RREADY;

    axi_sha3 #(.ADDR_W(AW), .DATA_W(DW)) DUT (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WSTRB(WSTRB), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

    initial ACLK = 0;
    always #5 ACLK = ~ACLK;

    // -------------------------------------------------------------
    // AXI4-Lite single write: drive AW + W, wait for B
    // -------------------------------------------------------------
    task axi_write;
        input [AW-1:0] addr;
        input [DW-1:0] data;
        begin
            @(posedge ACLK);
            AWADDR <= addr; AWVALID <= 1'b1;
            WDATA  <= data; WSTRB <= 4'hF; WVALID <= 1'b1;
            BREADY <= 1'b1;

            // drop AWVALID once AWREADY seen
            fork
                begin
                    wait (AWREADY); @(posedge ACLK); AWVALID <= 1'b0;
                end
                begin
                    wait (WREADY);  @(posedge ACLK); WVALID  <= 1'b0;
                end
            join

            // wait for write response
            wait (BVALID); @(posedge ACLK);
            BREADY <= 1'b0;
        end
    endtask

    // -------------------------------------------------------------
    // AXI4-Lite single read: drive AR, capture R
    // -------------------------------------------------------------
    task axi_read;
        input  [AW-1:0] addr;
        output [DW-1:0] data;
        begin
            @(posedge ACLK);
            ARADDR <= addr; ARVALID <= 1'b1; RREADY <= 1'b1;
            wait (ARREADY); @(posedge ACLK); ARVALID <= 1'b0;
            wait (RVALID);
            data = RDATA;
            @(posedge ACLK);
            RREADY <= 1'b0;
        end
    endtask

    integer poll;
    reg [DW-1:0] dval;
    reg [255:0]  got;

    localparam [255:0] EXP =
        256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532;

    initial begin
        // init
        AWADDR=0; AWVALID=0; WDATA=0; WSTRB=0; WVALID=0; BREADY=0;
        ARADDR=0; ARVALID=0; RREADY=0;
        ARESETN=0;
        repeat (4) @(posedge ACLK);
        ARESETN=1;
        @(posedge ACLK);

        // load "abc": lane0 lo=0x00000000, hi=0x61626300
        axi_write(32'h00, 32'h00000000);
        axi_write(32'h04, 32'h61626300);
        axi_write(32'h88, 32'd1);     // LANE_COUNT
        axi_write(32'h8C, 32'd3);     // LAST_BYTECNT
        axi_write(32'h90, 32'd1);     // START

        // poll DONE
        dval = 0; poll = 0;
        while (dval[0] !== 1'b1 && poll < 200) begin
            axi_read(32'h94, dval);
            poll = poll + 1;
        end
        if (dval[0] !== 1'b1) begin
            $display("TIMEOUT"); $finish;
        end
        $display("Hash done after %0d AXI read polls", poll);

        axi_read(32'hA0, dval); got[31:0]    = dval;
        axi_read(32'hA4, dval); got[63:32]   = dval;
        axi_read(32'hA8, dval); got[95:64]   = dval;
        axi_read(32'hAC, dval); got[127:96]  = dval;
        axi_read(32'hB0, dval); got[159:128] = dval;
        axi_read(32'hB4, dval); got[191:160] = dval;
        axi_read(32'hB8, dval); got[223:192] = dval;
        axi_read(32'hBC, dval); got[255:224] = dval;

        $display("=== SHA3-256(\"abc\") via AXI4-Lite ===");
        $display("Got:      %064h", got);
        $display("Expected: %064h", EXP);
        if (got === EXP) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // safety timeout
    initial begin
        #200000;
        $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule
