`timescale 1ns / 1ps
`default_nettype none
// ALU serial de 4 bits (un nibble por ciclo, LSB primero).
//
// Tabla de control:
//   000 ADD    (C.ADDI, C.LUI = x0 + imm, direccion de C.LW / C.SW)
//   001 SUB    (C.SUB)
//   010 AND    (C.AND)
//   011 XOR    (C.XOR)
//   100 SLL    (C.SLLI)
//   101 SRL    (C.SRLI)
//   110 SRA    (C.SRAI)
//
// Suma/resta: el acarreo se guarda entre nibbles (carry).
// Desplazamientos: la Control Unit lee los nibbles en el orden adecuado;
// aqui se forma una ventana de 8 bits {nibble actual, nibble anterior} y se
// toman 4 bits a partir de la posicion o (0..3). Los nibbles fuera de rango
// valen 0 (SLL/SRL) o el signo (SRA); el signo es prev[3], porque el primer
// nibble fuera de rango siempre llega justo despues del nibble 7.
module ALU (
    input  wire       clk,
    input  wire       step,        // avanzar un nibble
    input  wire       carry_init,  // carry <= 1 si SUB, 0 si no
    input  wire [2:0] ALUControl,
    input  wire [3:0] A,           // nibble del banco de registros
    input  wire [3:0] B,           // nibble de T o del inmediato
    input  wire [1:0] o,           // posicion en la ventana (desplazamientos)
    input  wire       oob,         // nibble fuera de rango
    output reg  [3:0] Y
);

    reg       carry;
    reg [3:0] prev;

    // Sumador de rizado compartido: con la cadena de acarreo apagada la
    // "suma" es A ^ B (XOR); el generador g = A & B es el AND.
    wire       sub   = (ALUControl == 3'b001);
    wire       arith = (ALUControl[2:1] == 2'b00);   // ADD o SUB
    wire [3:0] Bx    = sub ? ~B : B;
    wire [3:0] p     = A ^ Bx;
    wire [3:0] g     = A & Bx;
    wire c0 = carry & arith;
    wire c1 = arith & (g[0] | (p[0] & c0));
    wire c2 = arith & (g[1] | (p[1] & c1));
    wire c3 = arith & (g[2] | (p[2] & c2));
    wire c4 = arith & (g[3] | (p[3] & c3));
    wire [3:0] sum = p ^ {c3, c2, c1, c0};

    wire [3:0] fill = (ALUControl == 3'b110) ? {4{prev[3]}} : 4'b0;
    wire [3:0] cur  = oob ? fill : A;
    wire [7:0] W    = {cur, prev};
    wire [3:0] fun  = W[{1'b0, o} +: 4];

    always @(*) begin
        case (ALUControl)
            3'b000,
            3'b001,
            3'b011:  Y = sum;          // ADD, SUB, XOR
            3'b010:  Y = g;            // AND
            default: Y = fun;          // SLL, SRL, SRA
        endcase
    end

    // carry y prev con reloj gateado (sin muxes de "mantener")
    wire gclk;
    Clock_Gate cg (.clk(clk), .en(carry_init | step), .gclk(gclk));

    always @(posedge gclk) begin
        carry <= carry_init ? sub : c4;
        prev  <= cur;
    end

endmodule
