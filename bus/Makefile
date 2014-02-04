verisources=bus.v
veritestbench=testbench.cpp
veriopts=--autoflush -sv --stats
veriobjdir=simulation
top_module=BusTestRig
reportfile=simreport

include_dirs=../
include_dirs_params=$(foreach d, $(include_dirs), -I$d)

CFLAGS=-g

.PHONY: clean verilate all

all: verilate

verilate: $(verisources) $(veritestbench)
	verilator --cc $(verisources) --top-module $(top_module) $(veriopts) --exe $(veritestbench) --Mdir $(veriobjdir) -CFLAGS $(CFLAGS) $(include_dirs_params)
	make -C $(veriobjdir) -f V$(top_module).mk

clean:
	rm -rf $(veriobjdir)
	rm $(reportfile)

simreport: verilate
	./$(veriobjdir)/V$(top_module) > $(reportfile)

