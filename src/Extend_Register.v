`timescale 1ns / 1ps
`default_nettype none
// Expande los campos de 3 bits de RVC (rs1', rs2', rd') a x8..x15
module Extend_Register(
    input  wire [9:2] Inst,
    output wire [3:0] rs1,   // rs1' / rd'  = Inst[9:7]
    output wire [3:0] rs2    // rs2' / rd'  = Inst[4:2]
    );

    assign rs1 = {1'b1, Inst[9:7]};
    assign rs2 = {1'b1, Inst[4:2]};

    wire _unused = &{Inst[6:5], 1'b0};

endmodule
