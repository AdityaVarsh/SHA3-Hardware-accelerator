`timescale 1ns/1ps
// ============================================================================
// tb_sha3_mmio : drives the memory-mapped wrapper exactly as a CPU would,
// using plain addr/wdata/we/rd transactions. Verifies SHA3-256("abc").
// ============================================================================
module tb_sha3_mmio;

    reg         clk, rst;
    reg  [31:0] addr, wdata;
    reg         we, rd;
    wire [31:0] rdata;

    sha3_mmio DUT (
        .clk(clk), .rst(rst),
        .addr(addr), .wdata(wdata), .we(we), .rd(rd), .rdata(rdata)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ---- one write transaction ----
    task wr;
        input [31:0] a;
        input [31:0] d;
        begin
            @(negedge clk);
            addr = a; wdata = d; we = 1; rd = 0;
            @(negedge clk);
            we = 0; addr = 0; wdata = 0;
        end
    endtask

    // ---- one read transaction (returns in rdata after the access) ----
    task rdreg;
        input  [31:0] a;
        output [31:0] dout;
        begin
            @(negedge clk);
            addr = a; rd = 1; we = 0;
            #1 dout = rdata;     // combinational read
            @(negedge clk);
            rd = 0; addr = 0;
        end
    endtask

    integer poll;
    reg [31:0] dval;
    reg [255:0] got;

    // Expected SHA3-256("abc")
    localparam [255:0] EXP =
        256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532;

    initial begin
        // reset
        rst = 1; addr = 0; wdata = 0; we = 0; rd = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        @(negedge clk);

        // ---- Load "abc": single lane, 3 valid bytes ----
        // build_lane in the core expects MSB-packed big-endian word:
        //   'a'=0x61,'b'=0x62,'c'=0x63  ->  0x6162630000000000
        // low half  = 0x00000000
        // high half = 0x61626300
        wr(32'h00, 32'h00000000);   // DATA0_LO
        wr(32'h04, 32'h61626300);   // DATA0_HI

        wr(32'h88, 32'd1);          // LANE_COUNT = 1
        wr(32'h8C, 32'd3);          // LAST_BYTECNT = 3
        wr(32'h90, 32'd1);          // START

        // ---- Poll DONE ----
        dval = 0; poll = 0;
        while (dval[0] !== 1'b1 && poll < 200) begin
            rdreg(32'h94, dval);
            poll = poll + 1;
        end

        if (dval[0] !== 1'b1) begin
            $display("TIMEOUT: hash never completed");
            $finish;
        end
        $display("Hash completed after %0d polls", poll);

        // ---- Read digest (8 words) ----
        rdreg(32'hA0, dval); got[31:0]    = dval;
        rdreg(32'hA4, dval); got[63:32]   = dval;
        rdreg(32'hA8, dval); got[95:64]   = dval;
        rdreg(32'hAC, dval); got[127:96]  = dval;
        rdreg(32'hB0, dval); got[159:128] = dval;
        rdreg(32'hB4, dval); got[191:160] = dval;
        rdreg(32'hB8, dval); got[223:192] = dval;
        rdreg(32'hBC, dval); got[255:224] = dval;

        $display("=== SHA3-256(\"abc\") via memory-mapped accelerator ===");
        $display("Got:      %064h", got);
        $display("Expected: %064h", EXP);
        if (got === EXP) $display("PASS");
        else             $display("FAIL");

        $finish;
    end

endmodule
