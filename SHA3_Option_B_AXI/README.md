# SHA-3 Accelerator — Option B (AXI4-Lite) Integration

The faithful Section IV approach: the SHA-3 core is wrapped as a real
**AXI4-Lite slave**, and a processor (AXI master) drives it over the five-channel
AXI protocol. This is what you'd build for a production SoC.

Contrast with Option A (memory-mapped): Option A spliced the core directly onto
the pipeline's simple single-cycle memory bus. Option B speaks full AXI4-Lite —
independent AW/W/B/AR/R channels, each with VALID/READY handshaking — so the
accelerator can drop onto any standard AXI interconnect (Zynq PS, Xilinx
SmartConnect, a RISC-V SoC fabric) with no glue.

## Components

| File | Role |
|------|------|
| `axi_sha3.v`        | AXI4-Lite **slave** wrapper around `sha3_top` (32-bit data/addr) |
| `axi_master_mem.v`  | MEM-stage **master** adapter: turns one `lw`/`sw` into an AXI txn, asserts `busy` to stall the CPU until complete |
| `tb_axi_sha3.v`     | AXI master **BFM** testbench driving the slave directly — verifies SHA3-256("abc") over the bus (the paper's verification method) |
| `tb_axi_pair.v`     | Connects master adapter + slave and drives the master's CPU port as a stalled MEM stage would — verifies the **full** CPU→AXI→core→back path |

Plus your unchanged SHA-3 sources (TOp_module, input_register, padder_unit,
state_formation, keccak_f, keccak_round, theta, rho, pi, chi, iota).

## Register map (AXI byte offsets from the slave base, 32-bit)

Identical to Option A — each 64-bit Keccak lane is two 32-bit words:

| Offset | Name | Access |
|--------|------|--------|
| 0x00..0x87 | DATAn_LO / DATAn_HI (lanes 0..16) | W |
| 0x88 | LANE_COUNT (1..17) | W |
| 0x8C | LAST_BYTECNT (1..8) | W |
| 0x90 | START (write 1) | W |
| 0x94 | DONE (sticky) | R |
| 0xA0..0xBC | HASH0..7 (256-bit digest, low word first) | R |

"abc" -> lane0 LO=0x00000000, HI=0x61626300, LANE_COUNT=1, LAST_BYTECNT=3.

## The AXI4-Lite protocol, as implemented

Write transaction (master -> slave):
1. Master drives AWADDR/AWVALID and WDATA/WSTRB/WVALID.
2. Slave raises AWREADY and WREADY when it captures each (independently).
3. Slave commits the register write, raises BVALID (BRESP=OKAY).
4. Master raises BREADY; response accepted; transaction complete.

Read transaction:
1. Master drives ARADDR/ARVALID.
2. Slave raises ARREADY, captures the address.
3. Slave drives RDATA/RVALID (RRESP=OKAY).
4. Master raises RREADY; data accepted.

Every channel transfers only on a clock edge where both VALID and READY are
high — the core AXI rule.

## Run it (Icarus Verilog)

Slave + master BFM (verifies the bus protocol against the slave):
```
iverilog -g2012 -o tb_axi.out tb_axi_sha3.v axi_sha3.v TOp_module.v \
  input_register.v padder_unit.v state_formation.v keccak_f.v keccak_round.v \
  theta.v rho.v pi.v chi.v iota.v
vvp tb_axi.out
```

Full master+slave path (CPU access -> AXI master -> AXI slave -> core):
```
iverilog -g2012 -o tb_pair.out tb_axi_pair.v axi_master_mem.v axi_sha3.v \
  TOp_module.v input_register.v padder_unit.v state_formation.v keccak_f.v \
  keccak_round.v theta.v rho.v pi.v chi.v iota.v
vvp tb_pair.out
```

Both print `PASS`.

## Wiring `axi_master_mem` into your actual pipeline (for a hardware build)

The teaching pipeline assumes single-cycle memory. AXI takes several cycles, so
the pipeline must **stall** during an accelerator access. The adapter exposes
`busy` for exactly this. In `main`:

1. Compute `sel_accel` in the MEM stage (as in Option A).
2. Drive the adapter:
   `req = (mem_read | mem_write) & sel_accel;`
   `we  = mem_write;  addr = mem_alu[31:0];  wdata = mem_dat2;`
3. Mux the read value back:
   `mem_memval = sel_accel ? adapter_rdata : ram_rdata;`
4. Freeze the pipeline while `busy`:
   - gate `pc_write   &= ~busy;`
   - gate `ifid_write &= ~busy;`
   - hold the EX/MEM pipeline register (add an enable, or recirculate it) so
     the same access is re-presented until the transaction completes.
   - squash WB-stage register write while `busy` so the load doesn't retire
     early.

This is more invasive than Option A's single-cycle splice, which is the
tradeoff: AXI buys you standard-bus compatibility at the cost of a stall path.
Because that stall plumbing is specific and easy to get subtly wrong on this
particular pipeline, the master adapter is verified here with a CPU BFM
(`tb_axi_pair.v`) that reproduces the stall behavior exactly. Port the four
wiring steps above when you take it to hardware.

## Notes / limitations

- 32-bit AXI4-Lite (the paper uses 64-bit AXI; 32-bit matches your RV32 world
  and halves the register-count bookkeeping). Widening to 64-bit is mechanical.
- Single-block messages only (sha3_top hardwires use_feedback=0), same as
  Option A.
- Simulation integration; the ~6.1k-FF core fits XC7Z020 / Arty A7, not the
  iCE40UP5K.
- For a Zynq board, you would not instantiate `axi_master_mem` at all — the
  hard ARM PS is the AXI master, and `axi_sha3` connects to it through the
  AXI SmartConnect IP. `axi_master_mem` is only needed when your own soft CPU
  must be the master.
```
