`timescale 1ns / 1ps
`default_nettype none
// Celdas de bajo nivel.
//  - Para sintesis / lint / GDS se instancian directamente las celdas de GF180
//    (latch latq_1 y clock gate icgtp_1), asi el resultado no depende de
//    como la herramienta infiera latches.
//  - Para simulacion RTL (definir RTL_SIM) se usa un modelo de comportamiento.

// Latch transparente en alto (E=1 -> Q=D)
module Latch_Cell (
    input  wire d,
    input  wire e,
    output wire q
);
`ifdef RTL_SIM
    reg q_r;
    always @(*) if (e) q_r = d;
    assign q = q_r;
`else
    gf180mcu_fd_sc_mcu7t5v0__latq_1 u_lat (.E(e), .D(d), .Q(q));
`endif
endmodule

// Clock gate integrado: gclk = clk & en, con en capturado mientras clk = 0
// (sin glitches). Un registro con reloj gateado equivale a un DFF con enable
// pero sin el mux de "mantener", lo que ahorra area.
module Clock_Gate (
    input  wire clk,
    input  wire en,
    output wire gclk
);
`ifdef RTL_SIM
    reg en_l;
    always @(*) if (!clk) en_l = en;
    assign gclk = clk & en_l;
`else
    gf180mcu_fd_sc_mcu7t5v0__icgtp_1 u_icg (.CLK(clk), .E(en), .TE(1'b0), .Q(gclk));
`endif
endmodule
