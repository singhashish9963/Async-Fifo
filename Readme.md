# Asynchronous FIFO — RTL Design & Verification (Verilog)

A parameterized **asynchronous FIFO** that safely transfers data between two
independent clock domains, together with a **self-checking Verilog testbench**
that verifies it at different clock ratios.

The design follows the classic Gray-code pointer architecture used in
industry for Clock Domain Crossing (CDC).

---

## Table of Contents
1. [Features](#features)
2. [Architecture](#architecture)
3. [Directory Structure](#directory-structure)
4. [Module Description](#module-description)
5. [How It Works](#how-it-works)
6. [Interface](#interface)
7. [Verification](#verification)
8. [Simulation Results](#simulation-results)
9. [How to Run](#how-to-run)
10. [Design Decisions](#design-decisions)
11. [Limitations and Future Work](#limitations-and-future-work)

---

## Features

- Independent **write clock** and **read clock** (any frequency ratio)
- Parameterized **data width** and **depth** (`DEPTH = 2^ADDR_WIDTH`)
- **Gray-code pointers** + **2-flop synchronizers** for safe CDC
- **Full / Empty** flags using an extra pointer bit
- **Almost-full / Almost-empty** flags with configurable thresholds
- **Overflow and underflow protection** (writes when full and reads when empty are ignored)
- **First-word fall-through** read (`rdata` always shows the oldest entry)
- Separate asynchronous reset for each clock domain
- Self-checking testbench with a **reference model**, **CDC checkers** and **coverage counters**

---

## Architecture

```
         WRITE CLOCK DOMAIN                                  READ CLOCK DOMAIN
                                       ┌──────────┐
   winc ──►┌──────────────┐  wptr      │ sync_2ff │  rq2_wptr  ┌───────────────┐◄── rinc
           │  wptr_full   │──(Gray)───►│ (2 flops)│───────────►│  rptr_empty   │
  wfull ◄──│              │            └──────────┘            │               │──► rempty
 walmost◄──│ binary+Gray  │            ┌──────────┐            │ binary+Gray   │──► ralmost_empty
  _full    │  pointer     │◄───────────│ sync_2ff │◄──(Gray)───│  pointer      │
           └──────┬───────┘  wq2_rptr  │ (2 flops)│   rptr     └───────┬───────┘
                  │ waddr              └──────────┘                    │ raddr
                  ▼                                                    ▼
   wdata ──►┌─────────────────────────────────────────────────────────────────┐
            │                   fifo_mem  (dual-port RAM)                      │──► rdata
            └─────────────────────────────────────────────────────────────────┘
```

Only **Gray-coded pointers** cross between the domains. Each flag is generated
in its own domain, so it can be used directly by the logic in that domain.

---

## Directory Structure

```
Async-Fifo/
├── rtl/
│   ├── async_fifo.v      # Top level – connects all sub-modules
│   ├── fifo_mem.v        # Dual-port memory
│   ├── sync_2ff.v        # 2-flop synchronizer
│   ├── wptr_full.v       # Write pointer + full / almost-full logic
│   └── rptr_empty.v      # Read pointer + empty / almost-empty logic
├── tb/
│   └── tb_async_fifo.v   # Self-checking testbench
└── Readme.md
```

---

## Module Description

| Module | Clock | Description |
|---|---|---|
| `async_fifo` | both | Top level. Instantiates and connects all blocks. |
| `fifo_mem` | `wclk` | `2^ADDR_WIDTH x DATA_WIDTH` memory. Synchronous write, combinational read. |
| `sync_2ff` | destination | Two flip-flops in series that bring a Gray pointer into the other clock domain. |
| `wptr_full` | `wclk` | Increments the write pointer on accepted writes, converts it to Gray code, and generates `wfull` and `walmost_full`. |
| `rptr_empty` | `rclk` | Increments the read pointer on accepted reads, converts it to Gray code, and generates `rempty` and `ralmost_empty`. |

---

## How It Works

### 1. Why Gray code?
A binary counter can change many bits at once (`0111 → 1000` changes 4 bits).
If the other clock samples it while it is changing, each bit may be captured
differently, giving a completely wrong pointer.

A **Gray code** changes **exactly one bit** per increment, so the synchronized
value is always either the **old** or the **new** pointer, never garbage.

```
binary → Gray :  gray = (bin >> 1) ^ bin
Gray → binary :  bin[i] = XOR of gray[N:i]
```

### 2. Why two flip-flops?
The first flop may become **metastable** when its input changes near the clock
edge. The second flop gives it a full clock period to settle, which makes the
probability of failure (MTBF) extremely small.

### 3. Full and empty detection
Pointers are **`ADDR_WIDTH + 1` bits**. The extra MSB counts how many times the
pointer has wrapped around the memory.

| Condition | Rule (Gray pointers) |
|---|---|
| **Empty** | read pointer **==** synchronized write pointer |
| **Full** | write pointer **==** synchronized read pointer with its **top two bits inverted** |

Example with `ADDR_WIDTH = 4` (16 entries): after 16 writes and 0 reads the
binary pointers are `1_0000` and `0_0000`. Same address, different lap → **full**.

### 4. Pessimistic flags (safe by design)
The pointer from the other domain is always **2+ cycles old**.
- `wfull` may stay high a little longer than needed after a read.
- `rempty` may stay high a little longer than needed after a write.

This can cost a few cycles but can **never** cause overflow or underflow.
The almost-full and almost-empty flags work the same way.

---

## Interface

| Signal | Dir | Domain | Description |
|---|---|---|---|
| `wclk`, `wrst_n` | in | write | Write clock, active-low async reset |
| `winc` | in | write | Write request. Data is written at `posedge wclk` if `!wfull` |
| `wdata[DATA_WIDTH-1:0]` | in | write | Write data |
| `wfull` | out | write | FIFO is full |
| `walmost_full` | out | write | Free slots ≤ `ALMOST_FULL_TH` |
| `rclk`, `rrst_n` | in | read | Read clock, active-low async reset |
| `rinc` | in | read | Read request. Oldest entry is removed at `posedge rclk` if `!rempty` |
| `rdata[DATA_WIDTH-1:0]` | out | read | Oldest entry (valid when `!rempty`) |
| `rempty` | out | read | FIFO is empty |
| `ralmost_empty` | out | read | Entries ≤ `ALMOST_EMPTY_TH` |

| Parameter | Default | Description |
|---|---|---|
| `DATA_WIDTH` | 8 | Width of each entry |
| `ADDR_WIDTH` | 4 | Depth = `2^ADDR_WIDTH` (16). Must be ≥ 2 |
| `ALMOST_FULL_TH` | 2 | Almost-full threshold (free slots) |
| `ALMOST_EMPTY_TH` | 2 | Almost-empty threshold (entries) |

---

## Verification

The testbench (`tb/tb_async_fifo.v`) is **self-checking**. It prints
`TEST PASSED` or `TEST FAILED` at the end, so there's no need to check
waveforms by hand.

```
  ┌───────────────┐   winc/wdata   ┌────────────┐   rinc     ┌───────────────┐
  │ write_items() │──────────────► │ async_fifo │ ◄──────────│ read_items()  │
  │  (wclk)       │                │   (DUT)    │            │  (rclk)       │
  └───────────────┘                └─────┬──────┘            └───────────────┘
          │ accepted writes              │ rdata                   │
          ▼                              ▼                         │
  ┌──────────────────────────────────────────────────┐             │
  │ Reference model (queue): store on write,          │◄───────────┘
  │ compare oldest value on every read                │ accepted reads
  └──────────────────────────────────────────────────┘
```

| Component | What it does |
|---|---|
| **Stimulus tasks** | `write_items(count, max_idle)` writes random data with random gaps and holds `winc` while full, which produces overflow attempts. `read_items(total, read_pct)` reads with a chosen probability, including while empty, which produces underflow attempts. |
| **Reference model** | An array used as a queue. Every accepted write is stored, and every accepted read is compared with the oldest stored value. |
| **CDC checkers** | Gray pointers change **at most 1 bit** per clock. Pointers **do not move** on a write while full or a read while empty. |
| **Coverage counters** | Full, empty, almost-full, almost-empty, overflow attempts, underflow attempts, simultaneous read/write, pointer wrap-arounds. |
| **Timeout** | Reports `TEST FAILED` if the design or test gets stuck. |

Stimulus is driven on the **negative edge** and checked on the **positive edge**,
so the testbench never races with the design.

### Test plan
Each pattern is run at **three clock ratios**:

| Write clock | Read clock | Case |
|---|---|---|
| 10 ns (100 MHz) | 10 ns (100 MHz) | Same frequency |
| 10 ns (100 MHz) | 26 ns (~38 MHz) | Fast writer, slow reader |
| 34 ns (~29 MHz) | 8 ns (125 MHz) | Slow writer, fast reader |

| Pattern | Purpose |
|---|---|
| **A. Fill → overflow → drain → underflow** | Fill completely, keep writing while full, read everything, keep reading while empty |
| **B. Random traffic** | Random gaps on both sides |
| **C. Writer-heavy** | Continuous writes, 30 % reads, so the FIFO is often full |
| **D. Reader-heavy** | Sparse writes, 90 % reads, so the FIFO is often empty |

---

## Simulation Results

Output of the full regression (Icarus Verilog 13):

```
[85000] ---- write clock 10 ns, read clock 10 ns ----
[17610000] ---- write clock 10 ns, read clock 26 ns ----
[53404000] ---- write clock 34 ns, read clock 8 ns ----

==================== TEST SUMMARY ====================
 Writes accepted            : 1860
 Reads checked              : 1860
 Data mismatches            : 0
 CDC check failures         : 0
------------------------------------------------------
 Coverage
   cycles full              : 2556
   cycles empty             : 4886
   cycles almost full       : 3219
   cycles almost empty      : 6448
   overflow attempts        : 2316
   underflow attempts       : 3540
   simultaneous read/write  : 1004
   pointer wrap-arounds     : 116
------------------------------------------------------
 RESULT : *** TEST PASSED ***
======================================================
```

The testbench was also checked against **deliberately broken designs**, and it
reports `TEST FAILED` for:
- a wrong full condition (MSBs not inverted), which deadlocks and is caught by the timeout;
- a read pointer sent in binary instead of Gray, which is caught by the CDC checker and the reference model.

---

## How to Run

### Option 1 — Xilinx Vivado (xsim)
1. **Create Project** → RTL Project → *Do not specify sources at this time*.
2. **Add Sources → Add or create design sources** → add all files in `rtl/`.
3. **Add Sources → Add or create simulation sources** → add `tb/tb_async_fifo.v`.
4. In *Simulation Sources*, right-click `tb_async_fifo` → **Set as Top**.
5. **Run Simulation → Run Behavioral Simulation**, then type `run all` in the Tcl console.
6. The summary appears in the Tcl console. Add `wfull`, `rempty`, `dut/wptr`,
   `dut/rptr` to the waveform to see the pointers move.

### Option 2 — Icarus Verilog + GTKWave
```bash
iverilog -g2005 -Wall -o fifo_sim rtl/*.v tb/tb_async_fifo.v
vvp fifo_sim
gtkwave tb_async_fifo.vcd
```

### Option 3 — EDA Playground
Paste the `rtl/` files into **design.sv** and `tb/tb_async_fifo.v` into
**testbench.sv**. Select *Icarus Verilog* or any other simulator and click **Run**.

---

## Design Decisions

| Decision | Reason |
|---|---|
| Gray-code pointers | Only one bit changes per increment, so they are safe to synchronize |
| 2-flop synchronizers | Standard metastability protection |
| `ADDR_WIDTH + 1` bit pointers | Distinguish full from empty without a counter |
| Flags registered in their own domain | Glitch-free and usable directly by local logic |
| Combinational read (FWFT) | Data is available without an extra read latency cycle |
| Separate resets per domain | Each side can be reset by its own reset tree |

---

## Limitations and Future Work

- Depth must be a power of two (needed by the Gray-code scheme).
- Almost flags are conservative because of synchronization delay.
- Possible extensions:
  - registered read output for better timing on FPGA block RAM;
  - a 3-flop synchronizer option for very high clock frequencies;
  - a SystemVerilog/UVM testbench with assertions and functional coverage.

---

## References
- Clifford E. Cummings, *Simulation and Synthesis Techniques for Asynchronous FIFO Design*, SNUG 2002.
- Clifford E. Cummings, *Clock Domain Crossing (CDC) Design & Verification Techniques Using SystemVerilog*, SNUG 2008.

---

**Author:** Ashish Singh — B.Tech ECE, MNNIT Allahabad
