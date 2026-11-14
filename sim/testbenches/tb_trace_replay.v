`timescale 1ns/1ps

// Replays one read trace through the full cache_top and measures the real
// cycle count of every access. Run once per workload so each trace starts
// from a cold cache, the same way the Python model does.
//
//   vvp tb_trace_replay.vvp +TRACE=sim/traces/build/sequential.hex +N=20 +NAME=sequential
module tb_trace_replay;
    localparam MAX_ACCESSES = 1024;
    localparam TIMEOUT = 64;

    reg clk = 1'b0;
    reg reset = 1'b1;
    reg cpu_req = 1'b0;
    reg cpu_write = 1'b0;
    reg [31:0] cpu_addr = 32'd0;
    reg [31:0] cpu_wdata = 32'd0;

    wire cpu_ready;
    wire [31:0] cpu_rdata;
    wire [31:0] total_accesses, total_hits, total_misses;
    wire [3:0] controller_state;

    cache_top dut (
        .clk(clk), .reset(reset),
        .cpu_req(cpu_req), .cpu_write(cpu_write),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_ready(cpu_ready), .cpu_rdata(cpu_rdata),
        .total_accesses(total_accesses), .total_hits(total_hits),
        .total_misses(total_misses), .controller_state(controller_state)
    );

    always #5 clk = ~clk;

    reg [31:0] trace [0:MAX_ACCESSES-1];
    reg [1023:0] trace_file;
    reg [255:0] name;
    integer n, i, k, cycles, total_cycles, hit_cycles, miss_cycles;
    integer errors;
    reg [31:0] hits_before;

    function [31:0] pattern(input [31:0] word_index);
        pattern = 32'hC0DE_0000 ^ (word_index * 32'h0001_0003);
    endfunction

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_file)) begin
            $display("ERROR: pass +TRACE=<hex file>");
            $finish;
        end
        if (!$value$plusargs("N=%d", n)) n = 0;
        if (!$value$plusargs("NAME=%s", name)) name = "trace";
        if (n <= 0 || n > MAX_ACCESSES) begin
            $display("ERROR: +N must be between 1 and %0d", MAX_ACCESSES);
            $finish;
        end
        $readmemh(trace_file, trace, 0, n - 1);

        // Give every memory word a distinct value so a wrong word or a
        // stale line shows up as a data mismatch.
        #1;
        for (k = 0; k < 4096; k = k + 1)
            dut.u_main_memory.mem[k] = pattern(k);

        repeat (3) @(negedge clk);
        reset = 1'b0;
        @(negedge clk);

        errors = 0;
        total_cycles = 0;
        hit_cycles = 0;
        miss_cycles = 0;

        for (i = 0; i < n; i = i + 1) begin
            hits_before = total_hits;
            cpu_addr = trace[i];
            cpu_req = 1'b1;
            @(negedge clk);
            cpu_req = 1'b0;
            cycles = 1;
            while (cpu_ready !== 1'b1 && cycles < TIMEOUT) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (cpu_ready !== 1'b1) begin
                $display("ERROR: timeout on access %0d addr=0x%08h", i, trace[i]);
                errors = errors + 1;
            end else if (cpu_rdata !== pattern(trace[i][13:2])) begin
                $display("ERROR: access %0d addr=0x%08h got=0x%08h want=0x%08h",
                         i, trace[i], cpu_rdata, pattern(trace[i][13:2]));
                errors = errors + 1;
            end
            @(negedge clk);
            total_cycles = total_cycles + cycles;
            if (total_hits != hits_before)
                hit_cycles = hit_cycles + cycles;
            else
                miss_cycles = miss_cycles + cycles;
        end

        if (total_accesses != n) begin
            $display("ERROR: counter saw %0d accesses, trace has %0d", total_accesses, n);
            errors = errors + 1;
        end

        // One machine-readable line per run, collected by run_trace_benchmark.sh
        $display("RESULT,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d", name, n, total_hits, total_misses,
                 total_cycles, hit_cycles, miss_cycles, errors);
        $display(errors == 0 ? "FINAL RESULT: PASS" : "FINAL RESULT: FAIL");
        $finish;
    end
endmodule
