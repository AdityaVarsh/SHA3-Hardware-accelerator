`timescale 1ns/1ps
module tb_padder;
    reg clk,rst_n; reg [63:0] msg_in; reg valid_in,is_last; reg [3:0] bc;
    wire [511:0] block_out; wire padd_done, is_last_block;

    sha1_padder DUT(.clk(clk),.rst_n(rst_n),.msg_in(msg_in),.valid_in(valid_in),
        .is_last(is_last),.byte_count(bc),.block_out(block_out),
        .padd_done(padd_done),.is_last_block(is_last_block));

    initial clk=0; always #5 clk=~clk;

    always @(posedge clk) if (padd_done)
        $display("BLOCK last=%b %h", is_last_block, block_out);

    task send; input [63:0] w; input l; input [3:0] k; begin
        msg_in=w; valid_in=1; is_last=l; bc=k; @(posedge clk); #1; valid_in=0; is_last=0; end
    endtask
    task rst; begin rst_n=0; valid_in=0; @(posedge clk);#1;@(posedge clk);#1; rst_n=1; @(posedge clk);#1; end endtask

    integer i;
    initial begin
        rst;
        $display("--- 56 bytes 'a' (expect 2 blocks) ---");
        for(i=0;i<6;i=i+1) send(64'h6161616161616161,0,8); // 48 bytes
        send(64'h6161616161616161,1,8);                    // +8 = 56, last
        #50; rst;
        $display("--- 64 bytes 'a' (expect 2 blocks) ---");
        for(i=0;i<7;i=i+1) send(64'h6161616161616161,0,8); // 56 bytes
        send(64'h6161616161616161,1,8);                    // +8 = 64, last
        #50;
        $finish;
    end
endmodule
