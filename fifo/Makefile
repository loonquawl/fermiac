verisources=fifo.v
veritestbench=testbench.cpp
veriopts=--autoflush -sv --stats
veriobjdir=simulation
top_module=FIFO
reportfile=simreport

CFLAGS=-g

.PHONY: clean verilate all

all: verilate

verilate: $(verisources) $(veritestbench)
	verilator --cc $(verisources) --top-module $(top_module) $(veriopts) --exe $(veritestbench) --Mdir $(veriobjdir) -CFLAGS $(CFLAGS)
	make -C $(veriobjdir) -f V$(top_module).mk

clean:
	rm -rf $(veriobjdir)
	rm $(reportfile)

simreport: verilate
	./$(veriobjdir)/V$(top_module) > $(reportfile)

