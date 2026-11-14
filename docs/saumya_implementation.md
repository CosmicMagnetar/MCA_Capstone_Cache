# Saumya's Phase I Implementation Notes

**Scope:** Main-memory model (Issue #4) and performance monitor (Issue #5).

## Behavioral main-memory model

File: `memory/main_memory_model.v`

- Default configuration: 32-bit addresses, 4096 words (16 KiB), five-cycle response latency.
- 32-bit memory words, initialized to zero at simulation start.
- Optional `MEM_INIT_FILE` parameter invokes `$readmemh` after zero-filling the array.
- One outstanding request; a one-cycle `req` pulse is accepted while idle.
- Read requests return four consecutive 32-bit words from the aligned 16-byte block in ascending address order.
- Write requests update one 32-bit word (write-through from the cache controller).
- A one-cycle `ready` response indicates operation completion.
- Synchronous reset clears protocol state and outputs but deliberately does not erase memory contents.
- The model is behavioral and intended for simulation; it is not a physical synthesizable memory macro.

## Performance monitor

File: `rtl/performance_monitor.v`

- Three 32-bit counters: total accesses, hits and misses.
- Synchronous active-high reset clears all counters.
- An event is counted only when `access_complete` is high and exactly one of `hit_event` or `miss_event` is high.
- Incomplete accesses, simultaneous hit/miss assertions and unclassified completions are ignored.
- For accepted events, `total_accesses = total_hits + total_misses` (until 32-bit wraparound).

## Verification

Run from the repository root:

```sh
iverilog -g2012 -Wall -s tb_main_memory -o /tmp/tb_main_memory.vvp memory/main_memory_model.v sim/testbenches/tb_main_memory.v
vvp /tmp/tb_main_memory.vvp

iverilog -g2012 -Wall -s tb_memory_init -o /tmp/tb_memory_init.vvp memory/main_memory_model.v sim/testbenches/tb_memory_init.v
vvp /tmp/tb_memory_init.vvp

iverilog -g2012 -Wall -s tb_performance_monitor -o /tmp/tb_performance_monitor.vvp rtl/performance_monitor.v sim/testbenches/tb_performance_monitor.v
vvp /tmp/tb_performance_monitor.vvp
```

The recorded unit-test evidence covers block read, word write, read-after-write, five-cycle latency, file-based initialization, counter reset, hit/miss counting, invalid event rejection and the counter invariant. The full regression is run using `bash sim/run_krishna_tests.sh`.
