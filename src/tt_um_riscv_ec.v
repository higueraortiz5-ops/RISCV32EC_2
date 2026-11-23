`timescale 1ns / 1ps
`default_nettype none
// Envoltura con el pinout estandar de Tiny Tapeout (GF180, 1x1)
//
//  ui_in[3:0]   Inst      (IM -> CPU)
//  ui_in[7:4]   Data in   (DM -> CPU, para LW)
//  uo_out[3:0]  Dir       (CPU -> DM)
//  uo_out[7:4]  Data out  (CPU -> DM, para SW)
//  uio[0]  in   Halt      (IM: nibble de instruccion valido)
//  uio[1]  in   Recive    (DM: nibble de dato valido)
//  uio[2]  out  Hold      (CPU -> IM: no enviar)
//  uio[3]  out  Send      (CPU -> DM: Dir/Data validos)
//  uio[4]  out  MemWrite  (1 = SW, 0 = LW)
//  uio[7:5]     sin uso
module tt_um_riscv_ec (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire hold, send, mem_write;

    Procesador cpu (
        .clk(clk), .rst_n(rst_n),
        .inst_in(ui_in[3:0]), .halt(uio_in[0]), .hold(hold),
        .data_in(ui_in[7:4]), .recive(uio_in[1]),
        .send(send), .mem_write(mem_write),
        .dir_out(uo_out[3:0]), .data_out(uo_out[7:4]));

    assign uio_out = {3'b000, mem_write, send, hold, 2'b00};
    assign uio_oe  = 8'b0001_1100;

    wire _unused = &{ena, uio_in[7:2], 1'b0};

endmodule
