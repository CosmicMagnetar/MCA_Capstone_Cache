# Direct-Mapped Cache Controller — Phase I

A 32-bit, 1 KiB direct-mapped cache prototype with 64 lines, 16-byte blocks, four 32-bit words per line, write-through and write-allocate.

## Design documents

- [Architecture](docs/architecture.md)
- [RTL interface contract](docs/rtl_interface_contract.md)
- [Krishna's implementation notes](docs/krishna_implementation.md)
- [Aditya's implementation notes](docs/aditya_implementation.md)

## Modules and owners

| Module | Owner | File |
|---|---|---|
| Address decoder | Aditya | `rtl/address_decoder.v` |
| Cache storage | Rachit | `rtl/cache_storage.v` |
| Main memory model | Saumya | `memory/main_memory_model.v` |
| Performance monitor | Saumya | `rtl/performance_monitor.v` |
| Cache controller | Krishna | `rtl/cache_controller.v` |
| Integrated cache top | Krishna | `rtl/cache_top.v` |

The decoder and storage source files remain with their respective task owners. Their exact required interfaces are in the interface contract.

## Simulation

Install Icarus Verilog and run:

```sh
bash sim/run_krishna_tests.sh
```

The controller-level bench models decoder/storage behaviour and delayed main memory. Memory and performance-monitor unit benches are run separately. The script also elaborates the integrated `cache_top` from its current dependencies.

## Processor request protocol

`cpu_req` marks one request. The controller captures the request only while idle. `cpu_ready` is a one-cycle completion pulse; read data is valid with that pulse. Requests asserted while busy are not queued. Deassert `cpu_req` for at least one rising edge between transactions.

## Integrated cache system testbench

`sim/testbenches/tb_cache_top.v` tests the real `cache_top` with deterministic
initialization of the integrated main-memory array. It covers a cold miss,
repeated and same-block hits, same-index tag replacement and eviction, a write
hit, a write miss with allocation, write-through consistency, and readback.
The testbench also checks the completion counters after each transaction.

Run from the repository root with Icarus Verilog:

```sh
iverilog -g2012 -Wall -s tb_cache_top -o /tmp/tb_cache_top.vvp \
  rtl/address_decoder.v rtl/cache_storage.v rtl/cache_controller.v \
  rtl/performance_monitor.v memory/main_memory_model.v rtl/cache_top.v \
  sim/testbenches/tb_cache_top.v
vvp /tmp/tb_cache_top.vvp
```

The Issue #7 baseline covers the nine read/write transactions, counter checks,
and write consistency checks. The combined Issue #7 and Issue #8 results are
recorded in `sim/waveforms/verification_report.md`.

## Cache edge-case verification and waveform evidence

The same integrated testbench also covers reset invalidation, protocol-legal
consecutive requests, a request presented while the controller is busy,
four-word refill ordering, stale-data prevention on replacement, write-through
visibility, and preservation of other words in written blocks. Run the full
Issue #7 and Issue #8 suites and generate scenario VCDs with:

```sh
bash sim/run_cache_top_verification.sh
```

The runner compiles the same RTL dependencies listed above, runs the complete
test sequence, then runs isolated scenarios for named waveforms under
`sim/waveforms/`. The full sequence currently passes 39 checks with 26 accesses,
13 hits, and 13 misses. Per-scenario outcomes and waveform names are recorded in
`sim/waveforms/verification_report.md`.
