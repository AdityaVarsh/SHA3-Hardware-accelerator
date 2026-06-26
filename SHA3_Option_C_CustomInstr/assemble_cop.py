#!/usr/bin/env python3
# Option C demo program: drive the SHA-3 coprocessor via CUSTOM-0 instructions.
# CUSTOM0 opcode = 0b0001011. R-type field layout: funct7|rs2|rs1|funct3|rd|op.
#
# sub-ops (funct3):
#   000 FEED  rs1=lo, rs2=hi
#   001 CFG   rs1=lane_count, rs2=bytecnt
#   010 START
#   011 POLL  rd<-done
#   100 READ  rd<-hash[rs2[2:0]]   (index in rs2 register value)
#
# The CPU has no ADDI, so constants are seeded in RAM and loaded with lw,
# exactly as in the Option A demo.

CUSTOM0 = 0b0001011

def Renc(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7<<25)|(rs2<<20)|(rs1<<15)|(funct3<<12)|(rd<<7)|opcode
def LW(imm,rs1,rd): return ((imm&0xFFF)<<20)|(rs1<<15)|(0b010<<12)|(rd<<7)|0b0000011
def SW(imm,rs2,rs1):
    imm&=0xFFF; return (((imm>>5)&0x7F)<<25)|(rs2<<20)|(rs1<<15)|(0b010<<12)|((imm&0x1F)<<7)|0b0100011
def BEQ(rs1,rs2,imm):
    imm&=0x1FFF
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(0b000<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|0b1100011

FEED  = lambda rs1,rs2:    Renc(0, rs2, rs1, 0b000, 0,  CUSTOM0)
CFG   = lambda rs1,rs2:    Renc(0, rs2, rs1, 0b001, 0,  CUSTOM0)
START = lambda:            Renc(0, 0,   0,   0b010, 0,  CUSTOM0)
POLL  = lambda rd:         Renc(0, 0,   0,   0b011, rd, CUSTOM0)
READ  = lambda rd,idxreg:  Renc(0, idxreg, 0, 0b100, rd, CUSTOM0)

prog = []
# load constants from seeded RAM
prog.append(LW(0x00,0,2))   # x2 = msg lo = 0x00000000
prog.append(LW(0x04,0,3))   # x3 = msg hi = 0x61626300
prog.append(LW(0x08,0,4))   # x4 = 1  (lane count)
prog.append(LW(0x0C,0,6))   # x6 = 3  (byte count)
# index registers 0..7 for READ: load from RAM 0x10..0x2C
for i in range(8):
    prog.append(LW(0x10+4*i,0,8+i))  # x8..x15 = 0..7

# configure + feed + start
prog.append(CFG(4,6))       # lane_count=x4(1), bytecnt=x6(3)
prog.append(FEED(2,3))      # lane0 = {x3,x2}
prog.append(START())

# poll loop: x16 <- done ; if x16==0 loop
poll_idx=len(prog)
prog.append(POLL(16))
prog.append(BEQ(16,0,-4))

# read 8 digest words into x17..x24, store to RAM 0x40..0x5C
for i in range(8):
    prog.append(READ(17+i, 8+i))      # rd=x(17+i), index reg x(8+i)=i
for i in range(8):
    prog.append(SW(0x40+4*i, 17+i, 0))

prog.append(BEQ(0,0,0))     # halt

with open("prog_cop_bytes.txt","w") as f:
    for i,w in enumerate(prog):
        for b in range(4):
            f.write(f"        i_mem[{i*4+b:3d}] = 8'h{(w>>(8*b))&0xFF:02X};\n")
print(f"{len(prog)} instructions, {len(prog)*4} bytes; poll loop at PC=0x{poll_idx*4:X}")
