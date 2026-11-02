package Rv32CpuFault;
    typedef enum logic [4:0] {
        none = 0,
        invalid_instruction = 1,
        misaligned_load = 2,
        misaligned_store = 3
    } Type;
endpackage

module Rv32Cpu (
    input logic clk,

    // RAM
    output logic [29:0] ram_addr,
    output logic [ 3:0] ram_w_strobe,
    output logic [31:0] ram_din,
    input  logic [31:0] ram_dout,

    output Rv32CpuFault::Type fault = Rv32CpuFault::none
);
    enum {
        fetch,
        decode,
        execute,
        writeback,
        halt
    } state = fetch;
    logic [31:0] fetched_inst;

    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [4:0] rd;
    wire [4:0] rs1;
    wire [4:0] rs2;

    assign opcode = fetched_inst[6:0];
    assign funct3 = fetched_inst[14:12];
    assign funct7 = fetched_inst[31:25];
    assign rd = fetched_inst[11:7];
    assign rs1 = fetched_inst[19:15];
    assign rs2 = fetched_inst[24:20];

    enum {
        variant_r,
        variant_i,
        variant_s,
        variant_b,
        variant_u,
        variant_j
    } inst_variant;
    logic sign_extend;

    enum {
        inst_illegal,
        inst_lui,
        inst_auipc,
        inst_addi,
        inst_slti,
        inst_sltiu,
        inst_xori,
        inst_ori,
        inst_andi,
        inst_slli,
        inst_srli,
        inst_srai,
        inst_add,
        inst_sub,
        inst_sll,
        inst_slt,
        inst_sltu,
        inst_xor,
        inst_srl,
        inst_sra,
        inst_or,
        inst_and,
        inst_fence,
        inst_fence_i,
        inst_csrrw,
        inst_csrrs,
        inst_csrrc,
        inst_csrrwi,
        inst_csrrsi,
        inst_csrrci,
        inst_system,   // All system instructions
        inst_lb,
        inst_lh,
        inst_lw,
        inst_lbu,
        inst_lhu,
        inst_sb,
        inst_sh,
        inst_sw,
        inst_jal,
        inst_jalr,
        inst_beq,
        inst_bne,
        inst_blt,
        inst_bge,
        inst_bltu,
        inst_bgeu,

        // M-extension
        inst_mul,
        inst_mulh,
        inst_mulhsu,
        inst_mulhu,
        inst_div,
        inst_divu,
        inst_rem,
        inst_remu
    } inst_type;

    logic [31:0] pc = 32'b0;
    logic [31:0] next_pc = 32'b0;
    logic [31:0] regs[31:0];
    //initial for (int i = 0; i < 32; i++) regs[i] = 0;

    // Decode stage cache
    logic [31:0] imm;
    wire [31:0] load_store_addr = regs[rs1] + imm;

    // Execute stage cache
    logic [31:0] res;

    // ALU
    Rv32AluOp::Type alu_op;
    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_res;
    Rv32Alu alu (
        .op(alu_op),
        .a(alu_a),
        .b(alu_b),
        .result(alu_res),
        .carry()
    );

    // MDU
    Rv32MduOp::Type mdu_op;
    logic [31:0] mdu_a;
    logic [31:0] mdu_b;
    logic [63:0] mdu_res;
    Rv32Mdu mdu (
        .op(mdu_op),
        .a(mdu_a),
        .b(mdu_b),
        .result(mdu_res)
    );

    // DIV
    logic div_start = 1'b0;
    logic div_signed;
    logic [31:0] div_a;
    logic [31:0] div_b;
    wire div_busy;
    wire [31:0] div_quotient;
    wire [31:0] div_remainder;
    Rv32Div div (
        .clk(clk),
        .start(div_start),
        .is_signed(div_signed),
        .a(div_a),
        .b(div_b),
        .busy(div_busy),
        .quotient(div_quotient),
        .remainder(div_remainder)
    );

    // RAM
    logic [1:0] ram_cycle = 0;

    // Decoder
    always_comb begin
        inst_variant = variant_i;
        inst_type = inst_illegal;
        sign_extend = 1'b0;

        case (opcode)
            7'b0110111: begin
                inst_type = inst_lui;
                inst_variant = variant_u;
            end
            7'b0010111: begin
                inst_type = inst_auipc;
                inst_variant = variant_u;
            end
            7'b0010011: begin
                inst_variant = variant_i;
                case (funct3)
                    3'b000: begin
                        inst_type   = inst_addi;
                        sign_extend = 1'b1;
                    end
                    3'b010: begin
                        inst_type   = inst_slti;
                        sign_extend = 1'b1;
                    end
                    3'b011: begin
                        inst_type   = inst_sltiu;
                        sign_extend = 1'b1;
                    end
                    3'b100: begin
                        inst_type   = inst_xori;
                        sign_extend = 1'b1;
                    end
                    3'b110: begin
                        inst_type   = inst_ori;
                        sign_extend = 1'b1;
                    end
                    3'b111: begin
                        inst_type   = inst_andi;
                        sign_extend = 1'b1;
                    end
                    3'b001: begin
                        inst_type   = inst_slli;
                        sign_extend = 1'b0;
                    end
                    3'b101: begin
                        sign_extend = 1'b0;
                        if (funct7 == 7'b0000000) inst_type = inst_srli;
                        else inst_type = inst_srai;
                    end
                endcase
            end
            7'b0110011: begin
                inst_variant = variant_r;
                if (funct7 == 7'b0000001) begin
                    case (funct3)
                        3'b000: inst_type = inst_mul;
                        3'b001: inst_type = inst_mulh;
                        3'b010: inst_type = inst_mulhsu;
                        3'b011: inst_type = inst_mulhu;
                        3'b100: inst_type = inst_div;
                        3'b101: inst_type = inst_divu;
                        3'b110: inst_type = inst_rem;
                        3'b111: inst_type = inst_remu;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: begin
                            if (funct7 == 7'b0000000) inst_type = inst_add;
                            else inst_type = inst_sub;
                        end
                        3'b001: inst_type = inst_sll;
                        3'b010: inst_type = inst_slt;
                        3'b011: inst_type = inst_sltu;
                        3'b100: inst_type = inst_xor;
                        3'b101: begin
                            if (funct7 == 7'b0000000) inst_type = inst_srl;
                            else inst_type = inst_sra;
                        end
                        3'b110: inst_type = inst_or;
                        3'b111: inst_type = inst_and;
                    endcase
                end
            end
            7'b0001111: begin
                inst_variant = variant_i;
                sign_extend  = 1'b0;
                if (funct3 == 3'b000) inst_type = inst_fence;
                else inst_type = inst_fence_i;
            end
            7'b1110011: begin
                inst_variant = variant_i;
                sign_extend  = 1'b0;
                case (funct3)
                    3'b001: inst_type = inst_csrrw;
                    3'b010: inst_type = inst_csrrs;
                    3'b011: inst_type = inst_csrrc;
                    3'b101: inst_type = inst_csrrwi;
                    3'b110: inst_type = inst_csrrsi;
                    3'b111: inst_type = inst_csrrci;
                    3'b000: inst_type = inst_system;
                endcase
            end
            7'b0000011: begin
                inst_variant = variant_i;
                sign_extend  = 1'b1;
                case (funct3)
                    3'b000: inst_type = inst_lb;
                    3'b001: inst_type = inst_lh;
                    3'b010: inst_type = inst_lw;
                    3'b100: inst_type = inst_lbu;
                    3'b101: inst_type = inst_lhu;
                endcase
            end
            7'b0100011: begin
                inst_variant = variant_s;
                case (funct3)
                    3'b000: inst_type = inst_sb;
                    3'b001: inst_type = inst_sh;
                    3'b010: inst_type = inst_sw;
                endcase
            end
            7'b1101111: begin
                inst_variant = variant_j;
                inst_type = inst_jal;
            end
            7'b1100111: begin
                inst_variant = variant_i;
                inst_type = inst_jalr;
                sign_extend = 1'b1;
            end
            7'b1100011: begin
                inst_variant = variant_b;
                case (funct3)
                    3'b000: inst_type = inst_beq;
                    3'b001: inst_type = inst_bne;
                    3'b100: inst_type = inst_blt;
                    3'b101: inst_type = inst_bge;
                    3'b110: inst_type = inst_bltu;
                    3'b111: inst_type = inst_bgeu;
                endcase
            end
        endcase

        // Decode variants
        imm = 32'b0;
        unique case (inst_variant)
            variant_r: begin
            end
            variant_i: begin
                if (sign_extend) imm = {{21{fetched_inst[31]}}, fetched_inst[30:20]};
                else imm = {12'b0, fetched_inst[31:20]};
            end
            variant_s: begin
                imm = {{21{fetched_inst[31]}}, fetched_inst[30:25], fetched_inst[11:7]};
            end
            variant_b: begin
                imm = {
                    {20{fetched_inst[31]}},
                    fetched_inst[7],
                    fetched_inst[30:25],
                    fetched_inst[11:8],
                    1'b0
                };
            end
            variant_u: begin
                imm = {fetched_inst[31:12], 12'b0};
            end
            variant_j: begin
                imm = {
                    {12{fetched_inst[31]}},
                    fetched_inst[19:12],
                    fetched_inst[20],
                    fetched_inst[30:21],
                    1'b0
                };
            end
        endcase
    end

    always_ff @(posedge clk) begin
        ram_w_strobe <= 4'b0;
        div_start <= 1'b0;

        case (state)
            fetch: begin
                if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                case (ram_cycle)
                    0: ram_addr <= pc[31:2];
                    2: begin
                        fetched_inst <= ram_dout;
                        ram_cycle <= 0;
                        next_pc <= pc + 4;
                        state <= decode;
                    end
                endcase
            end
            decode: begin
                case (inst_type)
                    inst_auipc, inst_jal, inst_beq, inst_bne, inst_blt, inst_bge, inst_bltu, inst_bgeu: begin
                        alu_op <= Rv32AluOp::add;
                        alu_a  <= pc;
                        alu_b  <= imm;
                    end
                    inst_addi: begin
                        alu_op <= Rv32AluOp::add;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_xori: begin
                        alu_op <= Rv32AluOp::xor_;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_ori: begin
                        alu_op <= Rv32AluOp::or_;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_andi: begin
                        alu_op <= Rv32AluOp::and_;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_slli: begin
                        alu_op <= Rv32AluOp::sll;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_srli: begin
                        alu_op <= Rv32AluOp::srl;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_srai: begin
                        alu_op <= Rv32AluOp::sra;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_add: begin
                        alu_op <= Rv32AluOp::add;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_sub: begin
                        alu_op <= Rv32AluOp::sub;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_sll: begin
                        alu_op <= Rv32AluOp::sll;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_xor: begin
                        alu_op <= Rv32AluOp::xor_;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_srl: begin
                        alu_op <= Rv32AluOp::srl;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_sra: begin
                        alu_op <= Rv32AluOp::sra;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_or: begin
                        alu_op <= Rv32AluOp::or_;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_and: begin
                        alu_op <= Rv32AluOp::and_;
                        alu_a  <= regs[rs1];
                        alu_b  <= regs[rs2];
                    end
                    inst_jalr: begin
                        alu_op <= Rv32AluOp::add;
                        alu_a  <= regs[rs1];
                        alu_b  <= imm;
                    end
                    inst_mul: begin
                        mdu_op <= Rv32MduOp::mulu;
                        mdu_a  <= regs[rs1];
                        mdu_b  <= regs[rs2];
                    end
                    inst_mulh: begin
                        mdu_op <= Rv32MduOp::mul;
                        mdu_a  <= regs[rs1];
                        mdu_b  <= regs[rs2];
                    end
                    inst_mulhsu: begin
                        mdu_op <= Rv32MduOp::mulsu;
                        mdu_a  <= regs[rs1];
                        mdu_b  <= regs[rs2];
                    end
                    inst_mulhu: begin
                        mdu_op <= Rv32MduOp::mulu;
                        mdu_a  <= regs[rs1];
                        mdu_b  <= regs[rs2];
                    end
                    inst_div, inst_divu, inst_rem, inst_remu: begin
                        div_start  <= 1'b1;
                        div_signed <= inst_type == inst_div || inst_type == inst_rem;
                        div_a      <= regs[rs1];
                        div_b      <= regs[rs2];
                    end
                endcase
                state <= execute;
            end
            execute: begin
                // TODO: skip the writeback stage for S and B variants?
                case (inst_type)
                    inst_lui: begin
                        res   <= imm;
                        state <= writeback;
                    end
                    inst_auipc: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_addi: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_slti: begin
                        res   <= $signed(regs[rs1]) < $signed(imm);
                        state <= writeback;
                    end
                    inst_sltiu: begin
                        res   <= regs[rs1] < imm;
                        state <= writeback;
                    end
                    inst_xori: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_ori: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_andi: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_slli: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_srli: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_srai: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_add: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_sub: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_sll: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_slt: begin
                        res   <= $signed(regs[rs1]) < $signed(regs[rs2]);
                        state <= writeback;
                    end
                    inst_sltu: begin
                        res   <= regs[rs1] < regs[rs2];
                        state <= writeback;
                    end
                    inst_xor: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_srl: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_sra: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_or: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_and: begin
                        res   <= alu_res;
                        state <= writeback;
                    end
                    inst_fence: begin
                        // TODO
                        state <= writeback;
                    end
                    inst_fence_i: begin
                        // TODO
                        state <= writeback;
                    end
                    inst_lb: begin
                        if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                        case (ram_cycle)
                            0: ram_addr <= load_store_addr[31:2];
                            2: begin
                                case (load_store_addr[1:0])
                                    0: res <= {{24{ram_dout[7]}}, ram_dout[7:0]};
                                    1: res <= {{24{ram_dout[15]}}, ram_dout[15:8]};
                                    2: res <= {{24{ram_dout[23]}}, ram_dout[23:16]};
                                    3: res <= {{24{ram_dout[31]}}, ram_dout[31:24]};
                                endcase
                                ram_cycle <= 0;
                                state <= writeback;
                            end
                        endcase
                    end
                    inst_lh: begin
                        if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                        case (ram_cycle)
                            0: ram_addr <= load_store_addr[31:2];
                            2: begin
                                case (load_store_addr[1:0])
                                    0: res <= {{16{ram_dout[15]}}, ram_dout[15:0]};
                                    1: res <= {{16{ram_dout[23]}}, ram_dout[23:8]};
                                    2: res <= {{16{ram_dout[31]}}, ram_dout[31:16]};
                                    3: begin
                                        fault <= Rv32CpuFault::misaligned_load;
                                        state <= halt;
                                    end
                                endcase
                                ram_cycle <= 0;
                                if (load_store_addr[1:0] != 3) state <= writeback;
                            end
                        endcase
                    end
                    inst_lw: begin
                        if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                        case (ram_cycle)
                            0: ram_addr <= load_store_addr[31:2];
                            2: begin
                                if (load_store_addr[1:0] == 0) begin
                                    res   <= ram_dout;
                                    state <= writeback;
                                end else begin
                                    fault <= Rv32CpuFault::misaligned_load;
                                    state <= halt;
                                end
                                ram_cycle <= 0;
                            end
                        endcase
                    end
                    inst_lbu: begin
                        if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                        case (ram_cycle)
                            0: ram_addr <= load_store_addr[31:2];
                            2: begin
                                case (load_store_addr[1:0])
                                    0: res <= {24'b0, ram_dout[7:0]};
                                    1: res <= {24'b0, ram_dout[15:8]};
                                    2: res <= {24'b0, ram_dout[23:16]};
                                    3: res <= {24'b0, ram_dout[31:24]};
                                endcase
                                ram_cycle <= 0;
                                state <= writeback;
                            end
                        endcase
                    end
                    inst_lhu: begin
                        if (ram_cycle < 2) ram_cycle <= ram_cycle + 1;

                        case (ram_cycle)
                            0: ram_addr <= load_store_addr[31:2];
                            2: begin
                                case (load_store_addr[1:0])
                                    0: res <= {16'b0, ram_dout[15:0]};
                                    1: res <= {16'b0, ram_dout[23:8]};
                                    2: res <= {16'b0, ram_dout[31:16]};
                                    3: begin
                                        fault <= Rv32CpuFault::misaligned_load;
                                        state <= halt;
                                    end
                                endcase
                                ram_cycle <= 0;
                                if (load_store_addr[1:0] != 3) state <= writeback;
                            end
                        endcase
                    end
                    inst_sb: begin
                        ram_addr <= load_store_addr[31:2];
                        case (load_store_addr[1:0])
                            2'b00: begin
                                ram_w_strobe <= 4'b0001;
                                ram_din <= {24'h0, regs[rs2][7:0]};
                            end
                            2'b01: begin
                                ram_w_strobe <= 4'b0010;
                                ram_din <= {16'h0, regs[rs2][7:0], 8'h0};
                            end
                            2'b10: begin
                                ram_w_strobe <= 4'b0100;
                                ram_din <= {8'h0, regs[rs2][7:0], 16'h0};
                            end
                            2'b11: begin
                                ram_w_strobe <= 4'b1000;
                                ram_din <= {regs[rs2][7:0], 24'h0};
                            end
                        endcase

                        state <= writeback;
                    end
                    inst_sh: begin
                        ram_addr <= load_store_addr[31:2];
                        case (load_store_addr[1:0])
                            2'b00: begin
                                ram_w_strobe <= 4'b0011;
                                ram_din <= {16'h0, regs[rs2][15:0]};
                            end
                            2'b01: begin
                                ram_w_strobe <= 4'b0110;
                                ram_din <= {8'h0, regs[rs2][15:0], 8'h0};
                            end
                            2'b10: begin
                                ram_w_strobe <= 4'b1100;
                                ram_din <= {regs[rs2][15:0], 16'h0};
                            end
                            2'b11: begin
                                fault <= Rv32CpuFault::misaligned_store;
                                state <= halt;
                            end
                        endcase

                        if (load_store_addr[1:0] != 2'b11) state <= writeback;
                    end
                    inst_sw: begin
                        ram_addr <= load_store_addr[31:2];
                        if (load_store_addr[1:0] == 2'b00) begin
                            ram_w_strobe <= 4'b1111;
                            ram_din <= regs[rs2];
                            state <= writeback;
                        end else begin
                            fault <= Rv32CpuFault::misaligned_store;
                            state <= halt;
                        end
                    end
                    inst_jal: begin
                        res <= next_pc;
                        next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_jalr: begin
                        res <= next_pc;
                        next_pc <= alu_res & ~32'b1;
                        state <= writeback;
                    end
                    inst_beq: begin
                        if (regs[rs1] == regs[rs2]) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_bne: begin
                        if (regs[rs1] != regs[rs2]) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_blt: begin
                        if ($signed(regs[rs1]) < $signed(regs[rs2])) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_bge: begin
                        if ($signed(regs[rs1]) >= $signed(regs[rs2])) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_bltu: begin
                        if (regs[rs1] < regs[rs2]) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_bgeu: begin
                        if (regs[rs1] >= regs[rs2]) next_pc <= alu_res;
                        state <= writeback;
                    end
                    inst_mul: begin
                        res   <= mdu_res[31:0];
                        state <= writeback;
                    end
                    inst_mulh, inst_mulhsu, inst_mulhu: begin
                        res   <= mdu_res[63:32];
                        state <= writeback;
                    end
                    inst_div, inst_divu: begin
                        if (!div_start && !div_busy) begin
                            res   <= div_quotient;
                            state <= writeback;
                        end
                    end
                    inst_rem, inst_remu: begin
                        if (!div_start && !div_busy) begin
                            res   <= div_remainder;
                            state <= writeback;
                        end
                    end
                    default: begin
                        fault <= Rv32CpuFault::invalid_instruction;
                        state <= halt;
                    end
                endcase
            end
            writeback: begin
                case (inst_variant)
                    variant_r, variant_i, variant_u, variant_j: begin
                        if (rd != 0) regs[rd] <= res;
                    end
                endcase
                pc <= next_pc;
                state <= fetch;
            end
            halt: ;
        endcase
    end
endmodule
