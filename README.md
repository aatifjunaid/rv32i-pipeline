# 5-Stage Pipelined RISC-V (RV32I) Core

A small processor written in Verilog, with a testbench and SystemVerilog assertions (SVA).
It runs 8 instructions: **ADD, SUB, AND, OR, ADDI, LW, SW, BEQ**.
(No caches, no branch prediction, no CSRs. JAL can be added later.)

## How the pipeline works
Each instruction goes through 5 stages, and a new one starts every clock cycle:

    IF (fetch) -> ID (decode, read regs) -> EX (ALU, branch) -> MEM (data memory) -> WB (write reg)

Three problems come up when instructions overlap, and the core handles each one:

| Problem | Example | Fix in this core |
|---|---|---|
| Data hazard | `addi x1..` then `add x3, x1, ..` | **Forwarding** from EX/MEM and MEM/WB into the ALU |
| Load-use hazard | `lw x2..` then `add x3, x2, ..` | **1-cycle stall** (freeze PC and IF/ID, insert a bubble) |
| Branch | `beq` taken | Assume not-taken; if taken, **flush 2 instructions** |

Signal names start with their stage (`id_rd`, `ex_rd`, `mem_rd`, `wb_rd`), so waveforms are easy to read.

## What is in the folder

| File | What it is |
|---|---|
| `rtl/sc_core.v` | Single-cycle version. Used as the **reference model** ("correct answer"). |
| `rtl/pipe_core.v` | The 5-stage pipelined core (the actual design). |
| `tb/tb_top.sv` | Testbench. Runs both cores on the same program and compares them. |
| `tb/pipe_sva.sv` | 4 assertions that watch the pipeline while it runs. |
| `programs/*.s` | Test programs in assembly. |
| `programs/*.exp` | The expected final register/memory values for each program. |
| `sim/*.hex` | The same programs as machine code. This is what the CPU loads. |
| `tools/asm.py` | Converts a `.s` file into a `.hex` file. |
| `Makefile` | Shortcuts for running everything. |

## The 5 test programs

| Test | What it checks |
|---|---|
| `t1_nohazard` | Basic instructions, with NOPs between them |
| `t2_forward` | Back-to-back dependent instructions (forwarding) |
| `t3_loaduse` | A load followed straight away by its user (stall) |
| `t4_branch` | Taken and not-taken branches (flush) |
| `t5_sum` | A loop that adds 1 to 10 and stores 55 |

## The 4 assertions
1. Register `x0` is always 0.
2. The pipeline stalls **only** on a load-use hazard.
3. The pipeline flushes **only** on a taken branch.
4. After a stall or flush, a bubble (no-op) enters the EX stage.

## How a test passes
The testbench runs the program for 400 cycles, then checks:
1. Pipeline registers and memory **equal** the single-cycle reference.
2. Both match the `.exp` file (for example `R 1 55` means x1 must be 55).
3. No assertion fired.

It prints `TEST PASS (N checks)` or `TEST FAIL`. A missing `.hex` or `.exp` file also gives FAIL.

## Checking that the tests can catch bugs (bug injection)
`pipe_core.v` has 7 bug switches, all off by default. Add one as a run option and the tests should FAIL:

| Run option | Bug injected |
|---|---|
| `+BUG_NOFWD_MEM` | no EX/MEM forwarding |
| `+BUG_NOFWD_WB` | no MEM/WB forwarding |
| `+BUG_PRIO` | older value wins over newer one |
| `+BUG_NOBYPASS` | no register-file write-through |
| `+BUG_NOSTALL` | load-use stall disabled |
| `+BUG_NOFLUSH` | taken branch does not flush |
| `+BUG_FLUSH1` | flushes 1 instruction instead of 2 |

Example: `+PROG=t3.hex +EXP=t3.exp +BUG_NOSTALL`. Locally, `make mutate` runs every bug on every test.
(These switches exist only in simulation; they are removed when `SYNTHESIS` is defined.)

## Option A: run locally (Verilator 5 or newer)

    make test                        # run all 5 tests
    make run P=t3_loaduse TRACE=1    # run one test, print every cycle (shows STALL / FLUSH)

## Option B: run on EDA Playground (Cadence Xcelium)

1. **design.sv** pane: paste `sc_core.v`, then `pipe_core.v`.
2. **testbench.sv** pane: paste `pipe_sva.sv`, then `tb_top.sv`.
3. Add two extra files with the "+" button, for one test (for example t5_sum):
   `t5_sum.hex` (from `sim/`) and `t5_sum.exp` (from `programs/`).
4. Top module: `tb_top`. Compile options: `-timescale 1ns/1ps`.
5. Run options: `+PROG=t5_sum.hex +EXP=t5_sum.exp` (add `+TRACE` to see every cycle).
6. Click Run and look for `TEST PASS` in the log.

To run another test, swap the `.hex`/`.exp` files and the names in Run options.

## Writing your own test
Write a `.s` file ending with `halt: beq x0, x0, halt`, then run
`python3 tools/asm.py mytest.s mytest.hex`. Write the expected values in a `.exp` file.
You can also use the RARS assembler (Dump Memory, format Hexadecimal Text).

## How it was built
Single-cycle core first, then the pipeline registers, then forwarding, then the load-use stall,
then the branch flush, and last the testbench and assertions.
