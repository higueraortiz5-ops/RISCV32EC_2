`timescale 1ns / 1ps
`default_nettype none
// Camino de datos serial por nibbles.
//
//  Inst(4) -> FIFO_In -> Extend Register / Inst --mux--> A1, A2 -> Register File
//  Register File (nibble) -> ALU.A ; T[3:0] / Extend Unit --SrcB_sel--> ALU.B
//  ALU -> T (resultado) y -> Dir (direccion en LW/SW)
//  T  -> Data out (SW) ; Data in -> T (LW) ; T -> Register File (escritura)
module Procesador (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [3:0] inst_in,
    input  wire       halt,
    output wire       hold,

    input  wire [3:0] data_in,
    input  wire       recive,
    output wire       send,
    output wire       mem_write,
    output wire [3:0] dir_out,
    output wire [3:0] data_out
);

    wire [15:0] Inst;
    wire [3:0]  rs1p, rs2p, A2, RA, rf_nib, imm_nib, B, Y;
    reg  [3:0]  A1;
    wire [1:0]  A1_sel, ImmSrc, t_sel;
    wire [2:0]  ALUControl, rn, imm_idx;
    wire        A2_sel, rd_src, WE, SrcB_sel, alu_step, carry_init, oob, zero_a;
    wire [1:0]  o;
    wire        t_en, fifo_inst_en;

    // ---------------- FIFO de instrucciones ----------------
    FIFO_In #(.WIDTH(16)) fifo_inst (
        .clk(clk), .en(fifo_inst_en), .nibble(inst_in), .word(Inst));

    // ---------------- Unidad de control ----------------
    Control_Unit cu (
        .clk(clk), .rst_n(rst_n), .Inst(Inst), .halt(halt), .recive(recive),
        .A1_sel(A1_sel), .A2_sel(A2_sel), .rd_src(rd_src), .rn(rn), .WE(WE),
        .ALUControl(ALUControl), .SrcB_sel(SrcB_sel), .ImmSrc(ImmSrc), .imm_idx(imm_idx),
        .alu_step(alu_step), .carry_init(carry_init), .oob(oob), .o(o), .zero_a(zero_a),
        .t_en(t_en), .t_sel(t_sel),
        .fifo_inst_en(fifo_inst_en), .send(send), .mem_write(mem_write), .hold(hold));

    // ---------------- Seleccion de registros ----------------
    Extend_Register ext_reg (.Inst(Inst[9:2]), .rs1(rs1p), .rs2(rs2p));

    always @(*) begin
        case (A1_sel)
            2'b00:   A1 = Inst[10:7];
            2'b01:   A1 = rs1p;
            default: A1 = rs2p;
        endcase
    end
    assign A2 = A2_sel ? rs2p : Inst[5:2];
    assign RA = zero_a ? 4'd0 : (rd_src ? A2 : A1);

    // ---------------- Registro temporal T (32 bits) ----------------
    reg  [31:0] T;
    reg  [3:0]  t_in;
    wire        t_clk;

    always @(*) begin
        case (t_sel)
            2'd0:    t_in = rf_nib;
            2'd2:    t_in = data_in;
            default: t_in = Y;
        endcase
    end

    Clock_Gate cg_t (.clk(clk), .en(t_en), .gclk(t_clk));
    always @(posedge t_clk)
        T <= {t_in, T[31:4]};

    // ---------------- Banco de registros ----------------
    Register_File rf (
        .clk(clk), .we(WE), .wa(A1), .wd(T), .ra(RA), .rn(rn), .rd_nib(rf_nib));

    // ---------------- Inmediatos y ALU ----------------
    Extend_Unit ext (.Inst(Inst), .ImmSrc(ImmSrc), .idx(imm_idx), .imm_nib(imm_nib));

    assign B = SrcB_sel ? imm_nib : T[3:0];

    ALU alu (
        .clk(clk), .step(alu_step), .carry_init(carry_init), .ALUControl(ALUControl),
        .A(rf_nib), .B(B), .o(o), .oob(oob), .Y(Y));

    // ---------------- Salidas hacia la DM (validas con send = 1) ----------------
    assign dir_out  = Y;
    assign data_out = T[3:0];

endmodule
