#!/usr/bin/env python3
"""Tiny assembler: add sub and or addi lw sw beq nop (+ labels, # comments).
usage: asm.py prog.s prog.hex   (writes one 32-bit hex word per line + prints listing)"""
import sys, re

R = {'add': (0x00, 0), 'sub': (0x20, 0), 'and': (0x00, 7), 'or': (0x00, 6)}
reg = lambda s: int(s.strip().lstrip('x'))
num = lambda s: int(s.strip(), 0)

def enc_r(f7, rs2, rs1, f3, rd, op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_i(imm, rs1, f3, rd, op):     return ((imm & 0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op
def enc_b(imm, rs2, rs1, f3, op):
    imm &= 0x1FFF
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3F)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xF)<<8)|(((imm>>11)&1)<<7)|op

src = [l.split('#')[0].strip() for l in open(sys.argv[1])]
labels, lines, pc = {}, [], 0
for l in src:
    while ':' in l:
        lab, l = l.split(':', 1); labels[lab.strip()] = pc; l = l.strip()
    if l: lines.append((pc, l)); pc += 4

out = []
for pc, l in lines:
    m, _, rest = l.partition(' ')
    a = [x.strip() for x in rest.split(',')] if rest.strip() else []
    if m == 'nop':    w = enc_i(0, 0, 0, 0, 0x13)
    elif m in R:      w = enc_r(R[m][0], reg(a[2]), reg(a[1]), R[m][1], reg(a[0]), 0x33)
    elif m == 'addi': w = enc_i(num(a[2]), reg(a[1]), 0, reg(a[0]), 0x13)
    elif m == 'lw':
        o, r = re.match(r'(-?\w+)\((x\d+)\)', a[1]).groups(); w = enc_i(num(o), reg(r), 2, reg(a[0]), 0x03)
    elif m == 'sw':
        o, r = re.match(r'(-?\w+)\((x\d+)\)', a[1]).groups(); w = enc_s(num(o), reg(a[0]), reg(r), 2, 0x23)
    elif m == 'beq':
        off = labels[a[2]] - pc if a[2] in labels else num(a[2])
        w = enc_b(off, reg(a[1]), reg(a[0]), 0, 0x63)
    else: sys.exit(f'unknown instr: {l}')
    out.append(w); print(f'{pc:04x}: {w:08x}   {l}', file=sys.stderr)
open(sys.argv[2], 'w').write(''.join(f'{w:08x}\n' for w in out))
