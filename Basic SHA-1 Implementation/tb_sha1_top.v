`timescale 1ns/1ps
module tb_sha1_top;

    reg         clk, rst_n;
    reg  [63:0] msg_in;
    reg         valid_in, is_last;
    reg  [3:0]  byte_count;
    wire [159:0] hash_out;
    wire         hash_valid;

    sha1_top DUT (
        .clk(clk), .rst_n(rst_n),
        .msg_in(msg_in), .valid_in(valid_in),
        .is_last(is_last), .byte_count(byte_count),
        .hash_out(hash_out), .hash_valid(hash_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [2:0] test_num;
    integer   pass_count, fail_count;

    always @(posedge clk) begin
        if (hash_valid) begin
            case (test_num)
                3'd1: begin
                    $display("=== Test 1: Empty String ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: da39a3ee5e6b4b0d3255bfef95601890afd80709");
                    if (hash_out === 160'hda39a3ee5e6b4b0d3255bfef95601890afd80709)
                        begin $display("PASS\n"); pass_count=pass_count+1; end
                    else begin $display("FAIL\n"); fail_count=fail_count+1; end
                end
                3'd2: begin
                    $display("=== Test 2: abc ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: a9993e364706816aba3e25717850c26c9cd0d89d");
                    if (hash_out === 160'ha9993e364706816aba3e25717850c26c9cd0d89d)
                        begin $display("PASS\n"); pass_count=pass_count+1; end
                    else begin $display("FAIL\n"); fail_count=fail_count+1; end
                end
                3'd3: begin
                    $display("=== Test 3: Pangram ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: 2fd4e1c67a2d28fced849ee1bb76e7391b93eb12");
                    if (hash_out === 160'h2fd4e1c67a2d28fced849ee1bb76e7391b93eb12)
                        begin $display("PASS\n"); pass_count=pass_count+1; end
                    else begin $display("FAIL\n"); fail_count=fail_count+1; end
                end
            endcase
        end
    end

    task send_word;
        input [63:0] word; input last; input [3:0] cnt;
        begin
            msg_in=word; valid_in=1; is_last=last; byte_count=cnt;
            @(posedge clk); #1;
            valid_in=0; is_last=0;
        end
    endtask

    task reset_design;
        begin
            rst_n=0; valid_in=0; is_last=0; msg_in=0; byte_count=0;
            @(posedge clk); #1; @(posedge clk); #1;
            rst_n=1; @(posedge clk); #1;
        end
    endtask

    initial begin
        pass_count=0; fail_count=0;
        rst_n=0; valid_in=0; is_last=0; msg_in=0; byte_count=0;
        @(posedge clk); #1; @(posedge clk); #1; rst_n=1; @(posedge clk); #1;

        // Test 1: empty string  (byte_count=0)
        test_num=3'd1;
        send_word(64'h0000000000000000, 1, 4'd0);
        #10000; reset_design;

        // Test 2: "abc"
        test_num=3'd2;
        send_word(64'h6162630000000000, 1, 4'd3);
        #10000; reset_design;

        // Test 3: pangram "The quick brown fox jumps over the lazy dog"
        test_num=3'd3;
        send_word(64'h5468652071756963, 0, 4'd8); // "The quic"
        send_word(64'h6b2062726f776e20, 0, 4'd8); // "k brown "
        send_word(64'h666f78206a756d70, 0, 4'd8); // "fox jump"
        send_word(64'h73206f7665722074, 0, 4'd8); // "s over t"
        send_word(64'h6865206c617a7920, 0, 4'd8); // "he lazy "
        send_word(64'h646f670000000000, 1, 4'd3); // "dog"
        #10000;

        $display("=============================");
        $display("Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=============================");
        $finish;
    end

endmodule
