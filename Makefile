OBJ ?= sim/obj
# make asm   : programs/*.s -> sim/*.hex   (or assemble with RARS: Dump Memory -> Hexadecimal Text)
# make test  : run all programs on Verilator (needs verilator >= 5)
# make run P=t3_loaduse TRACE=1 : single program with per-cycle trace
PROGS := $(basename $(notdir $(wildcard programs/*.s)))
SRC   := rtl/sc_core.v rtl/pipe_core.v tb/pipe_sva.sv tb/tb_top.sv

asm:
	@for p in $(PROGS); do python3 tools/asm.py programs/$$p.s sim/$$p.hex 2>/dev/null; done

$(OBJ)/Vtb_top: $(SRC)
	verilator --binary --timing --assert -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-INITIALDLY \
	  --top-module tb_top -Mdir $(OBJ) $(SRC)

test: asm $(OBJ)/Vtb_top
	@for p in $(PROGS); do printf "%-14s " $$p; \
	  $(OBJ)/Vtb_top +PROG=sim/$$p.hex +EXP=programs/$$p.exp | grep -E "TEST|MISMATCH|SVA|Error" | tr '\n' ' '; echo; done

run: asm $(OBJ)/Vtb_top
	$(OBJ)/Vtb_top +PROG=sim/$(P).hex +EXP=programs/$(P).exp $(if $(TRACE),+TRACE)

BUGS := NOFWD_MEM NOFWD_WB PRIO NOBYPASS NOSTALL NOFLUSH FLUSH1
# make mutate : inject each bug with +BUG_xxx and check that at least one test/assertion catches it
mutate: asm $(OBJ)/Vtb_top
	@for b in $(BUGS); do caught=""; \
	  for p in $(PROGS); do \
	    out=$$($(OBJ)/Vtb_top +PROG=sim/$$p.hex +EXP=programs/$$p.exp +BUG_$$b 2>&1); rc=$$?; \
	    if [ $$rc -ne 0 ] || echo "$$out" | grep -q "TEST FAIL"; then caught="$$caught $$p"; fi; done; \
	  if [ -n "$$caught" ]; then printf "%-10s CAUGHT by:%s\n" $$b "$$caught"; else printf "%-10s *** MISSED ***\n" $$b; fi; done

clean:
	rm -rf $(OBJ)
