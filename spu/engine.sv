// Scanline processing unit engine

import spu::*;

package SpuInstructionOpcode;
    typedef enum logic [2:0] {
        arithmetic = 'b000,
        logical = 'b001,
        jump = 'b010,
        branch = 'b011,
        call = 'b100,
        ret = 'b101,
        blit = 'b110,
        sleep = 'b111
    } Type;
endpackage

package SpuInstructionKind;
    typedef enum {
        invalid,

        //lui,
        alu,
        jal,
        bne,
        call,
        ret,
        blit,
        sleep
    } Type;
endpackage

package SpuInstructionVariant;
    typedef enum {
        invalid,

        r,
        i,
        s,
        b,
        u,
        j
    } Type;
endpackage

package SpuAluOp;
    typedef enum {
        add,
        sub,
        sll,
        srl
    } Type;
endpackage

module SpuEngine (
    input logic clk,

    input logic ctrl,
    input CtrlCommand ctrl_cmd,

    input logic [9:0] x,
    input logic [9:0] y,

    output logic [CRAM_ADDR_WIDTH-1:0] cram_r_addr,
    input logic [CRAM_DATA_WIDTH-1:0] cram_dout,

    output logic [VRAM_ADDR_WIDTH-1:0] vram_r_addr,
    input logic [VRAM_DATA_WIDTH-1:0] vram_dout,

    output logic [CMDRAM_ADDR_WIDTH-1:0] cmdram_r_addr,
    input logic [COMMAND_SIZE-1:0] cmdram_douts[2],

    output Rgba color
);
    localparam XLEN = 20;

    // State
    logic active = 0;
    logic [CMDRAM_ADDR_WIDTH-1:0] reset_addr = 0;

    localparam REG_SEL_WIDTH = 3;
    localparam REGS = 2 ** REG_SEL_WIDTH;

    logic [XLEN-1:0] r[REGS] = '{default: '0};
    logic [CMDRAM_ADDR_WIDTH-1:0] stack[16] = '{default: '0};
    logic [XLEN-1:0] sp = '0;

    // Instruction

    wire [31:0] inst;
    assign inst = cmdram_douts[0];

    SpuInstructionKind::Type inst_kind;
    SpuInstructionVariant::Type inst_variant;
    //logic sign_extend;

    wire SpuInstructionOpcode::Type opcode;
    wire [REG_SEL_WIDTH-1:0] rd;
    wire [2:0] funct3;
    wire [REG_SEL_WIDTH-1:0] ra;
    wire [REG_SEL_WIDTH-1:0] rb;
    wire [XLEN-1:0] imm;
    wire [CMDRAM_ADDR_WIDTH-1:0] imm_addr;

    assign opcode = SpuInstructionOpcode::Type'(inst[2:0]);
    assign rd = inst[5:3];
    assign funct3 = inst[8:6];
    assign ra = inst[11:9];
    assign rb = inst[14:12];
    assign imm = inst[31:12];
    assign imm_addr = inst[26:15];

    // xxxx (4)                   | xxxx (4)        | xxxx (4)   | xxx (3)
    // VRAM value shift increment | CRAM addr bits  | alpha bits | CRAM addr offset
    typedef struct packed {
        logic [2:0] cram_addr_offset;
        logic [3:0] alpha_bits;
        logic [3:0] cram_addr_bits;
        logic [3:0] vram_value_shift_increment;
    } BlitParam;
    wire BlitParam blit_param;
    assign blit_param = BlitParam'({inst[20:12], inst[8:3]});

    logic [XLEN-1:0] sleep_cycles = 0;

    // ALU
    SpuAluOp::Type alu_op;
    logic [XLEN:0] alu_res;

    // Decoder
    always_comb begin
        inst_kind = SpuInstructionKind::invalid;
        inst_variant = SpuInstructionVariant::invalid;
        //sign_extend = '0;
        alu_op = SpuAluOp::add;

        case (opcode)
            //SpuInstructionOpcode::lui: begin
            //    inst_kind = SpuInstructionKind::lui;
            //    inst_variant = SpuInstructionVariant::u;
            //end
            SpuInstructionOpcode::arithmetic: begin
                inst_kind = SpuInstructionKind::alu;
                case (funct3[1:0])
                    2'b00: alu_op = SpuAluOp::add;
                    2'b01: alu_op = SpuAluOp::sub;
                    // TODO
                endcase
                if (funct3[2] == '0) inst_variant = SpuInstructionVariant::r;
                else inst_variant = SpuInstructionVariant::i;
                //sign_extend = funct3[2];
            end
            SpuInstructionOpcode::logical: begin
                inst_kind = SpuInstructionKind::alu;
                case (funct3[1:0])
                    2'b00: alu_op = SpuAluOp::sll;
                    2'b01: alu_op = SpuAluOp::srl;
                    // TODO
                    //2'b10: alu_op = SpuAluOp::sla;
                    //2'b11: alu_op = SpuAluOp::sra;
                endcase
                if (funct3[2] == '0) inst_variant = SpuInstructionVariant::r;
                else inst_variant = SpuInstructionVariant::i;
                //sign_extend = funct3[2];
            end
            SpuInstructionOpcode::jump: begin
                inst_kind = SpuInstructionKind::jal;
                inst_variant = SpuInstructionVariant::j;
                alu_op = SpuAluOp::add;
            end
            SpuInstructionOpcode::branch: begin
                inst_variant = SpuInstructionVariant::b;
                case (funct3)
                    'b000: begin
                        inst_kind = SpuInstructionKind::bne;
                    end
                    // TODO
                endcase
            end
            SpuInstructionOpcode::call: begin
                inst_kind = SpuInstructionKind::call;
                inst_variant = SpuInstructionVariant::j;
                alu_op = SpuAluOp::add;
            end
            SpuInstructionOpcode::ret: begin
                inst_kind = SpuInstructionKind::ret;
                inst_variant = SpuInstructionVariant::s;
            end
            SpuInstructionOpcode::blit: begin
                inst_kind = SpuInstructionKind::blit;
                inst_variant = SpuInstructionVariant::s;
            end
            SpuInstructionOpcode::sleep: begin
                inst_kind = SpuInstructionKind::sleep;
                inst_variant = SpuInstructionVariant::i;
                alu_op = SpuAluOp::add;
            end
        endcase
    end

    logic [XLEN-1:0] src_a;
    logic [XLEN-1:0] src_b;
    logic [CMDRAM_ADDR_WIDTH-1:0] addr;
    always_comb begin
        src_a = '0;
        src_b = '0;
        addr = '0;

        case (inst_variant)
            SpuInstructionVariant::r: begin
                src_a = r[ra];
                src_b = r[rb];
            end
            SpuInstructionVariant::i: begin
                src_a = r[ra];
                src_b = imm;
            end
            SpuInstructionVariant::s: begin
                src_a = r[ra];
            end
            SpuInstructionVariant::b: begin
                src_a = r[ra];
                src_b = r[rb];
                addr = imm_addr;
            end
            SpuInstructionVariant::u: begin
            end
            SpuInstructionVariant::j: begin
                src_a = r[ra];
                src_b = {8'b0, imm_addr};
            end
        endcase
    end

    localparam SHIFT_BITS = $clog2(XLEN);

    always_comb begin
        alu_res = '0;

        case (alu_op)
            SpuAluOp::add: alu_res = src_a + src_b;
            SpuAluOp::sub: alu_res = src_a - src_b;
            SpuAluOp::sll: alu_res = src_a << src_b[SHIFT_BITS-1:0];
            SpuAluOp::srl: alu_res = src_a >> src_b[SHIFT_BITS-1:0];
        endcase
    end

    // Fetch parameters
    logic [2:0] vram_value_shift_in = 0;
    wire [2:0] vram_value_shift_out;
    Delayer #(
        .T(logic[2:0])
    ) vram_value_shift_delayer(
        clk,
        vram_value_shift_in,
        vram_value_shift_out
    );

    logic [3:0] vram_value_shift_increment = 0;

    logic [3:0] cram_addr_bits_in = 0;
    wire [3:0] cram_addr_bits_out;
    Delayer #(
        .T(logic[3:0])
    ) cram_addr_bits_delayer(
        clk,
        cram_addr_bits_in,
        cram_addr_bits_out
    );

    logic [3:0] alpha_bits_in = 0;
    wire [3:0] alpha_bits_out;
    Delayer #(
        .T(logic[3:0])
    ) alpha_bits_delayer(
        clk,
        alpha_bits_in,
        alpha_bits_out
    );

    logic [2:0] cram_addr_offset_in = 0;
    wire [2:0] cram_addr_offset_out;
    Delayer #(
        .T(logic[2:0])
    ) cram_addr_offset_delayer(
        clk,
        cram_addr_offset_in,
        cram_addr_offset_out
    );

    // Next
    wire [3:0] next_vram_value_shift_in = {1'b0, vram_value_shift_in} + vram_value_shift_increment;

    // Color
    wire [VRAM_DATA_WIDTH-1:0] vram_value;
    assign vram_value = vram_dout >> vram_value_shift_out;
    assign cram_r_addr = (vram_value & ((1 << cram_addr_bits_out) - 1)) + {5'b0, cram_addr_offset_out};

    wire [7:0] alpha_raw;
    assign alpha_raw = (vram_value >> cram_addr_bits_out) & ((1 << alpha_bits_out) - 1);
    logic [7:0] alpha;

    always_comb begin
        if (active) begin
            color.rgb = {cram_dout[7:0], cram_dout[15:8], cram_dout[23:16]};
            color.a = alpha;
        end else begin
            color = '{
                rgb: '{default: '0},
                a: '0
            };
        end
    end

    // Clock
    always_ff @(posedge clk) begin
        if (active) begin
            if (y < vga::V_ACTIVE) begin
                // VRAM shift
                if (x < vga::H_ACTIVE) begin
                    if (next_vram_value_shift_in[3] == 1) begin
                        vram_r_addr <= vram_r_addr + 1;
                    end
                    vram_value_shift_in <= next_vram_value_shift_in[2:0];
                end

                // Execute
                // NOTE: the instruction being executed was fetched from the previous cycle's PC, so the PC must only
                // advance when the next cycle executes an instruction
                if (sleep_cycles == '0) begin
                    cmdram_r_addr <= cmdram_r_addr + 1;

                    case (inst_kind)
                        //SpuInstructionKind::lui: begin
                        //    res <= imm19;
                        //end
                        SpuInstructionKind::alu: begin
                            if (rd != '0) r[rd] <= alu_res[XLEN-1:0];
                        end
                        SpuInstructionKind::jal: begin
                            cmdram_r_addr <= alu_res[CMDRAM_ADDR_WIDTH-1:0];
                            sleep_cycles <= 1;
                        end
                        SpuInstructionKind::bne: begin
                            if (src_a != src_b) begin
                                cmdram_r_addr <= addr;
                                sleep_cycles <= 1;
                            end
                        end
                        SpuInstructionKind::call: begin
                            cmdram_r_addr <= alu_res[CMDRAM_ADDR_WIDTH-1:0];
                            stack[sp] <= cmdram_r_addr;
                            sp <= sp + 1;
                            sleep_cycles <= 1;
                        end
                        SpuInstructionKind::ret: begin
                            cmdram_r_addr <= stack[sp - 1];
                            sp <= sp - 1;
                            sleep_cycles <= 1;
                        end
                        SpuInstructionKind::blit: begin
                            vram_r_addr <= src_a[13:0];
                            vram_value_shift_in <= '0;
                            vram_value_shift_increment <= blit_param.vram_value_shift_increment;
                            cram_addr_bits_in <= blit_param.cram_addr_bits;
                            alpha_bits_in <= blit_param.alpha_bits;
                            cram_addr_offset_in <= blit_param.cram_addr_offset;
                        end
                        SpuInstructionKind::sleep: begin
                            // The next instruction has already been fetched, hold it
                            if (alu_res != '0) cmdram_r_addr <= cmdram_r_addr;
                            sleep_cycles <= alu_res[XLEN-1:0];
                        end
                    endcase
                end else begin
                    if (sleep_cycles == 1) cmdram_r_addr <= cmdram_r_addr + 1;
                    sleep_cycles <= sleep_cycles - 1;
                end

                // Alpha
                if (alpha_bits_out != 5'b0) begin
                    alpha <= (alpha_raw << (8 - alpha_bits_out)) | (alpha_raw[0] ? ((1 << (8 - alpha_bits_out)) - 1) : 0);
                end else begin
                    alpha <= 'hff;
                end
            end else if (x == vga::LINE - 1 && y == vga::SCREEN) begin
                // Jump to reset adress
                cmdram_r_addr <= reset_addr;
                sleep_cycles <= '0;
            end else if (x == vga::LINE && y == vga::SCREEN) begin
                // The first instruction has been fetched, fetch the next one
                cmdram_r_addr <= cmdram_r_addr + 1;
            end
        end

        if (ctrl) begin
            case (ctrl_cmd.kind)
                SpuCtrlCommandKind::reset: begin
                    active <= 0;
                    reset_addr <= ctrl_cmd.param[CMDRAM_ADDR_WIDTH-1:0];
                    cmdram_r_addr <= ctrl_cmd.param[CMDRAM_ADDR_WIDTH-1:0];
                    sleep_cycles <= '0;
                end
                SpuCtrlCommandKind::start: begin
                    active <= 1;
                end
                SpuCtrlCommandKind::stop: begin
                    active <= 0;
                end
            endcase
        end
    end
endmodule
