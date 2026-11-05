// 5-stage pipelined RV32I subset: ADD SUB AND OR ADDI LW SW BEQ
// Signals are prefixed by the stage that owns them: if_ id_ ex_ mem_ wb_
//  - forwarding : EX/MEM and MEM/WB -> ALU inputs (+ regfile write-through for WB->ID)
//  - load-use   : 1-cycle stall (hold PC and IF/ID, bubble into ID/EX)
//  - branch     : resolved in EX, predict not-taken, flush 2 (IF/ID and ID/EX)
module pipe_core (input clk, input rst);
  localparam [31:0] NOP = 32'h0000_0013;       // addi x0,x0,0
  localparam [1:0] ALU_ADD = 2'd0, ALU_SUB = 2'd1, ALU_AND = 2'd2, ALU_OR = 2'd3;

  reg [31:0] imem [0:255];
  reg [31:0] dmem [0:255];
  reg [31:0] regs [0:31];

  // pipeline registers declared up front so every stage can see them
  reg [31:0] id_pc, id_instr;
  reg [31:0] ex_pc, ex_rs1_val, ex_rs2_val, ex_imm;
  reg [4:0]  ex_rs1, ex_rs2, ex_rd;
  reg [1:0]  ex_alu_op;
  reg        ex_alu_src, ex_reg_write, ex_mem_read, ex_mem_write, ex_branch;
  reg [31:0] mem_alu_result, mem_store_data;
  reg [4:0]  mem_rd;
  reg        mem_reg_write, mem_mem_read, mem_mem_write;
  reg [31:0] wb_data;
  reg [4:0]  wb_rd;
  reg        wb_reg_write;

  // ---- bug injection for checking the testbench (sim only, all 0 by default) ----
  reg bug_nofwd_mem = 0, bug_nofwd_wb = 0, bug_prio = 0, bug_nobypass = 0,
      bug_nostall = 0, bug_noflush = 0, bug_flush1 = 0;
