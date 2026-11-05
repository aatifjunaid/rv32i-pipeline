# sum 1..10 = 55
addi x1, x0, 0
addi x2, x0, 1
addi x3, x0, 11
loop:
beq  x2, x3, done
add  x1, x1, x2
addi x2, x2, 1
beq  x0, x0, loop
done:
sw   x1, 0(x0)
lw   x4, 0(x0)
halt: beq x0, x0, halt
