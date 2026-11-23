`timescale 1ns / 1ps
`default_nettype none
// FIFO de entrada de instrucciones: arma la instruccion de 16 bits con
// 4 nibbles (LSB primero). Usa reloj gateado en vez de mux de enable.
module FIFO_In #(
    parameter WIDTH = 16
) (
    input  wire             clk,
    input  wire             en,      // FIFO_in_EN
    input  wire [3:0]       nibble,
    output reg  [WIDTH-1:0] word
);

    wire gclk;
    Clock_Gate cg (.clk(clk), .en(en), .gclk(gclk));

    always @(posedge gclk)
        word <= {nibble, word[WIDTH-1:4]};

endmodule
