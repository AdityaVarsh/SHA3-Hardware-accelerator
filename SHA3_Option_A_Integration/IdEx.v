module IdEx(
    input wire clk, rst, flush,
    input wire [13:0] id_control_sig,
    output reg [13:0] ex_control_sig,
    input wire [31:0] id_pc, id_imm, id_dat1, id_dat2,
    output reg [31:0] ex_pc, ex_imm, ex_dat1, ex_dat2,
    input wire [4:0] id_rs1, id_rs2, id_rd,
    output reg [4:0] ex_rs1, ex_rs2, ex_rd
);

    always @(posedge clk or posedge rst) 
	begin
        if (rst || flush) 
		begin
            	ex_control_sig <= 14'b0;
            	ex_pc         <= 32'b0;
            	ex_imm        <= 32'b0;
            	ex_dat1       <= 32'b0;
            	ex_dat2       <= 32'b0;
            	ex_rs1        <= 5'b0;
            	ex_rs2        <= 5'b0;
            	ex_rd         <= 5'b0;
        	end 
	else 
		begin
            	ex_control_sig <= id_control_sig;
            	ex_pc         <= id_pc;
            	ex_imm        <= id_imm;
            	ex_dat1       <= id_dat1;
            	ex_dat2       <= id_dat2;
            	ex_rs1        <= id_rs1;
            	ex_rs2        <= id_rs2;
            	ex_rd         <= id_rd;
        	end
    end

endmodule
