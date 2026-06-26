module Data_Mem(
    input wire [31:0] addr,
    input wire [31:0] wr_data,
    input wire mem_read, mem_write,
    input wire clk, rst,
    output reg [31:0] rd_data
);
    reg [7:0] d_mem [0:1023];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i=0;i<1024;i=i+1) d_mem[i] <= 8'b0;
            d_mem[0] <= 8'h00;
            d_mem[1] <= 8'h04;
            d_mem[2] <= 8'h00;
            d_mem[3] <= 8'h00;
            d_mem[4] <= 8'h00;
            d_mem[5] <= 8'h00;
            d_mem[6] <= 8'h00;
            d_mem[7] <= 8'h00;
            d_mem[8] <= 8'h00;
            d_mem[9] <= 8'h63;
            d_mem[10] <= 8'h62;
            d_mem[11] <= 8'h61;
            d_mem[12] <= 8'h01;
            d_mem[13] <= 8'h00;
            d_mem[14] <= 8'h00;
            d_mem[15] <= 8'h00;
            d_mem[16] <= 8'h03;
            d_mem[17] <= 8'h00;
            d_mem[18] <= 8'h00;
            d_mem[19] <= 8'h00;
        end else if (mem_write) begin
            d_mem[addr]   <= wr_data[7:0];
            d_mem[addr+1] <= wr_data[15:8];
            d_mem[addr+2] <= wr_data[23:16];
            d_mem[addr+3] <= wr_data[31:24];
        end
    end
    always @(*) begin
        if (mem_read)
            rd_data = {d_mem[addr+3], d_mem[addr+2], d_mem[addr+1], d_mem[addr]};
        else
            rd_data = 32'bx;
    end
endmodule
