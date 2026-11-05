`timescale 1ns/1ps
// Runs the same program on sc_core (reference) and pipe_core, then checks:
//   (a) pipe regs + dmem == single-cycle regs + dmem
//   (b) both match the hand-written expected file (+EXP=...)
// run: +PROG=sim/t5_sum.hex +EXP=programs/t5_sum.exp [+TRACE]
module tb_top;
  localparam CYCLES = 400;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;

  sc_core   ref_core (.clk(clk), .rst(rst));
  pipe_core dut      (.clk(clk), .rst(rst));

  pipe_sva sva (
    .clk(clk), .rst(rst), .x0(dut.regs[0]),
    .stall(dut.stall), .flush(dut.flush),
    .ex_mem_read(dut.ex_mem_read), .ex_rd(dut.ex_rd),
    .id_rs1(dut.id_rs1), .id_rs2(dut.id_rs2),
    .id_uses_rs1(dut.id_uses_rs1), .id_uses_rs2(dut.id_uses_rs2),
    .ex_branch(dut.ex_branch), .ex_eq(dut.ex_eq),
    .ex_reg_write(dut.ex_reg_write), .ex_mem_write(dut.ex_mem_write)
  );

  int cyc = 0, errors = 0, checks = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if ($test$plusargs("TRACE") && !rst)
      $display("c%0d if_pc=%03h id_instr=%08h ex_rd=x%0d mem_rd=x%0d wb_rd=x%0d wb_data=%0d %s%s",
               cyc, dut.if_pc, dut.id_instr, dut.ex_rd, dut.mem_rd, dut.wb_rd, dut.wb_data,
               dut.stall ? "STALL " : "", dut.flush ? "FLUSH" : "");
  end

  task automatic expect_val(string who, string what, int got, int exp);
    checks++;
    if (got !== exp) begin
      $display("  MISMATCH %s %s: got %0d expected %0d", who, what, got, exp);
      errors++;
    end
  endtask

  initial begin
    string exp_file, kind; int fd, a, b;
    if (!$test$plusargs("PROG")) begin
      $display("  ERROR: no +PROG file given"); errors++;
    end
    repeat (3) @(posedge clk);
    #1 rst = 0;
    repeat (CYCLES) @(posedge clk);
    #1;

    // (a) pipeline vs single-cycle reference
    for (int i = 0; i < 32; i++)  expect_val("pipe-vs-ref", $sformatf("x%0d", i), dut.regs[i], ref_core.regs[i]);
    for (int i = 0; i < 256; i++) expect_val("pipe-vs-ref", $sformatf("mem[%0d]", i), dut.dmem[i], ref_core.dmem[i]);

    // (b) expected values
    if ($value$plusargs("EXP=%s", exp_file)) begin
      fd = $fopen(exp_file, "r");
      if (fd == 0) begin
        $display("  ERROR: cannot open expected file %s", exp_file);
        errors++;
      end
      while ($fscanf(fd, "%s %d %d", kind, a, b) == 3) begin
        if (kind == "R") begin
          expect_val("pipe", $sformatf("x%0d", a), dut.regs[a], b);
          expect_val("ref ", $sformatf("x%0d", a), ref_core.regs[a], b);
        end else begin
          expect_val("pipe", $sformatf("mem[%0d]", a), dut.dmem[a], b);
          expect_val("ref ", $sformatf("mem[%0d]", a), ref_core.dmem[a], b);
        end
      end
      $fclose(fd);
    end

    if (!$test$plusargs("EXP")) begin
      $display("  ERROR: no +EXP file given");
      errors++;
    end
    if (errors == 0) $display("TEST PASS (%0d checks)", checks);
    else             $display("TEST FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
