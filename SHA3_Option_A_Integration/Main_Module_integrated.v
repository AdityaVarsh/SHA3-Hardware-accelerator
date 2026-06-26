`include "ALU.v"
`include "ALU_Control.v"
`include "Control_Unit.v"
`include "Data_Mem.v"
`include "Imm_Gen.v"
`include "Instr_Mem.v"
`include "Reg_File.v"
`include "Ex_Mem.v"
`include "Forwarding_Unit.v"
`include "Hazard_Detection_Unit.v"
`include "IdEx.v"
`include "IfId.v"
`include "MemWb.v"
`include "PC.v"

// ---- SHA-3 accelerator (Option A: memory-mapped) ----
`include "sha3_mmio.v"
`include "TOp_module.v"
`include "input_register.v"
`include "padder_unit.v"
`include "state_formation.v"
`include "keccak_f.v"
`include "keccak_round.v"
`include "theta.v"
`include "rho.v"
`include "pi.v"
`include "chi.v"
`include "iota.v"

module main(
    input  wire clk,
    input  wire rst,
    input  wire interrupt
);

    wire pc_write;
    wire pc_src;
    wire [31:0] pc_next_temp, pc_reg, mem_br_addr, pc_incr, instr, pc_next;

    assign pc_incr = pc_reg + 32'd4;
    assign pc_next_temp = pc_src ? mem_br_addr : pc_incr;
    assign pc_next = interrupt ? 32'h80000180 : pc_next_temp;

    PC program_counter(
        .clk(clk),
        .rst(rst),
        .enable(pc_write),
        .PC_next(pc_next),
        .PC_reg(pc_reg)
    );

    Instr_Mem I_mem(
        .PC(pc_reg),
        .instr(instr)
    );

    wire ifid_write;
    wire [31:0] id_pc, id_instr;
    wire flush = pc_src;
    wire interr_flush = flush | interrupt;

    IfId if_id(
        .flush(interr_flush),
        .clk(clk),
        .rst(rst),
        .enable(ifid_write),
        .if_pc(pc_reg),
        .if_instr(instr),
        .id_pc(id_pc),
        .id_instr(id_instr)
    );

    wire [4:0] id_rs1, id_rs2, id_rd;
    wire [6:0] id_opcode, id_funct7;
    wire [2:0] id_funct3;

    assign id_rs1    = id_instr[19:15];
    assign id_rs2    = id_instr[24:20];
    assign id_rd     = id_instr[11:7];
    assign id_opcode = id_instr[6:0];
    assign id_funct3 = id_instr[14:12];
    assign id_funct7 = id_instr[31:25];

    wire [3:0] id_ALU_Cntrl;
    wire [1:0] id_immsel, id_aluop;
    wire id_regwrite, id_alusrc, id_memread, id_memwrite, id_memtoreg, id_branch;
    wire wb_regwrite;
    wire [4:0] wb_rd;
    wire [31:0] wb_wr_data;
    wire [31:0] id_dat1, id_dat2, id_imm;

    Control_Unit cu(
        .opcode(id_opcode),
        .regwrite(id_regwrite),
        .immsel(id_immsel),
        .alusrc(id_alusrc),
        .aluop(id_aluop),
        .memread(id_memread),
        .memwrite(id_memwrite),
        .memtoreg(id_memtoreg),
        .branch(id_branch)
    );

    ALU_Control_Unit alu_cu(
        .ALU_Op(id_aluop),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .ALU_Cntrl(id_ALU_Cntrl)
    );

    Reg_File regs(
        .rd_reg1(id_rs1),
        .rd_reg2(id_rs2),
        .wr_reg(wb_rd),
        .wr_data(wb_wr_data),
        .DAT1(id_dat1),
        .DAT2(id_dat2),
        .reg_wr(wb_regwrite),
        .rst(rst),
        .clk(clk)
    );

    Imm_Gen immgen(
        .instr(id_instr),
        .Imm_out(id_imm),
        .Imm_sel(id_immsel)
    );

    wire cntrl;
    wire [13:0] id_control_sig_temp = {
        id_ALU_Cntrl,    // [13:10]
        id_immsel,       // [9:8]
        id_aluop,        // [7:6]
        id_regwrite,     // [5]
        id_alusrc,       // [4]
        id_memread,      // [3]
        id_memwrite,     // [2]
        id_memtoreg,     // [1]
        id_branch        // [0]
    };

    wire [13:0] id_control_sig = cntrl ? id_control_sig_temp : 14'b0;
    wire [13:0] ex_control_sig;
    wire [31:0] ex_pc, ex_imm, ex_dat1, ex_dat2;
    wire [4:0] ex_rs1, ex_rs2, ex_rd;

    IdEx id_ex(
        .flush(interr_flush),
        .clk(clk),
        .rst(rst),
        .id_control_sig(id_control_sig),
        .id_pc(id_pc),
        .id_dat1(id_dat1),
        .id_dat2(id_dat2),
        .id_imm(id_imm),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),
        .ex_control_sig(ex_control_sig),
        .ex_pc(ex_pc),
        .ex_dat1(ex_dat1),
        .ex_dat2(ex_dat2),
        .ex_imm(ex_imm),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd)
    );

    wire [1:0] forwardA, forwardB;
    reg  [31:0] alu_in1, alu_in21;
    wire [31:0] alu_in2;

    wire [32:0] mem_alu;

    always @(*)
    begin
        case (forwardA)
            2'b00: alu_in1 = ex_dat1;
            2'b01: alu_in1 = wb_wr_data;
            2'b10: alu_in1 = mem_alu[31:0];
            default: alu_in1 = ex_dat1;
        endcase
    end

    always @(*)
    begin
        case (forwardB)
            2'b00: alu_in21 = ex_dat2;
            2'b01: alu_in21 = wb_wr_data;
            2'b10: alu_in21 = mem_alu[31:0];
            default: alu_in21 = ex_dat2;
        endcase
    end

    assign alu_in2 = (ex_control_sig[4]) ? ex_imm : alu_in21;

    wire ex_zero;
    wire [31:0] ALU_Result;

    ALU alu(
        .ALU_Cntrl(ex_control_sig[13:10]),
        .In1(alu_in1),
        .In2(alu_in2),
        .Zero(ex_zero),
        .ALU_Result(ALU_Result)
    );

    wire [32:0] ex_alu = {ex_zero, ALU_Result};
    wire [31:0] ex_br_addr = ex_pc + (ex_imm << 1);

    wire [9:0] mem_control_sig;
    wire [31:0] mem_dat2;
    wire [4:0] mem_rd;

    reg [31:0] EPC;
    always @(posedge clk or posedge rst)
    begin
        if (rst)
            EPC <= 32'b0;
        else if (interrupt)
            EPC <= ex_pc;
    end

    Ex_Mem ex_mem(
        .flush(flush),
        .clk(clk),
        .rst(rst),
        .ex_control_sig(ex_control_sig[9:0]),
        .ex_pc(ex_br_addr),
        .ex_alu(ex_alu),
        .ex_dat2(alu_in21),
        .ex_rd(ex_rd),
        .mem_control_sig(mem_control_sig),
        .mem_pc(mem_br_addr),
        .mem_alu(mem_alu),
        .mem_dat2(mem_dat2),
        .mem_rd(mem_rd)
    );

    assign pc_src = mem_alu[32] && mem_control_sig[0];

    // ====================================================================
    // MEM-stage address decoder  (Option A integration)
    // --------------------------------------------------------------------
    // Data memory  : addresses 0x000 .. 0x3FF  (the existing 1 KB RAM)
    // Accelerator  : addresses 0x400 .. 0x4FF  (256-byte MMIO window)
    //
    // sel_accel is asserted when the address lands in the accelerator page.
    // The read value muxes back from whichever target was selected; reads
    // are combinational on both sides, matching the original Data_Mem.
    // ====================================================================
    wire [31:0] mem_addr = mem_alu[31:0];
    wire        sel_accel = (mem_addr[31:8] == 24'h000004); // 0x000004xx

    wire        mem_rd_sig = mem_control_sig[3];
    wire        mem_wr_sig = mem_control_sig[2];

    // gated controls
    wire        ram_read   = mem_rd_sig & ~sel_accel;
    wire        ram_write  = mem_wr_sig & ~sel_accel;
    wire        accel_read = mem_rd_sig &  sel_accel;
    wire        accel_write= mem_wr_sig &  sel_accel;

    wire [31:0] ram_rdata;
    wire [31:0] accel_rdata;

    // final read value back to MEM/WB
    wire [31:0] mem_memval = sel_accel ? accel_rdata : ram_rdata;

    Data_Mem D_mem(
        .addr(mem_addr),
        .wr_data(mem_dat2),
        .rd_data(ram_rdata),
        .mem_read(ram_read),
        .mem_write(ram_write),
        .clk(clk),
        .rst(rst)
    );

    sha3_mmio U_sha3_mmio(
        .clk   (clk),
        .rst   (rst),
        .addr  (mem_addr),          // lower 8 bits used inside as offset
        .wdata (mem_dat2),
        .we    (accel_write),
        .rd    (accel_read),
        .rdata (accel_rdata)
    );

    wire [9:0] wb_control_sig;
    wire [31:0] wb_memval, wb_alu;

    MemWb mem_wb(
        .clk(clk),
        .rst(rst),
        .mem_control_sig(mem_control_sig),
        .mem_memval(mem_memval),
        .mem_alu(mem_alu[31:0]),
        .mem_rd(mem_rd),
        .wb_control_sig(wb_control_sig),
        .wb_memval(wb_memval),
        .wb_alu(wb_alu),
        .wb_rd(wb_rd)
    );

    assign wb_regwrite = wb_control_sig[5];
    assign wb_wr_data   = (wb_control_sig[1]) ? wb_memval : wb_alu;

    Forwarding_Unit fw(
        .exmem_regwr(mem_control_sig[5]),
        .exmem_rd(mem_rd),
        .memwb_regwr(wb_control_sig[5]),
        .memwb_rd(wb_rd),
        .idex_rs1(ex_rs1),
        .idex_rs2(ex_rs2),
        .forwardA(forwardA),
        .forwardB(forwardB)
    );

    Hazard_Detection_Unit hd(
        .memread(ex_control_sig[3]),
        .ifid_rs1(id_rs1),
        .ifid_rs2(id_rs2),
        .idex_rd(ex_rd),
        .pc_write(pc_write),
        .ifid_write(ifid_write),
        .cntrl(cntrl)
    );

endmodule
