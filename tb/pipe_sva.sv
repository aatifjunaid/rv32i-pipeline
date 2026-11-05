// SVA checks for pipe_core. Instantiated from tb_top (ports hooked to dut internals).
module pipe_sva (
  input logic        clk, rst,
  input logic [31:0] x0,                       // regs[0]
  input logic        stall, flush,
  input logic        ex_mem_read,
  input logic [4:0]  ex_rd, id_rs1, id_rs2,
  input logic        id_uses_rs1, id_uses_rs2,
  input logic        ex_branch, ex_eq,
  input logic        ex_reg_write, ex_mem_write
);
  wire load_use     = ex_mem_read && (ex_rd != 0) &&
                      ((id_uses_rs1 && ex_rd == id_rs1) || (id_uses_rs2 && ex_rd == id_rs2));
  wire taken_branch = ex_branch && ex_eq;

  // 1. x0 always reads zero
  a_x0:     assert property (@(posedge clk) disable iff (rst) x0 == 32'd0)
            else $error("SVA: x0 != 0");
  // 2. stall happens exactly on load-use
  a_stall:  assert property (@(posedge clk) disable iff (rst) stall == load_use)
            else $error("SVA: stall != load-use");
  // 3. flush happens exactly on a taken branch
  a_flush:  assert property (@(posedge clk) disable iff (rst) flush == taken_branch)
            else $error("SVA: flush != taken branch");
  // 4. stall/flush inject a bubble (no side effects) into EX next cycle
  a_bubble: assert property (@(posedge clk) disable iff (rst)
              (stall || flush) |=> !(ex_reg_write || ex_mem_write || ex_branch))
            else $error("SVA: bubble not inserted");
endmodule
