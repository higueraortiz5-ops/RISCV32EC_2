`timescale 1ns / 1ps
`default_nettype none
// Banco de registros RV32E con latches: x1..x15 (x0 = 0), 32 bits cada uno.
//
//  Escritura: palabra completa de 32 bits (wd = registro temporal T).
//             Cada registro tiene su clock gate; cuando we=1 en un ciclo, el
//             latch de wa queda transparente durante la mitad alta del ciclo
//             siguiente y captura wd (que no cambia en ese ciclo).
//  Lectura  : un solo puerto de 4 bits: nibble rn del registro ra.
module Register_File (
    input  wire        clk,
    input  wire        we,
    input  wire [3:0]  wa,
    input  wire [31:0] wd,
    input  wire [3:0]  ra,
    input  wire [2:0]  rn,
    output wire [3:0]  rd_nib
);

    wire [32*16-1:0] q;
    assign q[31:0] = 32'b0;     // x0

    genvar r, b;
    generate
        for (r = 1; r < 16; r = r + 1) begin : g_reg
            wire gclk;
            Clock_Gate cg (.clk(clk), .en(we & (wa == r)), .gclk(gclk));
            for (b = 0; b < 32; b = b + 1) begin : g_bit
                Latch_Cell l (.d(wd[b]), .e(gclk), .q(q[r*32 + b]));
            end
        end
    endgenerate

    // Puerto de lectura: AND-OR con seleccion one-hot del registro,
    // luego seleccion del nibble.
    reg [31:0] word;
    integer i;
    always @(*) begin
        word = 32'b0;
        for (i = 1; i < 16; i = i + 1)
            word = word | (q[i*32 +: 32] & {32{ra == i[3:0]}});
    end

    assign rd_nib = word[rn*4 +: 4];

endmodule
