`timescale 1ns / 1ps
`default_nettype none
// Generador de inmediatos: entrega directamente el nibble idx del inmediato.
//
//  ImmSrc | Formato               | Instrucciones
//  -------+-----------------------+-------------------------------
//   00    | CL/CS uimm[6:2]       | C.LW, C.SW   (cero-extendido, x4)
//   01    | CI imm[5:0] con signo | C.ADDI
//   10    | CI nzimm[17:12]       | C.LUI        (con signo, << 12)
// (el shamt de C.SLLI/SRLI/SRAI se toma directo de Inst en la Control Unit)
module Extend_Unit (
    input  wire [15:0] Inst,
    input  wire [1:0]  ImmSrc,
    input  wire [2:0]  idx,
    output reg  [3:0]  imm_nib
);

    wire       s   = Inst[12];                    // signo de imm CI
    wire [2:0] d   = ImmSrc[1] ? idx - 3'd3 : idx; // LUI = ADDI desplazado 3 nibbles
    wire       neg = ImmSrc[1] & (idx < 3'd3);     // nibbles bajos de LUI = 0

    always @(*) begin
        imm_nib = 4'b0;
        if (ImmSrc == 2'b00) begin                // uimm = {I5, I12:10, I6, 00}
            if (idx == 3'd0) imm_nib = {Inst[10], Inst[6], 2'b00};
            if (idx == 3'd1) imm_nib = {1'b0, Inst[5], Inst[12], Inst[11]};
        end else if (!neg) begin                  // sext({I12, I6:2})
            if      (d == 3'd0) imm_nib = Inst[5:2];
            else if (d == 3'd1) imm_nib = {s, s, s, Inst[6]};
            else                imm_nib = {4{s}};
        end
    end


    wire _unused = &{Inst[15:13], Inst[9:7], Inst[1:0], 1'b0};

endmodule
