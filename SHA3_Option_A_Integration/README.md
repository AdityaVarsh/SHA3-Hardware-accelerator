# SHA-3 Hardware Accelerator — Option A (Memory-Mapped) Integration

Integrating an iterative SHA3-256 core into a 32-bit, 5-stage RISC-V pipeline using memory-mapped I/O. The CPU drives the accelerator with ordinary `lw` / `sw` instructions — the same instructions it uses for RAM.

Verified in simulation (Icarus Verilog): both the wrapper unit test and the full pipeline-driven program produce the correct SHA3-256("abc") digest.

> **Target digest:**
> `SHA3-256("abc") = 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532`

---

## Table of Contents

1. [What "memory-mapped" means here](#1-what-memory-mapped-means-here)
2. [System block diagram](#2-system-block-diagram)
3. [The two-level address decode](#3-the-two-level-address-decode)
4. [Register map (complete)](#4-register-map-complete)
5. [Byte ordering and the 64-bit-lane / 32-bit-CPU split](#5-byte-ordering-and-the-64-bit-lane--32-bit-cpu-split)
6. [Inside sha3\_mmio: the three pieces](#6-inside-sha3_mmio-the-three-pieces)
7. [The completion problem and why polling solves it](#7-the-completion-problem-and-why-polling-solves-it)
8. [End-to-end data flow, cycle by cycle](#8-end-to-end-data-flow-cycle-by-cycle)
9. [File-by-file description](#9-file-by-file-description)
10. [The demo program (full assembly listing)](#10-the-demo-program-full-assembly-listing)
11. [How to build and run](#11-how-to-build-and-run)
12. [Expected output](#12-expected-output)
13. [Porting to real hardware (FPGA)](#13-porting-to-real-hardware-fpga)
14. [Known limitations](#14-known-limitations)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. What "memory-mapped" means here

A CPU has one address space. Most of it points at RAM, but some address ranges can point at peripherals instead. The CPU does not know the difference — it just issues loads and stores, and the *address* decides where the access physically goes.

In Option A we reserve a **256-byte window** of the address space for the SHA-3 accelerator. A store (`sw`) into that window writes one of the accelerator's registers; a load (`lw`) from it reads one back. No new instructions, no bus protocol — just the pipeline's existing single-cycle memory interface, split between RAM and the accelerator by a small address decoder.

This is the simplest of the three integration styles:

| Option | Style |
|--------|-------|
| **A** | Memory-mapped *(this document)* |
| B | AXI4-Lite slave + master adapter |
| C | Custom instructions wired into the datapath |

---

## 2. System Block Diagram

```
+-----------------------------------------------------------+
|                    5-stage pipeline (main)                |
|                                                           |
|  IF -> ID -> EX -> MEM -> WB                              |
|                     |                                     |
|                     |  mem_alu (addr), mem_dat2 (wdata),  |
|                     |  mem_read, mem_write                |
|                     v                                     |
|            +------------------+                           |
|            | address decoder  |  sel_accel =              |
|            | (in MEM stage)   |  (addr[31:8]==0x000004)   |
|            +---+----------+---+                           |
|                |          |                               |
|        ~sel    |          |  sel                          |
|                v          v                               |
|         +----------+   +-------------+                    |
|         | Data_Mem |   |  sha3_mmio  |                    |
|         |  (1 KB)  |   |  (wrapper)  |                    |
|         +----+-----+   +------+------+                    |
|              |                |                           |
|    ram_rdata |                | accel_rdata               |
|              +-----> mux <----+                           |
|                       |                                   |
|                       v  mem_memval -> MEM/WB             |
+-----------------------------------------------------------+
                         |
                         v   (inside sha3_mmio)
               +---------------------+
               | register file + FSM |---> sha3_top (the core)
               +---------------------+
```

---

## 3. The Two-Level Address Decode

A full address does two jobs — think of it as **"which device"** + **"which register inside that device."**

```
full address = 0x 0000 04 10
                  \________/  \/
                   upper bits  lower 8 bits
                   "device"    "register offset"
```

**Level 1** (in `main`, MEM stage):
```verilog
sel_accel = (mem_alu[31:8] == 24'h000004);
```
- Addresses `0x000..0x3FF` → `Data_Mem` (existing 1 KB RAM)
- Addresses `0x400..0x4FF` → `sha3_mmio` (accelerator window)

**Level 2** (inside `sha3_mmio`):
```verilog
off = addr[7:0];   // lower 8 bits pick the register
```

The read value is muxed back according to the same select:
```verilog
mem_memval = sel_accel ? accel_rdata : ram_rdata;
```

Both `Data_Mem` and `sha3_mmio` present read data combinationally, so the mux behaves exactly like the original single-cycle memory the pipeline expects.

---

## 4. Register Map (Complete)

Base address of the accelerator window: **`0x400`**. All registers are 32 bits. Offsets are relative to the base.

| Offset | Name | Access | Meaning |
|--------|------|--------|---------|
| `0x00` | `DATA0_LO` | W | Message lane 0, bits [31:0] |
| `0x04` | `DATA0_HI` | W | Message lane 0, bits [63:32] |
| `0x08` | `DATA1_LO` | W | Message lane 1, bits [31:0] |
| `0x0C` | `DATA1_HI` | W | Message lane 1, bits [63:32] |
| `...` | `...` | `...` | Lanes 0..16 (offsets `0x00..0x87`) |
| `0x80` | `DATA16_LO` | W | Message lane 16, bits [31:0] |
| `0x84` | `DATA16_HI` | W | Message lane 16, bits [63:32] |
| `0x88` | `LANE_COUNT` | W | Number of valid lanes (1..17) |
| `0x8C` | `LAST_BYTECNT` | W | Valid bytes in the final lane (1..8) |
| `0x90` | `START` | W | Write 1 to begin hashing |
| `0x94` | `DONE` | R | 1 = hash complete (sticky) |
| `0xA0` | `HASH0` | R | Digest bits [31:0] |
| `0xA4` | `HASH1` | R | Digest bits [63:32] |
| `0xA8` | `HASH2` | R | Digest bits [95:64] |
| `0xAC` | `HASH3` | R | Digest bits [127:96] |
| `0xB0` | `HASH4` | R | Digest bits [159:128] |
| `0xB4` | `HASH5` | R | Digest bits [191:160] |
| `0xB8` | `HASH6` | R | Digest bits [223:192] |
| `0xBC` | `HASH7` | R | Digest bits [255:224] |

> **Note:** `HASH` and `DONE` registers are written only by the internal FSM. The write decoder has no case entry for those offsets, so a stray store there is silently ignored. For SHA3-256, only `HASH0..HASH3` (256 bits) are used.

---

## 5. Byte Ordering and the 64-bit-lane / 32-bit-CPU Split

The Keccak core works in 64-bit lanes, but the CPU is 32-bit and can only move 32 bits per store. Each lane is therefore written as two halves: **LO then HI**.

The core's padder (`build_lane`) expects each input word MSB-packed, big-endian — i.e. the first message byte sits in the most-significant byte of the 64-bit word. For `"abc"`:

```
'a' = 0x61, 'b' = 0x62, 'c' = 0x63

64-bit word (as the core wants it) = 0x6162630000000000

Split for the 32-bit CPU:
  DATA0_LO (bits [31:0])  = 0x00000000
  DATA0_HI (bits [63:32]) = 0x61626300

LANE_COUNT   = 1
LAST_BYTECNT = 3   (tells the padder where the 0x06 domain/padding byte goes)
```

Internally `sha3_mmio` reassembles the two halves:
```verilog
lane[n] = { DATAn_HI, DATAn_LO };   // {hi, lo} = full 64-bit lane
```

> When in doubt about packing, mirror your existing standalone SHA-3 testbench: it sends `64'h6162630000000000` with `byte_count=3` for `"abc"`.

---

## 6. Inside `sha3_mmio`: The Three Pieces

### (1) Register File
- 17 lanes × 64 bits, plus `lane_count`, `last_bytecnt`, a latched 256-bit hash, and a sticky done bit.
- The CPU writes data/control registers; the FSM writes the hash/done registers. Two writers, cleanly separated.

### (2) Address Decoder (combinational)
- `off = addr[7:0]`
- **Write path:** a `case` on `off` routes `wdata` to the targeted register. Data-lane stores use `off[7:3]` as the lane index and `off[2]` to pick LO (`0`) vs HI (`1`).
- **Read path:** a `case` on `off` returns `done` or a hash word.
- There is intentionally **no write entry** for the hash/done offsets — the hash can never be overwritten by `sw`.

### (3) Control State Machine (sequential)

States: `IDLE → FEED → HASH → DONE → IDLE`

| State | Behavior |
|-------|----------|
| `IDLE` | Wait for a START write (offset `0x90`, data bit 0 = 1) |
| `FEED` | A counter walks `0..lane_count-1`, presenting `lane[counter]` to the core's `msg_in` with `valid_in=1`, one lane per clock. On the last lane it also asserts `is_last` and drives `byte_count=last_bytecnt`. |
| `HASH` | Wait. The core runs its 24 Keccak rounds autonomously; the FSM only watches for `hash_valid`. |
| `DONE` | Capture `hash_out` into the hash registers, set `done_sticky=1`, then return to IDLE (a new START clears done and restarts). |

> **Why FEED?** The CPU dumps all lanes into registers up front (over many `sw`s), but the core wants them one-per-cycle with `valid_in`. FEED is the translator between "all at once" and "one at a time."

> **Why done is STICKY?** The core's `hash_valid` is a single-cycle pulse. If the CPU polled on a different cycle it would miss it. Latching into `done_sticky` lets the CPU poll at its own pace.

---

## 7. The Completion Problem and Why Polling Solves It

The pipeline assumes a load finishes in one cycle (the MEM stage). But a hash takes ~45 cycles (feed + 24 rounds + latency). You therefore **cannot** do:

```asm
sw  START
lw  HASH0        # WRONG: result not ready yet
```

Instead, poll the `DONE` register in a loop:

```asm
sw   START
poll:
  lw   x7, DONE
  beq  x7, x0, poll     # keep reading until DONE != 0
  lw   HASH0..HASH3     # now safe to read
```

Each `lw DONE` is a normal one-cycle load that simply returns `0` until the hash finishes, then `1`. The loop naturally absorbs the long latency **without stalling the pipeline**, so the hazard-detection and forwarding logic remain completely untouched.

> This is the key elegance of Option A: **variable latency handled in software, not hardware.**

---

## 8. End-to-End Data Flow, Cycle by Cycle

1. CPU executes `sw`s that write `DATA0_LO`, `DATA0_HI`, `LANE_COUNT`, `LAST_BYTECNT` into the register file. (FSM stays in IDLE.)
2. CPU executes `sw START=1`. FSM: `IDLE → FEED`.
3. FEED presents `lane[0]` with `valid_in=1`, `is_last=1`, `byte_count=3`. The core's `input_register → padder` build the 1088-bit block.
4. `padder` asserts `padd_done`; `state_formation` XORs the block into the (zero) state; `keccak_f` starts. FSM: `FEED → HASH`.
5. `keccak_f` runs 24 rounds (~24 cycles). FSM waits in HASH.
6. `keccak_f` asserts `done`; `sha3_top` byte-reverses each lane and pulses `hash_valid` with the 256-bit `hash_out`.
7. FSM captures `hash_out → hash registers`, sets `done_sticky=1`. FSM: `HASH → DONE → IDLE`.
8. Meanwhile the CPU has been looping `lw DONE; beq`. It now reads `1`.
9. CPU reads `HASH0..HASH3` and (in the demo) stores them to RAM.

---

## 9. File-by-File Description

### Integration (new / modified)

| File | Description |
|------|-------------|
| `sha3_mmio.v` | The memory-mapped wrapper. Register file + address decoder + FSM. Instantiates `sha3_top`. **Heart of Option A.** |
| `Main_Module_integrated.v` | Top-level `main` with MEM-stage address decoder spliced in and `sha3_mmio` alongside `Data_Mem`. Uses `` `include `` for all sub-modules (suitable for Vivado/Quartus). |
| `Main_Module_flat.v` | Identical logic with `` `include `` lines removed, for Icarus Verilog where every source file is listed on the command line. |

### Verification

| File | Description |
|------|-------------|
| `tb_sha3_mmio.v` | Unit test. Drives `sha3_mmio`'s memory interface directly and checks SHA3-256("abc"). Fast, no CPU needed. |
| `tb_integrated.v` | Full system test. Runs the entire pipeline executing the demo program, then checks the digest stored to RAM. |
| `assemble.py` | Hand-assembler that emits the demo program as `i_mem` byte initializers. |
| `Instr_Mem_demo.v` | Instruction memory preloaded with the assembled demo program. |
| `Data_Mem_demo.v` | Data memory seeded with the constants the program needs at reset. |

### Unchanged Pipeline Modules

`ALU.v`, `ALU_Control.v`, `Control_Unit.v`, `Ex_Mem.v`, `Forwarding_Unit.v`, `Hazard_Detection_Unit.v`, `IdEx.v`, `IfId.v`, `Imm_Gen.v`, `MemWb.v`, `PC.v`, `Reg_File.v`

### SHA-3 Core (unchanged)

`TOp_module.v` (`sha3_top`), `input_register.v`, `padder_unit.v`, `state_formation.v`, `keccak_f.v`, `keccak_round.v`, `theta.v`, `rho.v`, `pi.v`, `chi.v`, `iota.v`

---

## 10. The Demo Program (Full Assembly Listing)

**Registers seeded in RAM at reset (`Data_Mem_demo.v`):**

| Address | Value | Meaning |
|---------|-------|---------|
| `MEM[0x00]` | `0x00000400` | Accelerator base address |
| `MEM[0x04]` | `0x00000000` | Message low half |
| `MEM[0x08]` | `0x61626300` | Message high half (`"abc"`) |
| `MEM[0x0C]` | `0x00000001` | Constant 1 |
| `MEM[0x10]` | `0x00000003` | Byte count (3) |

**Program (assembled into `Instr_Mem_demo.v`):**

```asm
; ---- load constants ----
lw   x1, 0x00(x0)    ; x1 = 0x400   accelerator base
lw   x2, 0x04(x0)    ; x2 = msg lo
lw   x3, 0x08(x0)    ; x3 = msg hi
lw   x4, 0x0C(x0)    ; x4 = 1
lw   x6, 0x10(x0)    ; x6 = 3

; ---- load message lane 0 ----
sw   x2, 0x00(x1)    ; DATA0_LO = msg lo
sw   x3, 0x04(x1)    ; DATA0_HI = msg hi

; ---- configure ----
sw   x4, 0x88(x1)    ; LANE_COUNT   = 1
sw   x6, 0x8C(x1)    ; LAST_BYTECNT = 3

; ---- start ----
sw   x4, 0x90(x1)    ; START = 1

; ---- poll until done ----
poll:
lw   x7, 0x94(x1)    ; x7 = DONE
beq  x7, x0, poll    ; loop while DONE == 0

; ---- read digest ----
lw   x8,  0xA0(x1)
lw   x9,  0xA4(x1)
lw   x10, 0xA8(x1)
lw   x11, 0xAC(x1)
lw   x12, 0xB0(x1)
lw   x13, 0xB4(x1)
lw   x14, 0xB8(x1)
lw   x15, 0xBC(x1)

; ---- store digest to RAM 0x20..0x3F for inspection ----
sw   x8,  0x20(x0)
sw   x9,  0x24(x0)
sw   x10, 0x28(x0)
sw   x11, 0x2C(x0)
sw   x12, 0x30(x0)
sw   x13, 0x34(x0)
sw   x14, 0x38(x0)
sw   x15, 0x3C(x0)

; ---- halt ----
beq  x0, x0, 0       ; spin forever
```

> To change the program, edit `assemble.py` and re-run it; it regenerates the `i_mem` initializer block.

---

## 11. How to Build and Run

Requires Icarus Verilog. On Ubuntu:
```bash
sudo apt install iverilog
```

### (a) Wrapper unit test — quickest sanity check

```bash
iverilog -g2012 -o tb_mmio.out \
  tb_sha3_mmio.v sha3_mmio.v TOp_module.v input_register.v \
  padder_unit.v state_formation.v keccak_f.v keccak_round.v \
  theta.v rho.v pi.v chi.v iota.v
vvp tb_mmio.out
```

### (b) Full pipeline, end-to-end

```bash
iverilog -g2012 -o tb_int.out \
  tb_integrated.v Main_Module_flat.v \
  Instr_Mem_demo.v Data_Mem_demo.v \
  ALU.v ALU_Control.v Control_Unit.v Ex_Mem.v Forwarding_Unit.v \
  Hazard_Detection_Unit.v IdEx.v IfId.v Imm_Gen.v MemWb.v PC.v \
  Reg_File.v sha3_mmio.v TOp_module.v input_register.v padder_unit.v \
  state_formation.v keccak_f.v keccak_round.v theta.v rho.v pi.v \
  chi.v iota.v
vvp tb_int.out
```

> **Note:** Use `Main_Module_flat.v` with iverilog (no includes). Use `Main_Module_integrated.v` in Vivado/Quartus where `` `include `` is resolved. Do **not** pass both main files to the same compile.

---

## 12. Expected Output

### (a) Wrapper unit test

```
Hash completed after 17 polls
=== SHA3-256("abc") via memory-mapped accelerator ===
Got:      3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
Expected: 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
PASS
```

### (b) Full pipeline

```
=== End-to-end: pipeline-driven SHA3-256("abc") ===
Digest in RAM: 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
Expected:      3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
PASS
```

---

## 13. Porting to Real Hardware (FPGA)

- **Resources:** The full iterative SHA-3 core is ~6,100 flip-flops, which **exceeds** the iCE40UP5K (5,280 FFs). It fits comfortably on XC7Z020 (Zedboard) or an Arty A7. Treat Option A on the small board as a simulation exercise.

- **Real memory:** Replace the behavioral `Data_Mem` with the appropriate technology memory (block RAM). The address decoder logic is unchanged.

- **Address window:** Keep the accelerator window outside your real RAM region. The decoder constant (`mem_alu[31:8]==0x000004`) can be set to any page you like; just keep RAM and the accelerator non-overlapping.

- **Clocking:** The wrapper and core are fully synchronous to the pipeline clock. No clock-domain crossing is involved in Option A.

- **Vivado flow:** Use `Main_Module_integrated.v` (it `` `include ``s the sub-modules), or add all `.v` files to the project and use `Main_Module_flat.v`. Provide an XDC with your clock + reset pins. The standalone SHA-3 timing already met a 25 MHz constraint with large positive slack, so the wrapper additions (a register file + small FSM) are not a timing concern.

---

## 14. Known Limitations

- **Single block only.** The current `sha3_top` hardwires `state_formation` with `use_feedback=0`, so only messages that fit in one 1088-bit block (≤ 17 lanes, e.g. short strings like `"abc"`) are supported. Multi-block messages require wiring the feedback path (post-round state XORed into the next block). This is the single biggest upgrade and benefits all three integration options identically.

- **No ADDI in the CPU.** The demo loads constants from seeded RAM because this pipeline implements only R/I(load)/S/B types. Adding ADDI would let the program build immediates itself and drop the seeded-memory dependency.

- **32-bit data path.** Each 64-bit lane takes two stores. This is inherent to a 32-bit CPU and matches the register map.

- **Polling, not interrupts.** Completion is discovered by polling DONE. An interrupt-driven variant would assert an IRQ on `hash_valid` and let the CPU do other work in the meantime — not implemented here.

---

## 15. Troubleshooting

**Digest is all zeros / DONE never becomes 1**
- Check that START actually reached offset `0x90` with data bit 0 set.
- Confirm `sel_accel` matches your base address; a store landing in RAM instead of the accelerator will silently do nothing useful.

**Digest is wrong but non-zero**
- Almost always a byte packing issue. Re-check [Section 5](#5-byte-ordering-and-the-64-bit-lane--32-bit-cpu-split). `"abc"` must arrive as `DATA0_LO=0x00000000`, `DATA0_HI=0x61626300`, `LAST_BYTECNT=3`. Little-endian packing will produce a different (wrong) hash.
- Confirm `LANE_COUNT` matches the number of lanes you actually wrote.

**Result reads back as the DONE value or stale data**
- Only read `HASH0..HASH3` **after** `DONE==1`. Reading earlier returns the not-yet-latched (old/zero) hash registers.

**Simulation hangs / never finishes**
- The poll loop spins forever if DONE never sets. Add a cycle cap in the testbench (`tb_integrated.v` already runs a fixed number of cycles).

**Compile error: "module already defined"**
- You passed both `Main_Module_flat.v` and `Main_Module_integrated.v`, or both a demo memory and the original `Data_Mem`/`Instr_Mem`. Pass exactly one of each.
