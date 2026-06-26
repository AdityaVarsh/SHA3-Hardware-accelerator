# SHA-3 Accelerator — Option A (Memory-Mapped) Integration

This integrates your iterative SHA3-256 core into your RV32 5-stage pipeline
using **memory-mapped I/O** — no AXI. The CPU talks to the accelerator with
ordinary `lw` / `sw` instructions, exactly the way it talks to data memory.

## How it works

A small address decoder is spliced into the MEM stage of `main`:

```
  data address 0x000..0x3FF  ->  Data_Mem   (your existing 1 KB RAM)
  data address 0x400..0x4FF  ->  sha3_mmio  (the accelerator window)
```

`sha3_mmio` is the memory-mapped wrapper. It holds the message in a register
file, and a 4-state FSM (IDLE -> FEED -> HASH -> DONE) replays the stored words
into your `sha3_top` core one-per-cycle (driving msg_in/valid_in/is_last/
byte_count), then latches `hash_out` when the core pulses `hash_valid`. The
one-cycle pulse is captured into a *sticky* DONE bit so software can poll it.

Because the accelerator runs for ~45 cycles while the CPU expects single-cycle
memory, completion is handled in **software by polling** the DONE register in a
loop — the pipeline never stalls and your hazard/forwarding logic is untouched.

## Register map (offsets from base 0x400, all 32-bit)

| Offset | Name          | R/W | Meaning                                |
|--------|---------------|-----|----------------------------------------|
| 0x00   | DATA0_LO      | W   | lane 0 bits [31:0]                     |
| 0x04   | DATA0_HI      | W   | lane 0 bits [63:32]                    |
| ...    | DATAn_LO/HI   | W   | lanes 0..16 (offsets 0x00..0x87)       |
| 0x88   | LANE_COUNT    | W   | number of valid lanes (1..17)          |
| 0x8C   | LAST_BYTECNT  | W   | valid bytes in the final lane (1..8)   |
| 0x90   | START         | W   | write 1 to begin hashing               |
| 0x94   | DONE          | R   | 1 = complete (sticky until next START) |
| 0xA0   | HASH0         | R   | digest [31:0]                          |
| 0xA4..0xBC | HASH1..7  | R   | digest [255:32]                        |

Each 64-bit Keccak lane is written as two 32-bit halves because the CPU is
32-bit. The byte packing matches your core's `build_lane`: the word is
MSB-packed big-endian, so "abc" = 0x6162630000000000, i.e. LO=0x00000000,
HI=0x61626300, with LAST_BYTECNT=3.

## Files

New / modified for the integration:
- `sha3_mmio.v`            — the memory-mapped wrapper (register file + FSM)
- `Main_Module_integrated.v` — your `main` with the MEM-stage decoder added
                               (uses `include`; for Vivado/tool flows)
- `Main_Module_flat.v`     — same module with includes stripped (for iverilog
                               where all files are passed on the command line)

Verification:
- `tb_sha3_mmio.v`         — drives the wrapper's memory interface directly and
                             checks SHA3-256("abc"). Fast, reliable proof.
- `tb_integrated.v`        — runs the FULL pipeline executing a real program
                             (assembled below) end to end.
- `assemble.py`            — hand-assembler that emits the demo program bytes.
- `Instr_Mem_demo.v`       — instruction memory preloaded with that program.
- `Data_Mem_demo.v`        — data memory that seeds the constants the program
                             needs (your CPU has no ADDI to build immediates,
                             so constants are loaded from RAM).

Unchanged copies of your pipeline modules are included so the build is
self-contained: ALU, ALU_Control, Control_Unit, Ex_Mem, Forwarding_Unit,
Hazard_Detection_Unit, IdEx, IfId, Imm_Gen, MemWb, PC, Reg_File, plus your
SHA-3 sources (TOp_module, input_register, padder_unit, state_formation,
keccak_f, keccak_round, theta, rho, pi, chi, iota).

## Run it (Icarus Verilog)

Wrapper unit test:
```
iverilog -g2012 -o tb_mmio.out tb_sha3_mmio.v sha3_mmio.v TOp_module.v \
  input_register.v padder_unit.v state_formation.v keccak_f.v keccak_round.v \
  theta.v rho.v pi.v chi.v iota.v
vvp tb_mmio.out
```

Full end-to-end:
```
iverilog -g2012 -o tb_int.out tb_integrated.v Main_Module_flat.v \
  Instr_Mem_demo.v Data_Mem_demo.v ALU.v ALU_Control.v Control_Unit.v \
  Ex_Mem.v Forwarding_Unit.v Hazard_Detection_Unit.v IdEx.v IfId.v \
  Imm_Gen.v MemWb.v PC.v Reg_File.v sha3_mmio.v TOp_module.v \
  input_register.v padder_unit.v state_formation.v keccak_f.v \
  keccak_round.v theta.v rho.v pi.v chi.v iota.v
vvp tb_int.out
```

Both print `PASS`.

## The demo program (what tb_integrated executes)

```
  lw  x1, 0x00(x0)   ; x1 = 0x400  accelerator base   (seeded in RAM)
  lw  x2, 0x04(x0)   ; x2 = msg lo = 0x00000000
  lw  x3, 0x08(x0)   ; x3 = msg hi = 0x61626300
  lw  x4, 0x0C(x0)   ; x4 = 1
  lw  x6, 0x10(x0)   ; x6 = 3   (byte count)
  sw  x2, 0x00(x1)   ; DATA0_LO = msg lo
  sw  x3, 0x04(x1)   ; DATA0_HI = msg hi
  sw  x4, 0x88(x1)   ; LANE_COUNT = 1
  sw  x6, 0x8C(x1)   ; LAST_BYTECNT = 3
  sw  x4, 0x90(x1)   ; START = 1
poll:
  lw  x7, 0x94(x1)   ; x7 = DONE
  beq x7, x0, poll   ; spin until DONE != 0
  lw  x8,  0xA0(x1)  ; read digest words
  ... (x9..x15)
  sw  x8,  0x20(x0)  ; store digest to RAM for inspection
  ... (through 0x3C)
  beq x0, x0, 0      ; halt (self-loop)
```

## Known limitations / notes

- **Single block only** (message <= 1088 bits / 17 lanes). Your current
  `sha3_top` hardwires `use_feedback=0`, so the multi-block absorb path is not
  active. Short strings like "abc" work fully. Wiring the feedback path in
  `sha3_top` would lift this.
- This is a **simulation** integration. The full SHA-3 core is ~6.1k FFs, which
  exceeds the iCE40UP5K. It fits comfortably on XC7Z020 (Zedboard) / Arty A7.
- On real hardware you would put the accelerator at a base address outside your
  RAM region and (optionally) widen the decoder; the principle is identical.
- For a production SoC this same wrapper would expose an AXI4-Lite slave port
  instead of the raw memory interface — that's the only part that changes.
