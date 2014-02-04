#include <iostream>
#include <verilated.h>
#include "simulation/VBusTestRig.h"

typedef unsigned int uint;
typedef unsigned char byte;

int main(int argc, char** argv)
{
	Verilated::commandArgs(argc,argv);

	VBusTestRig* pmodule=new VBusTestRig;

	uint cycle=0;
	while (!Verilated::gotFinish() && cycle++<8192)
	{
		pmodule->clk=!pmodule->clk;
		std::cout << "--NEXT EVAL--" << std::endl;
		std::cout << (pmodule->clk ? "--POSEDGE--" : "--NEGEDGE--") << std::endl;
		pmodule->eval();
	}

	std::cout << "--END--" << std::endl;

	return 0;
}

