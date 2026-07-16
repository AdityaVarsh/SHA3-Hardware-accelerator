`timescale 1ns/1ps
module tb_sha3_top;

    reg         clk;
    reg         rst_n;
    reg  [63:0] msg_in;
    reg         valid_in;
    reg         is_last;
    reg  [3:0]  byte_count;
    wire [255:0] hash_out;
    wire         hash_valid;

    sha3_top DUT (
        .clk       (clk),
        .rst_n     (rst_n),
        .msg_in    (msg_in),
        .valid_in  (valid_in),
        .is_last   (is_last),
        .byte_count(byte_count),
        .hash_out  (hash_out),
        .hash_valid(hash_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg [2:0] test_num;
    integer   pass_count;
    integer   fail_count;

    always @(posedge clk) begin
        if (hash_valid) begin
            case (test_num)
                3'd1: begin
                    $display("=== Test 1: Empty String ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a");
                    if (hash_out === 256'ha7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a) begin
                        $display("PASS\n"); pass_count = pass_count + 1;
                    end else begin
                        $display("FAIL\n"); fail_count = fail_count + 1;
                    end
                end
                3'd2: begin
                    $display("=== Test 2: abc ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532");
                    if (hash_out === 256'h3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532) begin
                        $display("PASS\n"); pass_count = pass_count + 1;
                    end else begin
                        $display("FAIL\n"); fail_count = fail_count + 1;
                    end
                end
                3'd3: begin
                    $display("=== Test 3: Pangram ===");
                    $display("Got:      %h", hash_out);
                    $display("Expected: 69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04");
                    if (hash_out === 256'h69070dda01975c8c120c3aada1b282394e7f032fa9cf32f4cb2259a0897dfc04) begin
                        $display("PASS\n"); pass_count = pass_count + 1;
                    end else begin
                        $display("FAIL\n"); fail_count = fail_count + 1;
                    end
                end
            endcase
        end
    end

    task send_word;
        input [63:0] word;
        input        last;
        input [3:0]  cnt;
        begin
            msg_in     = word;
            valid_in   = 1;
            is_last    = last;
            byte_count = cnt;
            @(posedge clk); #1;
            valid_in = 0;
            is_last  = 0;
        end
    endtask

    task reset_design;
        begin
            rst_n    = 0;
            valid_in = 0;
            is_last  = 0;
            msg_in   = 0;
            byte_count = 0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst_n = 1;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n      = 0;
        valid_in   = 0;
        is_last    = 0;
        msg_in     = 0;
        byte_count = 0;

        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        // Test 1: Empty string
        test_num = 3'd1;
        send_word(64'h0000000000000000, 1, 4'd0);
        #10000;
        reset_design;

        // Test 2: abc
        test_num = 3'd2;
        send_word(64'h6162630000000000, 1, 4'd3);
        #10000;
        reset_design;

        // Test 3: Pangram
        test_num = 3'd3;
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