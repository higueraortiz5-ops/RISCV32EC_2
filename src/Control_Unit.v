`timescale 1ns / 1ps
`default_nettype none
// Unidad de control (procesador serial por nibbles) para RV32EC:
//   C.LW C.SW C.ADDI C.LUI C.SRLI C.SRAI C.SUB C.XOR C.AND C.SLLI C.MV
//
// Protocolo externo (igual que la version anterior):
//  IM: un nibble de Inst por flanco con halt=1 y hold=0 (4 por instruccion).
//  DM: send=1 durante 8 ciclos con Dir (y Data en SW); mem_write=1 en SW.
//      En LW la DM responde 8 nibbles por Data_in con recive=1.
//
// Estados                                   ciclos
//   FETCH  : recibe 4 nibbles                 >=4
//   DECODE : decide el camino                   1
//   LOADB  : T <= rs2 (MV, SUB, XOR, AND, SW)   8
//   EXEC   : T <= rd op B (ADDI, LUI, SUB...)   8
//   SHIFT  : T <= rd << / >> shamt              9
//   SEND   : Dir = rs1 + imm, Data = T          8   (T avanza para sacar el dato)
//   RECV   : T <= dato de la DM (LW)           >=8
//   WRITE  : rd <= T                            1
module Control_Unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] Inst,
    input  wire        halt,
    input  wire        recive,

    // banco de registros
    output reg  [1:0]  A1_sel,     // 00 Inst[10:7], 01 rs1', 10 rd'(Inst[4:2])
    output wire        A2_sel,     // 0 Inst[5:2], 1 rs2'
    output wire        rd_src,     // puerto de lectura: 0 A1, 1 A2
    output wire [2:0]  rn,         // nibble a leer
    output wire        WE,

    // ALU / inmediatos
    output reg  [2:0]  ALUControl,
    output wire        SrcB_sel,   // 0 T[3:0], 1 inmediato
    output reg  [1:0]  ImmSrc,
    output wire [2:0]  imm_idx,
    output wire        alu_step,
    output wire        carry_init,
    output wire        oob,
    output wire [1:0]  o,          // posicion de la ventana del desplazador
    output wire        zero_a,     // leer x0 (C.LUI = x0 + imm)

    // registro temporal T
    output wire        t_en,
    output reg  [1:0]  t_sel,      // 0 banco, 1 ALU, 2 Data_in

    // interfaz externa
    output wire        fifo_inst_en,
    output wire        send,
    output wire        mem_write,
    output wire        hold
);

    localparam ALU_ADD = 3'b000, ALU_SUB = 3'b001, ALU_AND = 3'b010, ALU_XOR = 3'b011,
               ALU_SLL = 3'b100, ALU_SRL = 3'b101, ALU_SRA = 3'b110;

    localparam S_FETCH = 3'd0, S_DECODE = 3'd1, S_LOADB = 3'd2, S_EXEC = 3'd3,
               S_SHIFT = 3'd4, S_SEND   = 3'd5, S_RECV  = 3'd6, S_WRITE = 3'd7;

    reg [2:0] state;
    reg [3:0] cnt;

    // ---------------- Decodificador (minimo) ----------------
    // Solo distingue las 11 instrucciones soportadas; cualquier otra
    // instruccion RVC tiene comportamiento indefinido. op = 11 (instrucciones
    // de 32 bits) se ejecuta como NOP.
    wire [1:0] op = Inst[1:0];
    wire [2:0] f3 = Inst[15:13];
    wire c0 = (op == 2'b00), c1 = (op == 2'b01), c2 = (op == 2'b10);

    wire is_lw   = c0 & !f3[2];
    wire is_sw   = c0 &  f3[2];
    wire is_addi = c1 & !f3[2] & !f3[1];
    wire is_lui  = c1 & !f3[2] &  f3[1];
    wire is_misc = c1 &  f3[2];
    wire is_srli = is_misc & !Inst[11] & !Inst[10];
    wire is_srai = is_misc & !Inst[11] &  Inst[10];
    wire is_arit = is_misc &  Inst[11];
    wire is_sub  = is_arit & !Inst[6] & !Inst[5];
    wire is_xor  = is_arit & !Inst[6] &  Inst[5];
    wire is_and  = is_arit &  Inst[6];
    wire is_slli = c2 & !f3[2];
    wire is_mv   = c2 &  f3[2];

    wire needs_b  = is_mv | is_sub | is_xor | is_and | is_sw;
    wire is_shr   = is_srli | is_srai;
    wire is_shift = is_slli | is_shr;
    wire is_ri    = is_addi | is_lui;

    // ---------------- Estado y contador ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_FETCH;
            cnt   <= 4'd0;
        end else begin
            case (state)
                S_FETCH:
                    if (halt) begin
                        if (cnt == 4'd3) begin cnt <= 4'd0; state <= S_DECODE; end
                        else cnt <= cnt + 4'd1;
                    end
                S_DECODE: begin
                    cnt <= 4'd0;
                    if      (is_lw)    state <= S_SEND;
                    else if (needs_b)  state <= S_LOADB;
                    else if (is_ri)    state <= S_EXEC;
                    else if (is_shift) state <= S_SHIFT;
                    else               state <= S_FETCH;   // no soportada -> NOP
                end
                S_LOADB:
                    if (cnt == 4'd7) begin
                        cnt   <= 4'd0;
                        state <= is_sw ? S_SEND : (is_mv ? S_WRITE : S_EXEC);
                    end else cnt <= cnt + 4'd1;
                S_EXEC:
                    if (cnt == 4'd7) begin cnt <= 4'd0; state <= S_WRITE; end
                    else cnt <= cnt + 4'd1;
                S_SHIFT:
                    if (cnt == 4'd8) begin cnt <= 4'd0; state <= S_WRITE; end
                    else cnt <= cnt + 4'd1;
                S_SEND:
                    if (cnt == 4'd7) begin cnt <= 4'd0; state <= is_sw ? S_FETCH : S_RECV; end
                    else cnt <= cnt + 4'd1;
                S_RECV:
                    if (recive) begin
                        if (cnt == 4'd7) begin cnt <= 4'd0; state <= S_WRITE; end
                        else cnt <= cnt + 4'd1;
                    end
                default: begin   // S_WRITE
                    cnt   <= 4'd0;
                    state <= S_FETCH;
                end
            endcase
        end
    end

    // ---------------- Indice de nibble para desplazamientos ----------------
    // shamt = Inst[6:2] = 4*q + r. En el ciclo cnt (0..8) se lee el nibble idx:
    //  derecha  : idx = cnt + q                     ventana desde o = r
    //  izquierda: idx = cnt - q - (r != 0)          ventana desde o = (-r) mod 4
    //             (cnt + ~q + (r == 0) en complemento a 2)
    // idx fuera de 0..7 -> oob = idx[4] | idx[3]
    wire [2:0] q       = Inst[6:4];
    wire [1:0] r       = Inst[3:2];
    wire [4:0] addend  = is_shr ? {2'b00, q} : {2'b11, ~q};
    wire       cin     = !is_shr & (r == 2'b00);
    wire [4:0] idx     = {1'b0, cnt} + addend + {4'b0, cin};

    wire st_shift = (state == S_SHIFT);

    assign rn      = st_shift ? idx[2:0] : cnt[2:0];
    assign oob     = st_shift & (idx[4] | idx[3]);
    assign o       = is_shr ? r : {r[1] ^ r[0], r[0]};
    assign imm_idx = cnt[2:0];

    // ---------------- Senales de control ----------------
    assign WE         = (state == S_WRITE);
    assign zero_a     = is_lui;
    assign rd_src     = (state == S_LOADB);
    assign A2_sel     = !is_mv;
    assign SrcB_sel   = is_ri | is_lw | is_sw;
    assign alu_step   = (state == S_EXEC) | st_shift | (state == S_SEND);
    assign carry_init = (state == S_DECODE) | (state == S_LOADB);

    assign t_en = (state == S_LOADB) | (state == S_EXEC) | (state == S_SEND) |
                  (st_shift & (cnt != 4'd0)) | ((state == S_RECV) & recive);

    always @(*) begin
        case (state)
            S_LOADB: t_sel = 2'd0;
            S_RECV : t_sel = 2'd2;
            default: t_sel = 2'd1;
        endcase
    end

    always @(*) begin
        ALUControl = ALU_ADD;
        if (is_sub)  ALUControl = ALU_SUB;
        if (is_and)  ALUControl = ALU_AND;
        if (is_xor)  ALUControl = ALU_XOR;
        if (is_slli) ALUControl = ALU_SLL;
        if (is_srli) ALUControl = ALU_SRL;
        if (is_srai) ALUControl = ALU_SRA;
    end

    always @(*) begin
        ImmSrc = 2'b00;                 // LW / SW
        if (is_addi) ImmSrc = 2'b01;
        if (is_lui)  ImmSrc = 2'b10;
    end

    always @(*) begin
        if (is_addi | is_lui | is_slli | is_mv) A1_sel = 2'b00;   // rd completo
        else                                    A1_sel = 2'b01;   // rs1' / rd'
        if (is_lw && state == S_WRITE)          A1_sel = 2'b10;   // rd' de LW
    end

    assign fifo_inst_en = (state == S_FETCH) & halt;
    assign hold         = (state != S_FETCH);
    assign send         = (state == S_SEND);
    assign mem_write    = (state == S_SEND) & is_sw;

    wire _unused = &{Inst[12], Inst[9:7], f3[0], 1'b0};

endmodule
