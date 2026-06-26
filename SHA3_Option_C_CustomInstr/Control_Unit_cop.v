module Control_Unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,        // needed to classify custom sub-ops
    output reg        regwrite,
    output reg [1:0]  immsel,
    output reg        alusrc,
    output reg [1:0]  aluop,
    output reg        memread,
    output reg        memwrite,
    output reg        memtoreg,
    output reg        branch,
    output reg        is_cop          // NEW: CUSTOM-0 instruction
);

    localparam [6:0]
        R_type  = 7'b0110011,
        I_type  = 7'b0000011,
        S_type  = 7'b0100011,
        B_type  = 7'b1100011,
        CUSTOM0 = 7'b0001011;

    // custom sub-ops that produce a register result
    localparam [2:0] F_POLL=3'b011, F_READ=3'b100;

    always @(*) begin
        // defaults
        regwrite=1'b0; immsel=2'bxx; alusrc=1'b0; aluop=2'bxx;
        memread=1'b0; memwrite=1'b0; memtoreg=1'b0; branch=1'b0; is_cop=1'b0;

        case (opcode)
            R_type: begin
                immsel=2'bxx; regwrite=1'b1; alusrc=1'b0; aluop=2'b10;
                memread=1'b0; memwrite=1'b0; memtoreg=1'b0; branch=1'b0;
            end
            I_type: begin
                immsel=2'b00; regwrite=1'b1; alusrc=1'b1; aluop=2'b00;
                memread=1'b1; memwrite=1'b0; memtoreg=1'b1; branch=1'b0;
            end
            S_type: begin
                immsel=2'b01; regwrite=1'b0; alusrc=1'b1; aluop=2'b00;
                memread=1'b0; memwrite=1'b1; memtoreg=1'bx; branch=1'b0;
            end
            B_type: begin
                immsel=2'b10; regwrite=1'b0; alusrc=1'b0; aluop=2'b01;
                memread=1'b0; memwrite=1'b0; memtoreg=1'bx; branch=1'b1;
            end
            CUSTOM0: begin
                // coprocessor instruction. POLL/READ write a result back to rd;
                // FEED/CFG/START do not. Operands rs1/rs2 read normally
                // (alusrc=0 so forwarded rs2 reaches the coprocessor).
                is_cop   = 1'b1;
                alusrc   = 1'b0;
                aluop    = 2'bxx;
                memread  = 1'b0;
                memwrite = 1'b0;
                memtoreg = 1'b0;        // result comes from cop via ALU path
                branch   = 1'b0;
                immsel   = 2'bxx;
                regwrite = (funct3==F_POLL || funct3==F_READ) ? 1'b1 : 1'b0;
            end
            default: begin
                regwrite=1'b0; immsel=2'bxx; alusrc=1'b0; aluop=2'bxx;
                memread=1'b0; memwrite=1'b0; memtoreg=1'b0; branch=1'b0; is_cop=1'b0;
            end
        endcase
    end
endmodule
