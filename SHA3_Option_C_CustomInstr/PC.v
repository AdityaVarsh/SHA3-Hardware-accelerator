module PC (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [31:0] PC_next,
    output reg  [31:0] PC_reg
);

    always @(posedge clk or posedge rst) 
	begin
        if (rst)
            PC_reg <= 32'b0;
        else if (enable)
            PC_reg <= PC_next;
    	end

endmodule
