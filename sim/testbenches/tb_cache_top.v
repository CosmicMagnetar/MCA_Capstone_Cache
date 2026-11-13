`timescale 1ns/1ps

module tb_cache_top;
    localparam integer REQUEST_TIMEOUT_CYCLES = 100;
    localparam integer GLOBAL_TIMEOUT_NS = 200000;
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
    integer word_number;
    integer wave_requested;
    reg [31:0] monitored_addr;
    string scenario;
    string wave_file;

    wire monitored_valid;
    wire [21:0] monitored_tag;
    wire [127:0] monitored_cache_block;
    wire [31:0] monitored_cache_word;
    wire [31:0] monitored_memory_word;

    assign monitored_valid =
        dut.u_cache_storage.valid_array[monitored_addr[9:4]];
    assign monitored_tag = dut.u_cache_storage.tag_array[monitored_addr[9:4]];
    assign monitored_cache_word =
        dut.u_cache_storage.data_array[monitored_addr[9:2]];
    assign monitored_cache_block = {
        dut.u_cache_storage.data_array[{monitored_addr[9:4], 2'd3}],
        dut.u_cache_storage.data_array[{monitored_addr[9:4], 2'd2}],
        dut.u_cache_storage.data_array[{monitored_addr[9:4], 2'd1}],
        dut.u_cache_storage.data_array[{monitored_addr[9:4], 2'd0}]
    };
    assign monitored_memory_word =
        dut.u_main_memory.mem[monitored_addr[13:2]];

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
        input start_now;
        integer cycles;
        reg passed;
        reg protocol_error;
        begin
            // start_now is used only when the previous task returned on a
            // falling edge after a required low-request rising edge.
            protocol_error = 1'b0;
            if (!start_now)
                @(negedge clk);
            else if (clk !== 1'b0) begin
                $display("  protocol error: consecutive request did not start on a falling edge");
                protocol_error = 1'b1;
                @(negedge clk);
            end

            monitored_addr = address;
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

            passed = !protocol_error;
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
            monitored_addr = address;
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

    function [31:0] expected_memory_word;
        input [31:0] address;
        begin
            expected_memory_word = 32'h600d_0000 + (address >> 2);
        end
    endfunction

    task check_reset_state;
        integer line_number;
        reg passed;
        begin
            passed = 1'b1;
            if (controller_state !== 4'd0) begin
                $display("  controller state after reset expected IDLE(0), got %0d",
                         controller_state);
                passed = 1'b0;
            end
            if (total_accesses !== 32'd0 || total_hits !== 32'd0 ||
                total_misses !== 32'd0) begin
                $display("  counters after reset expected 0/0/0, got %0d/%0d/%0d",
                         total_accesses, total_hits, total_misses);
                passed = 1'b0;
            end
            for (line_number = 0; line_number < 64; line_number = line_number + 1) begin
                if (dut.u_cache_storage.valid_array[line_number] !== 1'b0) begin
                    $display("  valid bit at cache index %0d was not cleared", line_number);
                    passed = 1'b0;
                end
            end
            report_test("reset clears all valid bits, counters and controller state", passed);
        end
    endtask

    task check_refill_order;
        input [31:0] block_address;
        input string test_name;
        reg [127:0] expected_block;
        reg passed;
        integer base_word;
        integer cache_word;
        begin
            base_word = (block_address >> 2) & 12'hffc;
            expected_block[31:0] = 32'h600d_0000 + base_word;
            expected_block[63:32] = 32'h600d_0000 + base_word + 1;
            expected_block[95:64] = 32'h600d_0000 + base_word + 2;
            expected_block[127:96] = 32'h600d_0000 + base_word + 3;
            passed = 1'b1;

            if (dut.mem_block_data !== expected_block) begin
                $display("  memory refill bus order mismatch: expected=0x%032h got=0x%032h",
                         expected_block, dut.mem_block_data);
                passed = 1'b0;
            end
            if (monitored_cache_block !== expected_block) begin
                $display("  installed cache block order mismatch: expected=0x%032h got=0x%032h",
                         expected_block, monitored_cache_block);
                passed = 1'b0;
            end

            cache_word = block_address[9:2];
            for (word_number = 0; word_number < 4; word_number = word_number + 1) begin
                if (dut.u_cache_storage.data_array[cache_word + word_number] !==
                    (32'h600d_0000 + base_word + word_number)) begin
                    $display("  refill word %0d mismatch: expected=0x%08h got=0x%08h",
                             word_number, 32'h600d_0000 + base_word + word_number,
                             dut.u_cache_storage.data_array[cache_word + word_number]);
                    passed = 1'b0;
                end
            end
            report_test(test_name, passed);
        end
    endtask

    task check_unchanged_block_words;
        input [31:0] block_address;
        input [1:0] changed_word_offset;
        input string test_name;
        integer line_number;
        integer cache_word;
        integer base_word;
        reg passed;
        begin
            line_number = block_address[9:4];
            cache_word = block_address[9:2];
            base_word = (block_address >> 2) & 12'hffc;
            passed = 1'b1;
            for (word_number = 0; word_number < 4; word_number = word_number + 1) begin
                if (word_number != changed_word_offset) begin
                    if (dut.u_cache_storage.data_array[cache_word + word_number] !==
                        (32'h600d_0000 + base_word + word_number)) begin
                        $display("  unrelated cache word %0d in block 0x%08h changed unexpectedly",
                                 word_number, block_address);
                        passed = 1'b0;
                    end
                    if (dut.u_main_memory.mem[base_word + word_number] !==
                        (32'h600d_0000 + base_word + word_number)) begin
                        $display("  unrelated memory word %0d in block 0x%08h changed unexpectedly",
                                 word_number, block_address);
                        passed = 1'b0;
                    end
                end
            end
            if (dut.u_cache_storage.valid_array[line_number] !== 1'b1 ||
                dut.u_cache_storage.tag_array[line_number] !== block_address[31:10]) begin
                $display("  line tag/valid changed unexpectedly while checking block 0x%08h",
                         block_address);
                passed = 1'b0;
            end
            report_test(test_name, passed);
        end
    endtask

    task busy_request_test;
        input [31:0] active_address;
        input [31:0] active_expected_data;
        input [31:0] busy_address;
        integer cycles;
        reg passed;
        begin
            @(negedge clk);
            monitored_addr = active_address;
            cpu_addr = active_address;
            cpu_write = 1'b0;
            cpu_wdata = 32'b0;
            cpu_req = 1'b1;
            @(negedge clk);
            cpu_req = 1'b0;

            cycles = 0;
            while ((controller_state !== 4'd2) &&
                   (cycles < REQUEST_TIMEOUT_CYCLES)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            passed = 1'b1;
            if (controller_state !== 4'd2) begin
                $display("  controller did not reach REFILL_WAIT before busy request");
                passed = 1'b0;
            end else begin
                @(negedge clk);
                monitored_addr = busy_address;
                cpu_addr = busy_address;
                cpu_write = 1'b0;
                cpu_wdata = 32'b0;
                cpu_req = 1'b1;
                @(negedge clk);
                cpu_req = 1'b0;
            end

            cycles = 0;
            while ((cpu_ready !== 1'b1) &&
                   (cycles < REQUEST_TIMEOUT_CYCLES)) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (cpu_ready !== 1'b1) begin
                $display("  timeout waiting for original busy-period request response");
                passed = 1'b0;
            end else if (cpu_rdata !== active_expected_data) begin
                $display("  active request returned stale/wrong data: expected=0x%08h got=0x%08h",
                         active_expected_data, cpu_rdata);
                passed = 1'b0;
            end

            expected_accesses = expected_accesses + 1;
            expected_misses = expected_misses + 1;
            if (cpu_ready === 1'b1) begin
                @(negedge clk);
                if (cpu_ready !== 1'b0) begin
                    $display("  original response was not a one-cycle pulse");
                    passed = 1'b0;
                end
                check_counters("busy-period original miss", passed);
            end

            // Give any incorrectly queued busy request time to surface before
            // deliberately issuing that address again as a new transaction.
            repeat (3) begin
                @(negedge clk);
                if (cpu_ready !== 1'b0 ||
                    total_accesses !== expected_accesses[31:0] ||
                    total_hits !== expected_hits[31:0] ||
                    total_misses !== expected_misses[31:0]) begin
                    $display("  busy request produced an unexpected completion/counter update");
                    passed = 1'b0;
                end
            end
            report_test("busy request is dropped; original miss completes once", passed);
        end
    endtask

    task check_final_counter;
        input string counter_name;
        input [31:0] expected_value;
        input [31:0] actual_value;
        begin
            if (actual_value !== expected_value) begin
                $display("FAIL: counter %0s expected=%0d actual=%0d",
                         counter_name, expected_value, actual_value);
                report_test({"performance counter ", counter_name}, 1'b0);
            end else begin
                $display("PASS: counter %0s expected=%0d actual=%0d",
                         counter_name, expected_value, actual_value);
                report_test({"performance counter ", counter_name}, 1'b1);
            end
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
        monitored_addr = 32'b0;
        expected_accesses = 0;
        expected_hits = 0;
        expected_misses = 0;
        tests_run = 0;
        tests_passed = 0;
        tests_failed = 0;

        scenario = "all";
        wave_file = "";
        wave_requested = $value$plusargs("SCENARIO=%s", scenario);
        wave_requested = $value$plusargs("WAVE=%s", wave_file);
        if (wave_requested) begin
            $dumpfile(wave_file);
            $dumpvars(0, clk, reset, cpu_req, cpu_write, cpu_addr, cpu_wdata,
                      cpu_ready, cpu_rdata, total_accesses, total_hits,
                      total_misses, controller_state, monitored_addr,
                      monitored_valid, monitored_tag, monitored_cache_word,
                      monitored_cache_block, monitored_memory_word,
                      dut.lookup_addr, dut.mem_req, dut.mem_write_en,
                      dut.mem_addr, dut.mem_write_data, dut.mem_ready,
                      dut.mem_block_data, dut.cache_refill_en,
                      dut.cache_refill_index, dut.cache_refill_tag,
                      dut.cache_refill_data, dut.cache_word_we,
                      dut.cache_word_index, dut.cache_word_offset,
                      dut.cache_word_wdata, dut.access_complete,
                      dut.hit_event, dut.miss_event);
        end

        if (scenario != "all" && scenario != "reset_invalid_lines" &&
            scenario != "cache_miss" && scenario != "cache_hit" &&
            scenario != "consecutive_requests" &&
            scenario != "controller_busy" &&
            scenario != "block_refill_order" &&
            scenario != "conflict_replacement" &&
            scenario != "write_through") begin
            $fatal(1, "Unknown SCENARIO=%0s", scenario);
        end

        // The memory model initializes to zero at time 0. Seed every word
        // after that initialization and before releasing synchronous reset.
        #1;
        for (init_word = 0; init_word < 4096; init_word = init_word + 1)
            dut.u_main_memory.mem[init_word] = 32'h600d_0000 + init_word;

        repeat (3) @(negedge clk);
        reset = 1'b0;
        @(negedge clk);

        check_reset_state;

        if (scenario == "all" || scenario == "reset_invalid_lines") begin
            read_transaction(32'h0000_0000, expected_memory_word(32'h0), 1'b0,
                             "first read after reset is a cold miss", 1'b0);
        end

        if (scenario == "all") begin
            passed = (CONFLICT_ADDR_A[9:4] == CONFLICT_ADDR_B[9:4]) &&
                     (CONFLICT_ADDR_A[31:10] != CONFLICT_ADDR_B[31:10]);
            report_test("Issue #7 conflict addresses share index and differ in tag", passed);
            read_transaction(32'h0000_0000, 32'h600d_0000, 1'b1,
                             "Issue #7 repeated address is a hit", 1'b0);
            read_transaction(32'h0000_0004, 32'h600d_0001, 1'b1,
                             "Issue #7 second word in the block is a hit", 1'b0);
            read_transaction(32'h0000_0400, 32'h600d_0100, 1'b0,
                             "Issue #7 conflicting tag misses and replaces", 1'b0);
            read_transaction(32'h0000_0000, 32'h600d_0000, 1'b0,
                             "Issue #7 evicted block re-access misses", 1'b0);
            write_transaction(32'h0000_0004, 32'hdead_beef, 1'b1,
                              "Issue #7 cached-word write is a hit");
            check_cache_memory_word(32'h0000_0004, 32'hdead_beef,
                                    "Issue #7 write hit updates cache and memory");
            read_transaction(32'h0000_0004, 32'hdead_beef, 1'b1,
                             "Issue #7 read after write hit returns updated data", 1'b0);
            write_transaction(32'h0000_0804, 32'hcafe_1234, 1'b0,
                              "Issue #7 uncached-word write is a miss");
            check_cache_memory_word(32'h0000_0804, 32'hcafe_1234,
                                    "Issue #7 write miss allocates and updates memory");
            read_transaction(32'h0000_0804, 32'hcafe_1234, 1'b1,
                             "Issue #7 read after write miss is a hit", 1'b0);
        end

        if (scenario == "cache_miss") begin
            read_transaction(32'h0000_0000, expected_memory_word(32'h0), 1'b0,
                             "cold cache access misses and returns memory data", 1'b0);
        end
        if (scenario == "cache_hit") begin
            read_transaction(32'h0000_0000, expected_memory_word(32'h0), 1'b0,
                             "cold fill before hit waveform", 1'b0);
            read_transaction(32'h0000_0000, expected_memory_word(32'h0), 1'b1,
                             "repeated cache access hits", 1'b0);
        end

        if (scenario == "all" || scenario == "consecutive_requests") begin
            read_transaction(32'h0000_0010, expected_memory_word(32'h10), 1'b0,
                             "consecutive sequence starts with a cold miss", 1'b0);
            read_transaction(32'h0000_0014, expected_memory_word(32'h14), 1'b1,
                             "next protocol-legal request returns word one", 1'b1);
            read_transaction(32'h0000_0018, expected_memory_word(32'h18), 1'b1,
                             "following protocol-legal request returns word two", 1'b1);
        end

        if (scenario == "all" || scenario == "controller_busy") begin
            busy_request_test(32'h0000_0020, expected_memory_word(32'h20),
                              32'h0000_0050);
            read_transaction(32'h0000_0050, expected_memory_word(32'h50), 1'b0,
                             "busy-period address was not queued and is a new cold miss", 1'b0);
        end

        if (scenario == "all" || scenario == "block_refill_order") begin
            read_transaction(32'h0000_003c, expected_memory_word(32'h3c), 1'b0,
                             "cold read of refill word three returns correct data", 1'b0);
            check_refill_order(32'h0000_0030,
                               "refill bus and installed cache line preserve four-word order");
            read_transaction(32'h0000_0030, expected_memory_word(32'h30), 1'b1,
                             "refilled word zero is a hit with correct data", 1'b0);
            read_transaction(32'h0000_0034, expected_memory_word(32'h34), 1'b1,
                             "refilled word one is a hit with correct data", 1'b0);
            read_transaction(32'h0000_0038, expected_memory_word(32'h38), 1'b1,
                             "refilled word two is a hit with correct data", 1'b0);
        end

        if (scenario == "all" || scenario == "conflict_replacement") begin
            read_transaction(32'h0000_0060, expected_memory_word(32'h60), 1'b0,
                             "replacement sequence loads original block", 1'b0);
            read_transaction(32'h0000_0460, expected_memory_word(32'h460), 1'b0,
                             "same-index replacement returns new block data", 1'b0);
            check_cache_memory_word(32'h0000_0460, expected_memory_word(32'h460),
                                    "replacement installed the new tag and word");
            read_transaction(32'h0000_0460, expected_memory_word(32'h460), 1'b1,
                             "replacement block is a hit with its own data", 1'b0);
            read_transaction(32'h0000_0060, expected_memory_word(32'h60), 1'b0,
                             "evicted data is refetched rather than returned stale", 1'b0);
        end

        if (scenario == "all" || scenario == "write_through") begin
            read_transaction(32'h0000_0040, expected_memory_word(32'h40), 1'b0,
                             "write-through sequence first fills target block", 1'b0);
            write_transaction(32'h0000_0044, 32'hface_1234, 1'b1,
                              "write-through hit updates cached word and completes");
            check_cache_memory_word(32'h0000_0044, 32'hface_1234,
                                    "write hit is visible in both cache and memory");
            check_unchanged_block_words(32'h0000_0040, 2'd1,
                                        "write hit preserves the other three block words");
            write_transaction(32'h0000_0844, 32'h0bad_c0de, 1'b0,
                              "write-through miss allocates the block and completes");
            check_cache_memory_word(32'h0000_0844, 32'h0bad_c0de,
                                    "write miss is visible in allocated cache and memory");
            check_unchanged_block_words(32'h0000_0840, 2'd1,
                                        "write miss preserves the other three block words");
            read_transaction(32'h0000_0844, 32'h0bad_c0de, 1'b1,
                             "read after write miss hits with updated data", 1'b0);
        end

        check_final_counter("total_accesses", expected_accesses[31:0], total_accesses);
        check_final_counter("total_hits", expected_hits[31:0], total_hits);
        check_final_counter("total_misses", expected_misses[31:0], total_misses);

        $display("\n===============================================");
        $display("cache_top scenario %0s: %0d run, %0d passed, %0d failed",
                 scenario, tests_run, tests_passed, tests_failed);
        $display("performance counters expected accesses/hits/misses: %0d/%0d/%0d",
                 expected_accesses, expected_hits, expected_misses);
        $display("performance counters actual   accesses/hits/misses: %0d/%0d/%0d",
                 total_accesses, total_hits, total_misses);
        $display("===============================================");

        if (tests_failed != 0 || total_accesses !== expected_accesses[31:0] ||
            total_hits !== expected_hits[31:0] ||
            total_misses !== expected_misses[31:0]) begin
            $display("FINAL RESULT: FAIL");
            $fatal(1, "cache_top Issue #8 verification failed");
        end else begin
            $display("FINAL RESULT: PASS");
            $finish;
        end
    end

    initial begin : global_timeout
        #GLOBAL_TIMEOUT_NS;
        $display("FINAL RESULT: FAIL (global simulation timeout)");
        $fatal(1, "cache_top verification timed out");
    end
endmodule
