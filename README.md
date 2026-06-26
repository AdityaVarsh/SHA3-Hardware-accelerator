# SHA-3 Hardware Accelerator × 5-Stage RISC-V Pipeline

Integrating an iterative **SHA3-256** hardware accelerator into a 32-bit, 5-stage **RISC-V** pipeline — demonstrating **three** different ways to connect an accelerator to a processor.

| Option | Style | Character |
|:------:|-------|-----------|
| **A** | Memory-mapped I/O | simplest |
| **B** | AXI4-Lite slave + master | most portable / faithful to the paper |
| **C** | Custom instructions | tightest coupling / lowest overhead |

All three wrap the **same** SHA-3 core and the **same** control logic — only the CPU-facing interface differs. Every option is verified in simulation and produces the correct digest:

```
SHA3-256("abc") = 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
```

---

## Table of Contents

1. [Background and motivation](#1-background-and-motivation)
2. [What this project contains](#2-what-this-project-contains)
3. [The two building blocks](#3-the-two-building-blocks)
4. [The three integration options at a glance](#4-the-three-integration-options-at-a-glance)
5. [Which option to use when](#5-which-option-to-use-when)
6. [The common design pattern](#6-the-common-design-pattern)
7. [Repository layout](#7-repository-layout)
8. [Quick start](#8-quick-start)
9. [Results summary](#9-results-summary)
10. [The one limitation that affects all three](#10-the-one-limitation-that-affects-all-three)
11. [Where to read more](#11-where-to-read-more)
12. [Glossary](#12-glossary)
13. [Credits / references](#13-credits--references)

---

## 1. Background and motivation

SHA-3 (Keccak, FIPS-202) is a cryptographic hash function: it turns any input message into a fixed-size, irreversible "fingerprint" (a 256-bit digest for SHA3-256). It is used for password storage, file integrity, digital signatures, and blockchains.

Software can compute SHA-3, but a general-purpose CPU does it one step at a time. A hardware accelerator computes an entire Keccak round in a single clock cycle using dedicated logic, which is dramatically faster — valuable for high-throughput security such as network line-rate hashing or crypto mining.

But an accelerator is useless on its own; a processor must be able to send it data and read back the result. **This project is about that connection** — three standard techniques for wiring a hardware accelerator to a CPU, built and verified against a real teaching pipeline.

> The work follows the structure of A. Raveendran, S. B V, D. Selvakumar, *"Micro-Architecture Design and Analysis of AXI Enabled SHA-3 Hardware Accelerator for a RISC-V Based SoC,"* IEEE VLSI SATA 2025. Section IV of that paper is the AXI wrapper (**Option B**); Section V is SoC integration; the paper's future-work ISA extension corresponds to **Option C**.

---

## 2. What this project contains

- An iterative **SHA3-256 core** (your existing design), unchanged.
- A 32-bit, 5-stage **RISC-V pipeline** (your existing design) with forwarding and hazard detection, unchanged except where an option requires it.
- **Three self-contained integrations**, each in its own folder, each with:
  - the wrapper/coprocessor RTL for that style
  - any modified pipeline modules
  - a testbench (and, for A and C, a hand-assembled demo program)
  - a detailed README
- This top-level overview.

Each option folder builds and runs **independently** with Icarus Verilog.

---

## 3. The two building blocks

### (a) The SHA-3 core — `sha3_top` and submodules

Iterative Keccak-f: one round per clock, 24 rounds per block. Pipeline of sub-blocks:

```
input_register → padder → state_formation → keccak_f
keccak_f = keccak_round (θ → ρ → π → χ → ι) × 24
```

**Interface:**

| Direction | Signals |
|-----------|---------|
| inputs | `clk`, `rst_n`, `msg_in[63:0]`, `valid_in`, `is_last`, `byte_count[3:0]` |
| outputs | `hash_out[255:0]`, `hash_valid` (one-cycle pulse) |

The core absorbs 64-bit words one per cycle, then runs 24 rounds, then pulses `hash_valid` with the digest (~45 cycles total for a single block).

### (b) The RISC-V pipeline — `main` and submodules

Classic 5-stage: **IF → ID → EX → MEM → WB**, 32-bit. Implements R-type (`add`/`sub`/…), I-type loads (`lw`), S-type stores (`sw`), and B-type branches (`beq`). Includes a forwarding unit and a load-use hazard-detection unit. Data memory is a behavioral 1 KB byte array; reads are combinational, writes are clocked.

> **Note:** this CPU has no `ADDI` (the I-type opcode is wired to loads), so the demo programs load constants from pre-seeded RAM rather than synthesizing them.

---

## 4. The three integration options at a glance

### Option A — Memory-mapped I/O

> **Idea:** reserve a 256-byte address window; `sw`/`lw` to it write/read the accelerator's registers. An address decoder in the MEM stage routes between RAM and the accelerator.

- **CPU sees:** ordinary loads and stores.
- **Surgery:** one address decoder + one read mux in `main`. Pipeline otherwise untouched.
- **Verified:** wrapper unit test **and** a full program running on the real pipeline.
- **Folder:** `SHA3_Option_A_Integration/` — key file `sha3_mmio.v`

### Option B — AXI4-Lite

> **Idea:** wrap the core as a standard AXI4-Lite slave (five channels with VALID/READY handshakes). A master adapter converts a CPU `lw`/`sw` into an AXI transaction and stalls the CPU until it completes.

- **CPU sees:** loads/stores that take a few cycles (a stall).
- **Surgery:** AXI slave + master adapter; a pipeline **stall path** is required to hold an access until the AXI transaction finishes.
- **Verified:** AXI master BFM against the slave, **and** the master+slave pair driven as a stalled CPU would.
- **Folder:** `SHA3_Option_B_AXI/` — key files `axi_sha3.v`, `axi_master_mem.v`

### Option C — Custom instructions

> **Idea:** add CUSTOM-0 instructions (`SHA.FEED`/`CFG`/`START`/`POLL`/`READ`). A coprocessor in the EX stage takes operands from registers and returns results on the writeback path. No addresses, no bus.

- **CPU sees:** new instructions, like `ADD`/`SUB`.
- **Surgery:** decode the new opcode (`Control_Unit`), widen the control bus (`IdEx`), instantiate the coprocessor, mux its result onto the ALU path. Hazard/forwarding/branch logic untouched.
- **Verified:** full program running on the real pipeline.
- **Folder:** `SHA3_Option_C_CustomInstr/` — key file `sha3_cop.v`

---

## 5. Which option to use when

**Use Option A when:**
- you want the simplest possible integration with a soft CPU,
- your CPU already has a simple memory bus,
- this is a course deliverable and clarity matters most.

*It is the cleanest demonstration of the memory-mapped principle.*

**Use Option B when:**
- you are targeting a Zynq / SoC with a standard AXI interconnect (the ARM PS becomes the master; you only need the slave),
- you want the accelerator to be reusable as a drop-in AXI IP,
- you want to follow the reference paper faithfully.

*Cost: a pipeline stall path if your own soft CPU is the master.*

**Use Option C when:**
- you want the lowest per-call overhead (no address/bus cycles),
- tight coupling to one specific CPU is acceptable,
- you are exploring ISA extension (the paper's future work).

*Cost: the accelerator is welded to this CPU's instruction set and cannot be reused on a different processor without re-doing the decode.*

### Quick comparison

| | **A** (mem-mapped) | **B** (AXI4-Lite) | **C** (custom instr) |
|---|:---:|:---:|:---:|
| CPU interface | `lw`/`sw` + address | `lw`/`sw` → AXI | new opcodes |
| Addresses used | yes | yes | none |
| Pipeline surgery | minimal | stall path | control bus + mux |
| Portability | needs mem bus | any AXI fabric | tied to this ISA |
| Per-call overhead | moderate | highest | lowest |
| Reusable as IP | somewhat | **yes (best)** | no |

---

## 6. The common design pattern

Despite different front-ends, all three wrappers share the same internals:

1. **A register file** holding the message (17 lanes × 64 bits, written as 32-bit halves), plus `lane_count`, `byte_count`, a latched 256-bit digest, and a sticky *done* bit.

2. **A small FSM:** `IDLE → FEED → HASH → DONE`.
   - **FEED** replays the stored lanes into the core one-per-cycle (`valid_in`), because the CPU loaded them all up front but the core wants them sequentially.
   - **HASH** waits out the 24 rounds (the core runs them independently).
   - **DONE** latches the digest and sets the sticky done bit.

3. **Polling for completion.** The hash takes ~45 cycles, far longer than one CPU access, so software polls the done bit in a loop and only reads the digest once `done == 1`. This hides the latency *without* stalling the pipeline. *(Option B's stall is for the AXI bus timing, not the hash.)*

4. **Secure-by-omission result registers.** The write decoder has no entry for the digest/done registers, so the CPU can read them but never overwrite them.

> Understanding this shared pattern once makes all three options easy to read.

---

## 7. Repository layout

```
(top level)
├── README_PROJECT.md              ← this file
├── README_OptionA_detailed.txt    ← deep dive, Option A
├── README_OptionB_detailed.txt    ← deep dive, Option B
├── README_OptionC_detailed.txt    ← deep dive, Option C
│
├── SHA3_Option_A_Integration/
│   ├── README.md
│   ├── sha3_mmio.v                 memory-mapped wrapper
│   ├── Main_Module_integrated.v    pipeline top (with `include)
│   ├── Main_Module_flat.v          pipeline top (for iverilog)
│   ├── tb_sha3_mmio.v              wrapper unit test
│   ├── tb_integrated.v             full end-to-end test
│   ├── assemble.py                 demo-program assembler
│   ├── Instr_Mem_demo.v / Data_Mem_demo.v
│   └── (+ unchanged pipeline and SHA-3 source files)
│
├── SHA3_Option_B_AXI/
│   ├── README.md
│   ├── axi_sha3.v                  AXI4-Lite slave wrapper
│   ├── axi_master_mem.v            MEM-stage AXI master adapter
│   ├── tb_axi_sha3.v               AXI master BFM test
│   ├── tb_axi_pair.v               master+slave full-path test
│   └── (+ unchanged SHA-3 source files)
│
└── SHA3_Option_C_CustomInstr/
    ├── README.md
    ├── sha3_cop.v                  EX-stage coprocessor
    ├── Control_Unit_cop.v          decode for CUSTOM-0
    ├── IdEx_cop.v                  widened control bus
    ├── Main_Module_cop.v           pipeline top with coprocessor + mux
    ├── tb_cop.v                    full end-to-end test
    ├── assemble_cop.py             demo-program assembler
    ├── Instr_Mem_cop.v / Data_Mem_cop.v
    └── (+ unchanged pipeline and SHA-3 source files)
```

Each option folder is **self-contained**: it has every `.v` file needed to build, so you can simulate any one option without the others.

---

## 8. Quick start

Requires Icarus Verilog. On Ubuntu: `sudo apt install iverilog`

### Option A — full pipeline end-to-end

```bash
cd SHA3_Option_A_Integration
iverilog -g2012 -o a.out tb_integrated.v Main_Module_flat.v \
  Instr_Mem_demo.v Data_Mem_demo.v ALU.v ALU_Control.v Control_Unit.v \
  Ex_Mem.v Forwarding_Unit.v Hazard_Detection_Unit.v IdEx.v IfId.v \
  Imm_Gen.v MemWb.v PC.v Reg_File.v sha3_mmio.v TOp_module.v \
  input_register.v padder_unit.v state_formation.v keccak_f.v \
  keccak_round.v theta.v rho.v pi.v chi.v iota.v
vvp a.out
```

### Option B — master + slave full path

```bash
cd SHA3_Option_B_AXI
iverilog -g2012 -o b.out tb_axi_pair.v axi_master_mem.v axi_sha3.v \
  TOp_module.v input_register.v padder_unit.v state_formation.v keccak_f.v \
  keccak_round.v theta.v rho.v pi.v chi.v iota.v
vvp b.out
```

### Option C — full pipeline end-to-end

```bash
cd SHA3_Option_C_CustomInstr
iverilog -g2012 -o c.out tb_cop.v Main_Module_cop.v Instr_Mem_cop.v \
  Data_Mem_cop.v Control_Unit_cop.v IdEx_cop.v sha3_cop.v ALU.v \
  ALU_Control.v Ex_Mem.v Forwarding_Unit.v Hazard_Detection_Unit.v IfId.v \
  Imm_Gen.v MemWb.v PC.v Reg_File.v TOp_module.v input_register.v \
  padder_unit.v state_formation.v keccak_f.v keccak_round.v theta.v rho.v \
  pi.v chi.v iota.v
vvp c.out
```

Each prints `PASS` with the matching digest. *(Each option's README also lists a smaller, faster unit test where applicable.)*

---

## 9. Results summary

All options compute `SHA3-256("abc")` correctly in simulation:

```
3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532
```

**Standalone SHA-3 core** (from your project), for reference:

| Metric | Value (XC7Z020 / Zedboard) |
|--------|----------------------------|
| LUTs | ~3,797 |
| Flip-flops | ~6,103 |
| F<sub>max</sub> | ~77 MHz |
| Constraint | 25 MHz met with large positive slack |
| NIST vectors | empty string, "abc", pangram — all pass |

> **Resource note:** the ~6,100-FF core **exceeds** the iCE40UP5K (5,280 FFs), so on that small board these integrations are simulation exercises. They fit comfortably on **XC7Z020** or **Arty A7** for a hardware build.

---

## 10. The one limitation that affects all three

### ⚠ Single-block messages only

The current `sha3_top` hardwires `state_formation` with `use_feedback = 0`, so the multi-block "absorb" feedback path (post-round state XORed into the next block) is not active at the top level. As a result, only messages that fit in one 1088-bit block (≤ 17 lanes, e.g. short strings like `"abc"`) are supported.

This is a property of the **core**, not of any wrapper, so it affects A, B, and C identically. **Wiring the feedback path in `sha3_top` is the single highest-value upgrade** — it would unlock arbitrary-length messages for all three integrations at once, with no change to the wrappers.

**Secondary, shared notes:**
- The CPU has no `ADDI`, so demo programs seed constants in RAM.
- Completion is by polling, not interrupts.
- The data path is 32-bit, so each 64-bit lane is two register writes.

---

## 11. Where to read more

Each option has a **detailed README** with register maps, cycle-by-cycle traces, full assembly listings, hardware-porting guidance, and troubleshooting:

| File | Covers |
|------|--------|
| `README_OptionA_detailed.txt` | memory-mapped I/O |
| `README_OptionB_detailed.txt` | AXI4-Lite (channels, handshake, stall path) |
| `README_OptionC_detailed.txt` | custom instructions (encoding, toolchain) |

Each option folder also has a shorter `README.md` focused on just that build.

---

## 12. Glossary

| Term | Meaning |
|------|---------|
| **Keccak-f** | the 24-round permutation at the heart of SHA-3 |
| **Lane** | a 64-bit slice of the Keccak state; a block is 17 lanes |
| **Block** | one 1088-bit unit absorbed then permuted (for SHA3-256) |
| **Rate** | bits absorbed per block (1088 for SHA3-256) |
| **Digest** | the output hash (256 bits for SHA3-256) |
| **MMIO** | memory-mapped I/O; peripherals accessed via memory addresses |
| **AXI4-Lite** | ARM's simplified on-chip bus for register-style access |
| **VALID/READY** | AXI handshake; a beat transfers when both are high on a clock |
| **BFM** | Bus Functional Model; a testbench that mimics a bus master |
| **Coprocessor** | a functional unit driven by dedicated instructions |
| **Polling** | repeatedly reading a status bit until it changes |
| **Sticky bit** | a flag that stays set until explicitly cleared |
| **Forwarding** | sending an ALU/result value to a later instruction without waiting for writeback |

---

## 13. Credits / references

- **SHA-3 core** and **5-stage RISC-V pipeline:** your project work.
- **Integration wrappers** (A/B/C), testbenches, demo programs, and documentation: produced for this integration exercise.
- **Reference paper:** A. Raveendran, S. B V, D. Selvakumar, *"Micro-Architecture Design and Analysis of AXI Enabled SHA-3 Hardware Accelerator for a RISC-V Based SoC,"* IEEE VLSI SATA 2025.
- **Standard:** FIPS PUB 202, *"SHA-3 Standard: Permutation-Based Hash and Extendable-Output Functions,"* NIST.
