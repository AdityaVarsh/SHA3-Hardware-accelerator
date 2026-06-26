module Ex_Mem(
    input wire flush, clk, rst,
    input wire [9:0] ex_control_sig,
    output reg [9:0] mem_control_sig,
    input wire [31:0] ex_pc, ex_dat2,
    output reg [31:0] mem_pc, mem_dat2,
    input wire [32:0] ex_alu,
    output reg [32:0] mem_alu,
    input wire [4:0] ex_rd,
    output reg [4:0] mem_rd
);

    always @(posedge clk or posedge rst) 
	begin
        if (rst || flush) 
		begin
            	mem_control_sig <= 10'b0;
           	mem_pc <= 32'b0;
            	mem_dat2 <= 32'b0;
            	mem_alu <= 33'b0;
            	mem_rd <= 5'b0;
        	end 
	else 	
		begin
            	mem_control_sig <= ex_control_sig;
            	mem_pc <= ex_pc;
            	mem_dat2 <= ex_dat2;
            	mem_alu <= ex_alu;
            	mem_rd <= ex_rd;
        	end
    	end

endmodule
