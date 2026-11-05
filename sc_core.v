// Single-cycle RV32I subset: ADD SUB AND OR ADDI LW SW BEQ
// Role: REFERENCE MODEL. Written independently of pipe_core on purpose.
module sc_core (input clk, input rst);
  reg [31:0] pc;
  reg [31:0] imem [0:255];
  reg [31:0] dmem [0:255];
  reg [31:0] regs [0:31];

  wire [31:0] instr  = imem[pc[9:2]];
  wire [6:0]  opcode = instr[6:0];
  wire [4:0]  rd     = instr[11:7];
  wire [2:0]  funct3 = instr[14:12];
  wire [4:0]  rs1    = instr[19:15];
  wire [4:0]  rs2    = instr[24:20];
  wire [6:0]  funct7 = instr[31:25];

  wire is_r    = (opcode == 7'b0110011);
  wire is_addi = (opcode == 7'b0010011);
  wire is_lw   = (opcode == 7'b0000011);
  wire is_sw   = (opcode == 7'b0100011);
  wire is_beq  = (opcode == 7'b1100011);

  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  wire [31:0] imm   = is_sw ? imm_s : is_beq ? imm_b : imm_i;

  wire [31:0] rv1 = (rs1 == 0) ? 32'd0 : regs[rs1];
  wire [31:0] rv2 = (rs2 == 0) ? 32'd0 : regs[rs2];
  wire [31:0] opb = is_r ? rv2 : imm;

  wire is_sub = is_r && funct3 == 3'b000 && funct7[5];
  wire is_and = is_r && funct3 == 3'b111;
  wire is_or  = is_r && funct3 == 3'b110;
  wire [31:0] alu = is_and ? (rv1 & opb) :
                    is_or  ? (rv1 | opb) :
                    is_sub ? (rv1 - opb) : (rv1 + opb);

  wire        taken = is_beq && (rv1 == rv2);
  wire        we    = is_r | is_addi | is_lw;
  wire [31:0] wdata = is_lw ? dmem[alu[9:2]] : alu;

  integer i;
  initial begin : init
    reg [1023:0] fname;
    for (i = 0; i < 256; i = i + 1) begin imem[i] = 0; dmem[i] = 0; end
    for (i = 0; i < 32;  i = i + 1) regs[i] = 0;
    if ($value$plusargs("PROG=%s", fname)) $readmemh(fname, imem);
  end

  always @(posedge clk) begin
    if (rst) pc <= 32'd0;
    else begin
      pc <= taken ? pc + imm_b : pc + 32'd4;
      if (we && rd != 0) regs[rd] <= wdata;
      if (is_sw)         dmem[alu[9:2]] <= rv2;
    end
  end
endmodule
