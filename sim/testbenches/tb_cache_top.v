`timescale 1ns/1ps

module tb_cache_top;
    localparam integer REQUEST_TIMEOUT_CYCLES = 100;
    localparam [31:0] CONFLICT_ADDR_A = 32'h0000_0000;
    localparam [31:0] CONFLICT_ADDR_B = 32'h0000_0400;

    reg clk;
    reg reset;
    reg cpu_req;
    reg cpu_write;
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;

    wire cpu_ready;
    wire [31:0] cpu_rdata;
    wire [31:0] total_accesses;
    wire [31:0] total_hits;
    wire [31:0] total_misses;
    wire [3:0] controller_state;

    integer expected_accesses;
    integer expected_hits;
    integer expected_misses;
    integer tests_run;
    integer tests_passed;
    integer tests_failed;
    integer init_word;

    cache_top dut (
        .clk(clk),
        .reset(reset),
        .cpu_req(cpu_req),
        .cpu_write(cpu_write),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready),
        .cpu_rdata(cpu_rdata),
        .total_accesses(total_accesses),
        .total_hits(total_hits),
        .total_misses(total_misses),
        .controller_state(controller_state)
    );

    always #5 clk = ~clk;

    task report_test;
        input string test_name;
        input integer passed;
        begin
            tests_run = tests_run + 1;
            if (passed) begin
                tests_passed = tests_passed + 1;
                $display("PASS: %0s", test_name);
            end else begin
                tests_failed = tests_failed + 1;
                $display("FAIL: %0s", test_name);
            end
        end
    endtask

    task check_counters;
        input string test_name;
        inout reg passed;
        begin
            if (total_accesses !== expected_accesses[31:0]) begin
                $display("  counter mismatch after %0s: accesses expected=%0d got=%0d",
                         test_name, expected_accesses, total_accesses);
                passed = 1'b0;
            end
            if (total_hits !== expected_hits[31:0]) begin
                $display("  counter mismatch after %0s: hits expected=%0d got=%0d",
                         test_name, expected_hits, total_hits);
                passed = 1'b0;
            end
            if (total_misses !== expected_misses[31:0]) begin
                $display("  counter mismatch after %0s: misses expected=%0d got=%0d",
                         test_name, expected_misses, total_misses);
                passed = 1'b0;
            end
        end
    endtask

    task read_transaction;
        input [31:0] address;
        input [31:0] expected_data;
        input expected_hit;
        input string test_name;
        integer cycles;
        reg passed;
        begin
            // Drive on a falling edge; the controller samples on rising edges.
            @(negedge clk);
            cpu_addr = address;
            cpu_write = 1'b0;
            cpu_wdata = 32'b0;
            cpu_req = 1'b1;
            @(negedge clk);
            cpu_req = 1'b0;

            cycles = 0;
            while ((cpu_ready !== 1'b1) &&
                   (cycles < REQUEST_TIMEOUT_CYCLES)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            passed = 1'b1;
            if (cpu_ready !== 1'b1) begin
                $display("  timeout waiting for read response at 0x%08h (state=%0d)",
                         address, controller_state);
                passed = 1'b0;
            end else if (cpu_rdata !== expected_data) begin
                $display("  read data mismatch at 0x%08h: expected=0x%08h got=0x%08h",
                         address, expected_data, cpu_rdata);
                passed = 1'b0;
            end

            if (expected_hit) begin
                expected_hits = expected_hits + 1;
            end else begin
                expected_misses = expected_misses + 1;
            end
            expected_accesses = expected_accesses + 1;

            if (cpu_ready === 1'b1) begin
                // The monitor samples the registered completion event on the
                // next rising edge, so check counters after that edge.
                @(negedge clk);
                if (cpu_ready !== 1'b0) begin
                    $display("  cpu_ready did not return low after the response pulse");
                    passed = 1'b0;
                end
                check_counters(test_name, passed);
            end

            report_test(test_name, passed);
        end
    endtask

    task write_transaction;
        input [31:0] address;
        input [31:0] write_data;
        input expected_hit;
        input string test_name;
        integer cycles;
        reg passed;
        begin
            @(negedge clk);
            cpu_addr = address;
            cpu_write = 1'b1;
            cpu_wdata = write_data;
            cpu_req = 1'b1;
            @(negedge clk);
            cpu_req = 1'b0;

            cycles = 0;
            while ((cpu_ready !== 1'b1) &&
                   (cycles < REQUEST_TIMEOUT_CYCLES)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            passed = 1'b1;
            if (cpu_ready !== 1'b1) begin
                $display("  timeout waiting for write response at 0x%08h (state=%0d)",
                         address, controller_state);
                passed = 1'b0;
            end

            if (expected_hit) begin
                expected_hits = expected_hits + 1;
            end else begin
                expected_misses = expected_misses + 1;
            end
            expected_accesses = expected_accesses + 1;

            if (cpu_ready === 1'b1) begin
                @(negedge clk);
                if (cpu_ready !== 1'b0) begin
                    $display("  cpu_ready did not return low after the response pulse");
                    passed = 1'b0;
                end
                check_counters(test_name, passed);
            end

            report_test(test_name, passed);
        end
    endtask

    task check_cache_memory_word;
        input [31:0] address;
        input [31:0] expected_data;
        input string test_name;
        integer line_index;
        integer cache_word_index;
        integer memory_word_index;
        reg passed;
        begin
            line_index = address[9:4];
            cache_word_index = address[9:2];
            memory_word_index = address[13:2];
            passed = 1'b1;

            if (dut.u_cache_storage.valid_array[line_index] !== 1'b1) begin
                $display("  cache line %0d is not valid", line_index);
                passed = 1'b0;
            end
            if (dut.u_cache_storage.tag_array[line_index] !== address[31:10]) begin
                $display("  cache tag mismatch at index %0d: expected=0x%06h got=0x%06h",
                         line_index, address[31:10],
                         dut.u_cache_storage.tag_array[line_index]);
                passed = 1'b0;
            end
            if (dut.u_cache_storage.data_array[cache_word_index] !== expected_data) begin
                $display("  cache data mismatch at 0x%08h: expected=0x%08h got=0x%08h",
                         address, expected_data,
                         dut.u_cache_storage.data_array[cache_word_index]);
                passed = 1'b0;
            end
            if (dut.u_main_memory.mem[memory_word_index] !== expected_data) begin
                $display("  memory data mismatch at 0x%08h: expected=0x%08h got=0x%08h",
                         address, expected_data,
                         dut.u_main_memory.mem[memory_word_index]);
                passed = 1'b0;
            end

            report_test(test_name, passed);
        end
    endtask

    initial begin : run_tests
        reg passed;

        clk = 1'b0;
        reset = 1'b1;
        cpu_req = 1'b0;
        cpu_write = 1'b0;
        cpu_addr = 32'b0;
        cpu_wdata = 32'b0;
        expected_accesses = 0;
        expected_hits = 0;
        expected_misses = 0;
        tests_run = 0;
        tests_passed = 0;
        tests_failed = 0;

        // The memory model initializes to zero at time 0. Seed every word
        // after that initialization and before releasing synchronous reset.
        #1;
        for (init_word = 0; init_word < 4096; init_word = init_word + 1)
            dut.u_main_memory.mem[init_word] = 32'h600d_0000 + init_word;

        repeat (3) @(negedge clk);
        reset = 1'b0;
        @(negedge clk);

        passed = 1'b1;
        if (total_accesses !== 32'd0 || total_hits !== 32'd0 ||
            total_misses !== 32'd0) begin
            $display("  performance counters did not reset to zero");
            passed = 1'b0;
        end
        if (dut.u_cache_storage.valid_array[0] !== 1'b0) begin
            $display("  cache index zero was not invalidated by reset");
            passed = 1'b0;
        end
        report_test("synchronous reset and deterministic memory initialization", passed);

        passed = (CONFLICT_ADDR_A[9:4] == CONFLICT_ADDR_B[9:4]) &&
                 (CONFLICT_ADDR_A[31:10] != CONFLICT_ADDR_B[31:10]);
        report_test("conflict addresses share index and differ in tag", passed);

        read_transaction(32'h0000_0000, 32'h600d_0000, 1'b0,
                         "cold read of 0x00000000 is a miss with correct data");
        read_transaction(32'h0000_0000, 32'h600d_0000, 1'b1,
                         "repeated read of 0x00000000 is a hit");
        read_transaction(32'h0000_0004, 32'h600d_0001, 1'b1,
                         "second word of the same block is a hit");
        read_transaction(32'h0000_0400, 32'h600d_0100, 1'b0,
                         "same-index different-tag access misses and replaces");
        read_transaction(32'h0000_0000, 32'h600d_0000, 1'b0,
                         "re-access of the evicted block misses and refills");

        write_transaction(32'h0000_0004, 32'hdead_beef, 1'b1,
                          "write to cached word completes as a write hit");
        check_cache_memory_word(32'h0000_0004, 32'hdead_beef,
                                "write hit updates both cache and main memory");
        read_transaction(32'h0000_0004, 32'hdead_beef, 1'b1,
                         "read after write hit returns updated cached data");

        write_transaction(32'h0000_0804, 32'hcafe_1234, 1'b0,
                          "write to uncached block completes as a write miss");
        check_cache_memory_word(32'h0000_0804, 32'hcafe_1234,
                                "write miss allocates line and updates main memory");
        read_transaction(32'h0000_0804, 32'hcafe_1234, 1'b1,
                         "read after write miss hits and returns written data");

        $display("\n===============================================");
        $display("cache_top Issue #7: %0d run, %0d passed, %0d failed",
                 tests_run, tests_passed, tests_failed);
        $display("performance counters: accesses=%0d hits=%0d misses=%0d",
                 total_accesses, total_hits, total_misses);
        $display("expected counters:    accesses=%0d hits=%0d misses=%0d",
                 expected_accesses, expected_hits, expected_misses);
        $display("===============================================");

        if (tests_failed != 0 || total_accesses !== expected_accesses[31:0] ||
            total_hits !== expected_hits[31:0] ||
            total_misses !== expected_misses[31:0]) begin
            $display("FINAL RESULT: FAIL");
            $fatal(1, "cache_top Issue #7 testbench failed");
        end else begin
            $display("FINAL RESULT: PASS");
            $finish;
        end
    end

    initial begin : global_timeout
        #100000;
        $display("FINAL RESULT: FAIL (global simulation timeout)");
        $fatal(1, "cache_top Issue #7 testbench timed out");
    end
endmodule
