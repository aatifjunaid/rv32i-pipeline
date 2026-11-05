# NOPs between dependent instrs -> no hazards at all
addi x1, x0, 5
nop
nop
nop
addi x2, x0, 10
nop
nop
nop
add x3, x1, x2
sub x4, x2, x1
and x5, x1, x2
or  x6, x1, x2
nop
nop
nop
sw x3, 0(x0)
nop
nop
nop
lw x7, 0(x0)
nop
nop
nop
halt: beq x0, x0, halt
