`timescale 1ns/1ps
// ============================================================================
// tb_integrated : runs the FULL 5-stage pipeline executing a hand-assembled
// RISC-V program that drives the memory-mapped SHA-3 accelerator end to end:
// writes "abc", triggers, polls DONE, reads the digest, stores it to RAM.
// ============================================================================
module tb_integrated;
    reg clk, rst, interrupt;

    main A(.clk(clk), .rst(rst), .interrupt(interrupt));

    always #5 clk = ~clk;

    integer cyc;
    reg [255:0] digest;

    initial begin
        clk = 0; rst = 1; interrupt = 0;
        repeat (3) @(negedge clk);
        rst = 0;

        // let the program run; SHA-3 needs ~45 cycles + program overhead
        for (cyc = 0; cyc < 400; cyc = cyc + 1) @(negedge clk);

        // digest was stored by the program to RAM bytes 0x20..0x3F
        digest[31:0]    = {A.D_mem.d_mem[8'h23],A.D_mem.d_mem[8'h22],A.D_mem.d_mem[8'h21],A.D_mem.d_mem[8'h20]};
        digest[63:32]   = {A.D_mem.d_mem[8'h27],A.D_mem.d_mem[8'h26],A.D_mem.d_mem[8'h25],A.D_mem.d_mem[8'h24]};
        digest[95:64]   = {A.D_mem.d_mem[8'h2B],A.D_mem.d_mem[8'h2A],A.D_mem.d_mem[8'h29],A.D_mem.d_mem[8'h28]};
        digest[127:96]  = {A.D_mem.d_mem[8'h2F],A.D_mem.d_mem[8'h2E],A.D_mem.d_mem[8'h2D],A.D_mem.d_mem[8'h2C]};
        digest[159:128] = {A.D_mem.d_mem[8'h33],A.D_mem.d_mem[8'h32],A.D_mem.d_mem[8'h31],A.D_mem.d_mem[8'h30]};
        digest[191:160] = {A.D_mem.d_mem[8'h37],A.D_mem.d_mem[8'h36],A.D_mem.d_mem[8'h35],A.D_mem.d_mem[8'h34]};
        digest[223:192] = {A.D_mem.d_mem[8'h3B],A.D_mem.d_mem[8'h3A],A.D_mem.d_mem[8'h39],A.D_mem.d_mem[8'h38]};
        digest[255:224] = {A.D_mem.d_mem[8'h3F],A.D_mem.d_mem[8'h3E],A.D_mem.d_mem[8'h3D],A.D_mem.d_mem[8'h3C]};

        $display("=== End-to-end: pipeline-driven SHA3-256(\"abc\") ===");
        $display("Digest in RAM: %064h", digest);
        $display("Expected:      3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532");
        if (digest === 256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end
endmodule
