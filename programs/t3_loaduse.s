# load-use stalls
addi x1, x0, 100
sw   x1, 0(x0)
lw   x2, 0(x0)
add  x3, x2, x2     # stall -> 200
lw   x4, 0(x0)
sw   x4, 4(x0)      # stall (store data) -> mem[1]=100
lw   x5, 0(x0)
addi x6, x5, 1      # stall -> 101
lw   x7, 0(x0)
add  x8, x0, x0     # filler
add  x9, x7, x1     # no stall, fwd from WB -> 200
halt: beq x0, x0, halt
