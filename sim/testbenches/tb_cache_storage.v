`timescale 1ns/1ps

module tb_cache_storage;

    reg clk, reset;
    reg [5:0] lookup_index;
    reg [1:0] lookup_word_offset;

    wire [21:0] lookup_tag;
    wire lookup_valid;
    wire [31:0] lookup_word_data;

    reg refill_en;
    reg [5:0] refill_index;
    reg [21:0] refill_tag;
    reg [127:0] refill_block_data;

    reg word_write_en;
    reg [5:0] word_write_index;
    reg [1:0] word_write_offset;
    reg [31:0] word_write_data;

    cache_storage dut (
        .clk(clk),
        .reset(reset),
        .lookup_index(lookup_index),
        .lookup_word_offset(lookup_word_offset),
        .lookup_tag(lookup_tag),
        .lookup_valid(lookup_valid),
        .lookup_word_data(lookup_word_data),
        .refill_en(refill_en),
        .refill_index(refill_index),
        .refill_tag(refill_tag),
        .refill_block_data(refill_block_data),
        .word_write_en(word_write_en),
        .word_write_index(word_write_index),
        .word_write_offset(word_write_offset),
        .word_write_data(word_write_data)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 0;
        lookup_index = 0;
        lookup_word_offset = 0;
        refill_en = 0;
        refill_index = 0;
        refill_tag = 0;
        refill_block_data = 0;
        word_write_en = 0;
        word_write_index = 0;
        word_write_offset = 0;
        word_write_data = 0;

        // Test 1: Reset invalidates cache
        @(negedge clk);
        reset = 1;
        @(posedge clk);
        #1;
        reset = 0;
        lookup_index = 5;
        #1;
        if (lookup_valid !== 0)
            $fatal(1, "FAIL: Reset did not invalidate line");

        // Test 2: Refill one complete cache line
        @(negedge clk);
        refill_en = 1;
        refill_index = 5;
        refill_tag = 22'h12345;
        refill_block_data =
            128'h44444444_33333333_22222222_11111111;

        @(posedge clk);
        #1;
        refill_en = 0;

        if (lookup_valid !== 1)
            $fatal(1, "FAIL: Refilled line is not valid");

        if (lookup_tag !== 22'h12345)
            $fatal(1, "FAIL: Incorrect tag");

        // Test 3: Check all four words
        lookup_word_offset = 0; #1;
        if (lookup_word_data !== 32'h11111111)
            $fatal(1, "FAIL: Word 0 incorrect");

        lookup_word_offset = 1; #1;
        if (lookup_word_data !== 32'h22222222)
            $fatal(1, "FAIL: Word 1 incorrect");

        lookup_word_offset = 2; #1;
        if (lookup_word_data !== 32'h33333333)
            $fatal(1, "FAIL: Word 2 incorrect");

        lookup_word_offset = 3; #1;
        if (lookup_word_data !== 32'h44444444)
            $fatal(1, "FAIL: Word 3 incorrect");

        // Test 4: Update only word 2
        @(negedge clk);
        word_write_en = 1;
        word_write_index = 5;
        word_write_offset = 2;
        word_write_data = 32'hAAAAAAAA;

        @(posedge clk);
        #1;
        word_write_en = 0;

        lookup_word_offset = 2; #1;
        if (lookup_word_data !== 32'hAAAAAAAA)
            $fatal(1, "FAIL: Word write failed");

        lookup_word_offset = 1; #1;
        if (lookup_word_data !== 32'h22222222)
            $fatal(1, "FAIL: Other words were modified");

        // Test 5: Refill priority over word write
        @(negedge clk);
        refill_en = 1;
        refill_index = 5;
        refill_tag = 22'h54321;
        refill_block_data = 128'h0;
        word_write_en = 1;
        word_write_index = 5;
        word_write_offset = 0;
        word_write_data = 32'hFFFFFFFF;

        @(posedge clk);
        #1;
        refill_en = 0;
        word_write_en = 0;

        lookup_word_offset = 0; #1;
        if (lookup_word_data !== 32'h0)
            $fatal(1, "FAIL: Refill priority incorrect");

        if (lookup_tag !== 22'h54321)
            $fatal(1, "FAIL: Refill tag incorrect");

        $display("==================================");
        $display("ALL CACHE STORAGE TESTS PASSED!");
        $display("==================================");

        $finish;
    end

endmodule
