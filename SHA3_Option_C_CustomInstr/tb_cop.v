`timescale 1ns/1ps
// ============================================================================
// tb_cop : full pipeline executing a program that drives the SHA-3 coprocessor
// through CUSTOM-0 instructions (no memory map). Verifies SHA3-256("abc").
// Digest is stored by the program to RAM bytes 0x40..0x5F.
// ============================================================================
module tb_cop;
    reg clk, rst, interrupt;
    main A(.clk(clk), .rst(rst), .interrupt(interrupt));
    always #5 clk=~clk;

    integer cyc; reg [255:0] digest;

    initial begin
        clk=0; rst=1; interrupt=0;
        repeat(3) @(negedge clk); rst=0;
        for (cyc=0; cyc<400; cyc=cyc+1) @(negedge clk);

        digest[31:0]    = {A.D_mem.d_mem[8'h43],A.D_mem.d_mem[8'h42],A.D_mem.d_mem[8'h41],A.D_mem.d_mem[8'h40]};
        digest[63:32]   = {A.D_mem.d_mem[8'h47],A.D_mem.d_mem[8'h46],A.D_mem.d_mem[8'h45],A.D_mem.d_mem[8'h44]};
        digest[95:64]   = {A.D_mem.d_mem[8'h4B],A.D_mem.d_mem[8'h4A],A.D_mem.d_mem[8'h49],A.D_mem.d_mem[8'h48]};
        digest[127:96]  = {A.D_mem.d_mem[8'h4F],A.D_mem.d_mem[8'h4E],A.D_mem.d_mem[8'h4D],A.D_mem.d_mem[8'h4C]};
        digest[159:128] = {A.D_mem.d_mem[8'h53],A.D_mem.d_mem[8'h52],A.D_mem.d_mem[8'h51],A.D_mem.d_mem[8'h50]};
        digest[191:160] = {A.D_mem.d_mem[8'h57],A.D_mem.d_mem[8'h56],A.D_mem.d_mem[8'h55],A.D_mem.d_mem[8'h54]};
        digest[223:192] = {A.D_mem.d_mem[8'h5B],A.D_mem.d_mem[8'h5A],A.D_mem.d_mem[8'h59],A.D_mem.d_mem[8'h58]};
        digest[255:224] = {A.D_mem.d_mem[8'h5F],A.D_mem.d_mem[8'h5E],A.D_mem.d_mem[8'h5D],A.D_mem.d_mem[8'h5C]};

        $display("=== Option C: custom-instruction SHA3-256(\"abc\") ===");
        $display("Digest in RAM: %064h", digest);
        $display("Expected:      3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532");
        if (digest === 256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532)
            $display("PASS");
        else
            $display("FAIL");
        $finish;
    end
endmodule
