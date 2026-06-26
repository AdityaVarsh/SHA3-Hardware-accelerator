module Hazard_Detection_Unit(
    input wire memread,
    input wire [4:0] ifid_rs1, ifid_rs2, idex_rd,
    output wire pc_write, ifid_write, cntrl
);

    wire stall;
    assign stall      = memread && ((idex_rd == ifid_rs1) || (idex_rd == ifid_rs2));
    assign pc_write   = ~stall;
    assign ifid_write = ~stall;
    assign cntrl      = ~stall;

endmodule
