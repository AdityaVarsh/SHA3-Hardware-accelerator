# SHA-3 Accelerator — Option C (Custom Instruction) Integration

The deepest integration: the accelerator is a **coprocessor wired into the
datapath**, reached by new CUSTOM-0 instructions. No memory map, no addresses —
operands come straight from the register file and results go straight back on
the writeback path.

Verified end-to-end on your actual 5-stage pipeline: a program built from the
custom instructions computes SHA3-256("abc") correctly.

## The custom instruction set

Opcode `CUSTOM-0 = 0b0001011`, R-type field layout, sub-op in `funct3`:

| funct3 | mnemonic | operands | effect | writes rd? |
|--------|----------|----------|--------|-----------|
| 000 | SHA.FEED  | rs1=lane_lo, rs2=lane_hi | append a 64-bit lane | no |
| 001 | SHA.CFG   | rs1=lane_count, rs2=bytecnt | set message params | no |
| 010 | SHA.START | — | begin hashing | no |
| 011 | SHA.POLL  | rd | rd <- {31'b0, done} | yes |
| 100 | SHA.READ  | rd, rs2=index | rd <- digest word[rs2[2:0]] | yes |

A full hash: CFG, then one FEED per lane, then START, then POLL in a loop until
done, then eight READs for the 256-bit digest. The long hash latency is hidden
by the POLL loop, so no pipeline stall is required — every custom instruction is
single-cycle in EX.

## How it's wired into the pipeline

Four changes, all minimal:

1. `Control_Unit_cop.v` — decodes `CUSTOM-0`. Takes `funct3` as a new input so
   it can set `regwrite=1` only for POLL/READ. Emits a new `is_cop` signal.
2. `IdEx_cop.v` — control bus widened 14 -> 18 bits to carry `is_cop` (bit 17)
   and `cop_func`=funct3 (bits 16:14) into EX.
3. `sha3_cop.v` — the coprocessor, instantiated in EX. FEED/CFG/START write its
   internal state; POLL/READ drive `cop_result` combinationally. A background
   FSM (IDLE->FEED->HASH->DONE) runs the core after START.
4. `Main_Module_cop.v` — instantiates the coprocessor and muxes its result onto
   the ALU writeback path:
   `ex_result = ex_cop_read ? cop_result : ALU_Result;`
   Because the result rides the normal ALU path, the existing forwarding unit
   handles the POLL-then-BEQ dependency in the poll loop with no extra logic.

Nothing else in the pipeline changes — the hazard unit, branch resolution, and
memory stage are untouched.

## Files

| File | Role |
|------|------|
| `sha3_cop.v`          | the datapath coprocessor (core + FSM + custom-op interface) |
| `Control_Unit_cop.v`  | control unit with CUSTOM-0 decode |
| `IdEx_cop.v`          | ID/EX register widened to 18-bit control |
| `Main_Module_cop.v`   | top with coprocessor instantiated + result mux |
| `assemble_cop.py`     | assembles the demo program |
| `Instr_Mem_cop.v`     | instruction memory preloaded with the program |
| `Data_Mem_cop.v`      | data memory seeding constants + READ index values |
| `tb_cop.v`            | end-to-end testbench (checks abc) |

Unchanged pipeline modules included so the build is self-contained: ALU,
ALU_Control, Ex_Mem, Forwarding_Unit, Hazard_Detection_Unit, IfId, Imm_Gen,
MemWb, PC, Reg_File. Plus your SHA-3 sources.

## Run it (Icarus Verilog)

```
iverilog -g2012 -o tb_cop.out tb_cop.v Main_Module_cop.v \
  Instr_Mem_cop.v Data_Mem_cop.v Control_Unit_cop.v IdEx_cop.v sha3_cop.v \
  ALU.v ALU_Control.v Ex_Mem.v Forwarding_Unit.v Hazard_Detection_Unit.v \
  IfId.v Imm_Gen.v MemWb.v PC.v Reg_File.v TOp_module.v input_register.v \
  padder_unit.v state_formation.v keccak_f.v keccak_round.v theta.v rho.v \
  pi.v chi.v iota.v
vvp tb_cop.out
```

Prints `PASS`.

## The demo program

```
  lw   x2, 0x00(x0)    ; msg lo  = 0x00000000   (seeded)
  lw   x3, 0x04(x0)    ; msg hi  = 0x61626300
  lw   x4, 0x08(x0)    ; 1       (lane count)
  lw   x6, 0x0C(x0)    ; 3       (byte count)
  lw   x8..x15, ...    ; index constants 0..7   (for READ)
  SHA.CFG   x4, x6     ; lane_count=1, bytecnt=3
  SHA.FEED  x2, x3     ; lane0 = {x3,x2}
  SHA.START
poll:
  SHA.POLL  x16        ; x16 <- done
  beq  x16, x0, poll   ; spin until done
  SHA.READ  x17, x8    ; digest word 0  (index in x8=0)
  ... x18..x24 (indices x9..x15 = 1..7)
  sw   x17..x24, 0x40  ; store digest to RAM for inspection
  beq  x0,x0,0         ; halt
```

## How Option C compares

| | A (mem-mapped) | B (AXI4-Lite) | C (custom instr) |
|--|--|--|--|
| CPU interface | `lw`/`sw` to an address | `lw`/`sw` -> AXI master -> bus | new opcodes |
| Decoder change | address decode in MEM | address decode + AXI master | new opcode in Control_Unit |
| Pipeline surgery | minimal | stall path needed | control bus widened, result mux |
| Portability | needs a memory bus | drops on any AXI fabric | tied to this core's ISA |
| Speed | bus-limited | bus-limited | tightest (no address overhead) |

C is the fastest and most tightly coupled, but the least portable: the
accelerator is now part of the CPU's instruction set, so it cannot be reused on
a different processor without re-implementing the decode. The paper lists this
ISA-extension route as future work for exactly this reason.

## Notes / limitations

- Single-block messages only (sha3_top hardwires use_feedback=0).
- The CPU has no ADDI, so constants/indices are seeded in RAM and loaded with
  lw, same as the Option A demo. Adding ADDI would make the program fully
  self-contained.
- Simulation integration; the ~6.1k-FF core fits XC7Z020 / Arty A7, not the
  iCE40UP5K.
- A production custom-instruction design would also extend the assembler/
  toolchain so you could write `sha.feed` in C/asm directly instead of
  hand-encoding CUSTOM-0 words.
```