`ifndef SYNTHESIS
  initial begin
    if ($test$plusargs("BUG_NOFWD_MEM")) bug_nofwd_mem = 1;  // no EX/MEM -> ALU forwarding
    if ($test$plusargs("BUG_NOFWD_WB"))  bug_nofwd_wb  = 1;  // no MEM/WB -> ALU forwarding
    if ($test$plusargs("BUG_PRIO"))      bug_prio      = 1;  // older (WB) value beats newer (MEM)
    if ($test$plusargs("BUG_NOBYPASS"))  bug_nobypass  = 1;  // no regfile write-through
    if ($test$plusargs("BUG_NOSTALL"))   bug_nostall   = 1;  // load-use stall disabled
    if ($test$plusargs("BUG_NOFLUSH"))   bug_noflush   = 1;  // taken branch does not flush
    if ($test$plusargs("BUG_FLUSH1"))    bug_flush1    = 1;  // flush only 1 instruction, not 2
  end
`endif

  wire        stall, flush;
  wire [31:0] ex_branch_target;

  // ------------------------------------------------------------------ IF
  reg  [31:0] if_pc;
  wire [31:0] if_instr = imem[if_pc[9:2]];

  always @(posedge clk) begin
    if (rst) begin
      if_pc <= 0; id_pc <= 0; id_instr <= NOP;
    end else if (flush) begin
      if_pc <= ex_branch_target;               // redirect
      id_pc <= 0; id_instr <= bug_flush1 ? if_instr : NOP;   // kill instr currently in IF
    end else if (!stall) begin
      if_pc <= if_pc + 32'd4;
      id_pc <= if_pc; id_instr <= if_instr;
    end                                         // stall: hold PC and IF/ID
  end

  // ------------------------------------------------------------------ ID
  wire [6:0] id_opcode = id_instr[6:0];
  wire [4:0] id_rd     = id_instr[11:7];
  wire [2:0] id_funct3 = id_instr[14:12];
  wire [4:0] id_rs1    = id_instr[19:15];
  wire [4:0] id_rs2    = id_instr[24:20];
  wire [6:0] id_funct7 = id_instr[31:25];

  wire id_is_r    = (id_opcode == 7'b0110011);
  wire id_is_addi = (id_opcode == 7'b0010011);
  wire id_is_lw   = (id_opcode == 7'b0000011);
  wire id_is_sw   = (id_opcode == 7'b0100011);
  wire id_is_beq  = (id_opcode == 7'b1100011);

  wire id_reg_write = id_is_r | id_is_addi | id_is_lw;
  wire id_mem_read  = id_is_lw;
  wire id_mem_write = id_is_sw;
  wire id_branch    = id_is_beq;
  wire id_alu_src   = id_is_addi | id_is_lw | id_is_sw;     // 1 = use immediate
  wire id_uses_rs1  = id_is_r | id_is_addi | id_is_lw | id_is_sw | id_is_beq;
  wire id_uses_rs2  = id_is_r | id_is_sw | id_is_beq;

  reg [1:0] id_alu_op;
  always @* begin
    id_alu_op = ALU_ADD;
    if (id_is_r) case (id_funct3)
      3'b000:  id_alu_op = id_funct7[5] ? ALU_SUB : ALU_ADD;
      3'b111:  id_alu_op = ALU_AND;
      3'b110:  id_alu_op = ALU_OR;
      default: id_alu_op = ALU_ADD;
    endcase
  end

  wire [31:0] id_imm_i = {{20{id_instr[31]}}, id_instr[31:20]};
  wire [31:0] id_imm_s = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};
  wire [31:0] id_imm_b = {{19{id_instr[31]}}, id_instr[31], id_instr[7], id_instr[30:25], id_instr[11:8], 1'b0};
  wire [31:0] id_imm   = id_is_sw ? id_imm_s : id_is_beq ? id_imm_b : id_imm_i;

  // regfile read with write-through (WB -> ID in the same cycle)
  wire [31:0] id_rs1_val = (id_rs1 == 0) ? 32'd0 :
                           (!bug_nobypass && wb_reg_write && wb_rd == id_rs1) ? wb_data : regs[id_rs1];
  wire [31:0] id_rs2_val = (id_rs2 == 0) ? 32'd0 :
                           (!bug_nobypass && wb_reg_write && wb_rd == id_rs2) ? wb_data : regs[id_rs2];

  // load-use hazard: instruction in EX is a load whose rd is needed by the one in ID
  assign stall = !bug_nostall && ex_mem_read && (ex_rd != 0) &&
                 ((id_uses_rs1 && ex_rd == id_rs1) || (id_uses_rs2 && ex_rd == id_rs2));

  // ID/EX
  always @(posedge clk) begin
    if (rst || flush || stall) begin            // insert bubble
      ex_pc <= 0; ex_rs1_val <= 0; ex_rs2_val <= 0; ex_imm <= 0;
      ex_rs1 <= 0; ex_rs2 <= 0; ex_rd <= 0; ex_alu_op <= ALU_ADD;
      ex_alu_src <= 0; ex_reg_write <= 0; ex_mem_read <= 0; ex_mem_write <= 0; ex_branch <= 0;
    end else begin
      ex_pc <= id_pc; ex_rs1_val <= id_rs1_val; ex_rs2_val <= id_rs2_val; ex_imm <= id_imm;
      ex_rs1 <= id_rs1; ex_rs2 <= id_rs2; ex_rd <= id_rd; ex_alu_op <= id_alu_op;
      ex_alu_src <= id_alu_src; ex_reg_write <= id_reg_write;
      ex_mem_read <= id_mem_read; ex_mem_write <= id_mem_write; ex_branch <= id_branch;
    end
  end

  // ------------------------------------------------------------------ EX
  reg [31:0] ex_fwd_a, ex_fwd_b;                // later assignment wins -> MEM (newest) beats WB
  always @* begin
    ex_fwd_a = ex_rs1_val;
    if (!bug_nofwd_wb  && wb_reg_write  && wb_rd  != 0 && wb_rd  == ex_rs1) ex_fwd_a = wb_data;
    if (!bug_nofwd_mem && mem_reg_write && mem_rd != 0 && mem_rd == ex_rs1) ex_fwd_a = mem_alu_result;
    if (bug_prio && wb_reg_write && wb_rd != 0 && wb_rd == ex_rs1) ex_fwd_a = wb_data;
    ex_fwd_b = ex_rs2_val;
    if (!bug_nofwd_wb  && wb_reg_write  && wb_rd  != 0 && wb_rd  == ex_rs2) ex_fwd_b = wb_data;
    if (!bug_nofwd_mem && mem_reg_write && mem_rd != 0 && mem_rd == ex_rs2) ex_fwd_b = mem_alu_result;
    if (bug_prio && wb_reg_write && wb_rd != 0 && wb_rd == ex_rs2) ex_fwd_b = wb_data;
  end

  wire [31:0] ex_alu_b = ex_alu_src ? ex_imm : ex_fwd_b;
  reg  [31:0] ex_alu_result;
  always @* begin
    case (ex_alu_op)
      ALU_SUB: ex_alu_result = ex_fwd_a - ex_alu_b;
      ALU_AND: ex_alu_result = ex_fwd_a & ex_alu_b;
      ALU_OR:  ex_alu_result = ex_fwd_a | ex_alu_b;
      default: ex_alu_result = ex_fwd_a + ex_alu_b;
    endcase
  end

  wire ex_eq = (ex_fwd_a == ex_fwd_b);
  assign flush            = !bug_noflush && ex_branch && ex_eq;          // taken branch
  assign ex_branch_target = ex_pc + ex_imm;

  // EX/MEM
  always @(posedge clk) begin
    if (rst) begin
      mem_alu_result <= 0; mem_store_data <= 0; mem_rd <= 0;
      mem_reg_write <= 0; mem_mem_read <= 0; mem_mem_write <= 0;
    end else begin
      mem_alu_result <= ex_alu_result; mem_store_data <= ex_fwd_b; mem_rd <= ex_rd;
      mem_reg_write <= ex_reg_write; mem_mem_read <= ex_mem_read; mem_mem_write <= ex_mem_write;
    end
  end

  // ------------------------------------------------------------------ MEM
  wire [31:0] mem_rdata = dmem[mem_alu_result[9:2]];
  wire [31:0] mem_wdata = mem_mem_read ? mem_rdata : mem_alu_result;

  always @(posedge clk)
    if (!rst && mem_mem_write) dmem[mem_alu_result[9:2]] <= mem_store_data;

  // MEM/WB
  always @(posedge clk) begin
    if (rst) begin wb_data <= 0; wb_rd <= 0; wb_reg_write <= 0; end
    else begin wb_data <= mem_wdata; wb_rd <= mem_rd; wb_reg_write <= mem_reg_write; end
  end

  // ------------------------------------------------------------------ WB
  integer i;
`ifndef SYNTHESIS   // simulation-only: zero memories and load program
  initial begin : init
    reg [1023:0] fname;
    for (i = 0; i < 256; i = i + 1) begin imem[i] = 0; dmem[i] = 0; end
    for (i = 0; i < 32;  i = i + 1) regs[i] = 0;
    if ($value$plusargs("PROG=%s", fname)) $readmemh(fname, imem);
  end
`endif

  always @(posedge clk)
    if (!rst && wb_reg_write && wb_rd != 0) regs[wb_rd] <= wb_data;
endmodule
