# taken / not-taken / load->branch; wrong-path instrs must not commit
addi x1, x0, 1
addi x2, x0, 1
beq  x1, x2, taken
addi x3, x0, 99     # flushed
addi x4, x0, 99     # flushed
taken:
addi x5, x0, 7
beq  x1, x0, skip   # not taken
addi x6, x0, 8
skip:
addi x7, x0, 9
addi x8, x0, 4
addi x9, x0, 4
sw   x8, 0(x0)
lw   x10, 0(x0)
beq  x10, x9, t2    # load-use stall + fwd, taken
addi x11, x0, 99    # flushed
addi x12, x0, 99    # flushed
t2:
addi x13, x0, 5
halt: beq x0, x0, halt
