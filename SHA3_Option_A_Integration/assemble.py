#!/usr/bin/env python3
# Hand-assembler for the small RV32 subset this pipeline supports:
#   R: add, sub      I: lw, addi(only via lw path? -> we only have lw for I)
#   S: sw            B: beq
# The pipeline's Control_Unit decodes opcode only:
#   R_type=0110011, I_type(load)=0000011, S_type=0100011, B_type=1100011
# ALU_Control uses funct3/funct7. For addresses we need to build constants.
#
# PROBLEM: this CPU has no ADDI (I-type arithmetic) -- I_type opcode is wired
# to loads. So we cannot synthesize arbitrary constants with addi.
# We CAN preload constants into data memory and lw them, OR use a tiny trick:
# registers start at 0 after reset; we build values by loading from prepared
# RAM words. The testbench seeds RAM with the constants the program needs.
#
# Register usage:
#   x1 = accelerator base (0x400)
#   x2 = message low half  (0x00000000)
#   x3 = message high half (0x61626300)
#   x4 = constant 1
#   x5 = lane count (1), x6 = byte count (3)
#   x7 = scratch (DONE poll)
#   x8..x15 = digest words
#
# Memory map of seeded constants (RAM, byte addresses):
#   0x00 : 0x00000400  (accel base)
#   0x04 : 0x00000000  (msg lo)
#   0x08 : 0x61626300  (msg hi)
#   0x0C : 0x00000001  (one / lane count)
#   0x10 : 0x00000003  (byte count)

def R(funct7, rs2, rs1, funct3, rd, opcode=0b0110011):
    return (funct7<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(rd<<7)|opcode

def I(imm, rs1, funct3, rd, opcode=0b0000011):  # load
    imm &= 0xFFF
    return (imm<<20)|(rs1<<15)|(funct3<<12)|(rd<<7)|opcode

def S(imm, rs2, rs1, funct3, opcode=0b0100011):  # store
    imm &= 0xFFF
    imm11_5 = (imm>>5)&0x7F
    imm4_0  = imm&0x1F
    return (imm11_5<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(imm4_0<<7)|opcode

def B(imm, rs2, rs1, funct3, opcode=0b1100011):  # branch (imm in bytes, even)
    # B-imm encoding: imm[12|10:5] and imm[4:1|11]
    imm &= 0x1FFF
    b12   = (imm>>12)&1
    b10_5 = (imm>>5)&0x3F
    b4_1  = (imm>>1)&0xF
    b11   = (imm>>11)&1
    return (b12<<31)|(b10_5<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(b4_1<<8)|(b11<<7)|opcode

LW  = lambda imm,rs1,rd: I(imm,rs1,0b010,rd)
SW  = lambda imm,rs2,rs1: S(imm,rs2,rs1,0b010)
ADD = lambda rd,rs1,rs2: R(0,rs2,rs1,0,rd)
SUB = lambda rd,rs1,rs2: R(0b0100000,rs2,rs1,0,rd)
BEQ = lambda rs1,rs2,imm: B(imm,rs2,rs1,0b000)

prog = []

# --- load constants from seeded RAM into registers ---
prog.append(LW(0x00,0,1))   # x1 = MEM[0x00] = 0x400  (accel base)
prog.append(LW(0x04,0,2))   # x2 = MEM[0x04] = msg lo
prog.append(LW(0x08,0,3))   # x3 = MEM[0x08] = msg hi
prog.append(LW(0x0C,0,4))   # x4 = MEM[0x0C] = 1
prog.append(LW(0x10,0,6))   # x6 = MEM[0x10] = 3 (byte count)

# --- write message lane 0 (lo @ +0x00, hi @ +0x04) ---
prog.append(SW(0x00,2,1))   # accel[0x00] = msg lo
prog.append(SW(0x04,3,1))   # accel[0x04] = msg hi
# --- lane count = 1 (x4), byte count = 3 (x6) ---
prog.append(SW(0x88,4,1))   # accel[0x88] = 1
prog.append(SW(0x8C,6,1))   # accel[0x8C] = 3
# --- START = 1 ---
prog.append(SW(0x90,4,1))   # accel[0x90] = 1

# --- poll loop: x7 = accel[0x94]; if x7==x0 (==0) loop back ---
poll_idx = len(prog)
prog.append(LW(0x94,1,7))            # x7 = DONE
prog.append(BEQ(7,0,-4))             # if x7==0 -> back to the LW (PC-4)

# --- read digest words into x8..x15 ---
prog.append(LW(0xA0,1,8))
prog.append(LW(0xA4,1,9))
prog.append(LW(0xA8,1,10))
prog.append(LW(0xAC,1,11))
prog.append(LW(0xB0,1,12))
prog.append(LW(0xB4,1,13))
prog.append(LW(0xB8,1,14))
prog.append(LW(0xBC,1,15))

# --- store digest back to RAM at 0x20.. so we can inspect ---
prog.append(SW(0x20,8,0))
prog.append(SW(0x24,9,0))
prog.append(SW(0x28,10,0))
prog.append(SW(0x2C,11,0))
prog.append(SW(0x30,12,0))
prog.append(SW(0x34,13,0))
prog.append(SW(0x38,14,0))
prog.append(SW(0x3C,15,0))

# --- halt: infinite self-loop ---
prog.append(BEQ(0,0,0))   # beq x0,x0,0 -> spin

# emit as byte initialization for i_mem
with open("prog_bytes.txt","w") as f:
    for i,word in enumerate(prog):
        for b in range(4):
            byte = (word>>(8*b))&0xFF
            f.write(f"        i_mem[{i*4+b:3d}] = 8'h{byte:02X};\n")

print(f"Program length: {len(prog)} instructions, {len(prog)*4} bytes")
print(f"Poll loop at instruction index {poll_idx} (PC=0x{poll_idx*4:X})")
