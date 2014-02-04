#include <iostream>
#include <verilated.h>
#include <sys/types.h>
#include "simulation/VFIFO.h"

int main(int argc, char** argv)
{
	Verilated::commandArgs(argc,argv);

	/* won't write a testbench for this - it just works */

	VFIFO* pfifo=new VFIFO;
	uint cycle=0;
	while (!Verilated::gotFinish() && cycle++<8192)
	{
		pfifo->clk=!pfifo->clk;
		std::cout << "--NEXT EVAL--"                              << std::endl;
		std::cout << (pfifo->clk ? "--POSEDGE--" : "--NEGEDGE--") << std::endl;
		pfifo->eval();
	}
	std::cout << "--END--" << std::endl;
}

