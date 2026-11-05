# back-to-back dependences: EX/MEM fwd, MEM/WB fwd, WB->ID write-through, priority
addi x1, x0, 5
addi x2, x1, 3      # 8  (EX/MEM fwd)
add  x3, x2, x1     # 13 (x2 EX/MEM, x1 MEM/WB)
sub  x4, x3, x2     # 5
and  x5, x4, x3     # 5
or   x6, x2, x4     # 13
sw   x6, 4(x0)      # store data forwarded
addi x7, x0, 1
addi x8, x0, 2
addi x9, x0, 3
add  x10, x7, x9    # 4  (x7 written in WB same cycle as ID read)
add  x11, x10, x10  # 8  (both operands fwd)
addi x12, x0, 1
addi x12, x12, 1    # 2
addi x12, x12, 1    # 3  (needs EX/MEM priority over MEM/WB)
halt: beq x0, x0, halt
