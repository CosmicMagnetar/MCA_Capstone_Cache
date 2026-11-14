# Synthesis results

Run `bash synth/run_synthesis.sh`. It needs yosys, plus nextpnr-ecp5 for the timing step. If there's no native nextpnr-ecp5, `pip install yowasp-nextpnr-ecp5` and run with `NEXTPNR=yowasp-nextpnr-ecp5`. The numbers below come from Yosys 0.71 and nextpnr-ecp5 (YoWASP build), with seed 1.

## Generic gates (cache only)

`cache_generic.ys` synthesises `cache_top` with the main-memory model as a black box, because that model is behavioural and isn't meant to become hardware. Full report: `reports/generic_stat.txt`.

| Item | Count |
|---|---:|
| Total cells | 39,854 |
| Flip-flops | 10,136 |
| of which data array (256 × 32 bit) | 8,192 |
| of which tag array (64 × 22 bit) | 1,408 |
| of which valid bits | 64 |
| of which controller, counters and registers | 472 |
| 2-input muxes | 12,710 |

The storage dominates. The data array reads a whole 4-word block in one cycle for the refill and write paths, so Yosys keeps it in flip-flops rather than a single-port RAM.

## Lattice ECP5-85F (CABGA756)

`cache_ecp5.ys`, then nextpnr-ecp5 with a 100 MHz target. `MEM_WORDS` is set to 64 for this run so the behavioural memory turns into a small stand-in. The cache itself is unchanged. Reports: `reports/ecp5_stat.txt` and `reports/ecp5_pnr.log`.

| Resource | Used | Available | % |
|---|---:|---:|---:|
| LUT4 (TRELLIS_COMB) | 18,851 | 83,640 | 22% |
| Flip-flops (TRELLIS_FF) | 10,978 | 83,640 | 13% |
| Block RAM (DP16KD) | 1 | 208 | <1% |
| I/O | 201 | 365 | 55% |

**Post-route maximum frequency: 61.1 MHz** (period 16.4 ns). The 100 MHz target is not met.

Critical path: tag RAM read, then the 22-bit tag compare, then the controller next-state logic, then the write enable into the memory stand-in. The tag array is the only structure that mapped to block RAM, so its 5.8 ns clock-to-out starts the path. Ways to get faster:

- register the hit decision, which costs one cycle of hit latency
- move the data array into four banked 64 × 32 RAMs so it also maps to block RAM
- drop the memory-model path from timing, since a real design would use a separate memory controller

The 201 I/Os are an artefact of exposing the CPU port and all three 32-bit counters as top-level pins. Inside a real SoC these would be internal nets.

## Why ECP5 and not iCE40

`cache_ice40.ys` targets iCE40 HX8K. Synthesis needs 16,467 LUTs and about 8,800 flip-flops (`reports/ice40_stat.txt`), while the HX8K has 7,680 logic cells, so the design does not fit and place-and-route was not attempted. That's why the timing numbers come from ECP5.

## Limits

- Clock-to-clock timing only. I/O delays are not constrained.
- One placement seed.
- The memory model is a stand-in, so the numbers describe the cache subsystem and not a complete memory hierarchy.
