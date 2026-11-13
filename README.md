# Direct-Mapped Cache Controller — Phase I

A 32-bit, 1 KiB direct-mapped cache prototype with 64 lines, 16-byte blocks, four 32-bit words per line, write-through and write-allocate.

## Design documents

- [Architecture](docs/architecture.md)
- [RTL interface contract](docs/rtl_interface_contract.md)
- [Krishna's implementation notes](docs/krishna_implementation.md)
- [Aditya's implementation notes](docs/aditya_implementation.md)
- [Saumya's memory and performance-monitor notes](docs/saumya_implementation.md)
- [IEEE Phase I report source](report/phase1_report.tex)

## Modules and owners

| Module | Owner | File |
|---|---|---|
| Address decoder | Aditya | `rtl/address_decoder.v` |
| Cache storage | Rachit | `rtl/cache_storage.v` |
| Main memory model | Saumya | `memory/main_memory_model.v` |
| Performance monitor | Saumya | `rtl/performance_monitor.v` |
| Cache controller | Krishna | `rtl/cache_controller.v` |
| Integrated cache top | Krishna | `rtl/cache_top.v` |
| Integrated system verification | Nishtha | `sim/testbenches/tb_cache_top.v` |

## Simulation

Install Icarus Verilog (`iverilog` and `vvp`) and run the full Phase I regression from the repository root:

```sh
bash sim/run_krishna_tests.sh
```

The runner executes the address-decoder, cache-storage, controller, main-memory, memory-initialization and performance-monitor unit testbenches, then invokes `sim/run_cache_top_verification.sh` to run the actual integrated `cache_top` test and generate eight isolated VCD scenarios.

The committed integrated verification report records 39 checks passed with 0 failures for the combined Issue #7 and Issue #8 sequence, with 26 processor accesses, 13 hits and 13 misses. The decoder test log records 374 checks and 0 errors. See [integrated verification evidence](sim/waveforms/verification_report.md) for scenario-level results and waveform names.

## Processor request protocol

`cpu_req` marks one request. The controller captures the request only while idle. `cpu_ready` is a one-cycle completion pulse; read data is valid with that pulse. Requests asserted while busy are not queued. Deassert `cpu_req` for at least one rising edge between transactions.

## Cache configuration

- 32-bit byte address
- 1 KiB direct-mapped cache
- 64 lines, 16-byte blocks
- Four 32-bit words per line
- Tag/index/offset fields: 22/6/4 bits
- Word-aligned requests only
- Write-through and write-allocate
