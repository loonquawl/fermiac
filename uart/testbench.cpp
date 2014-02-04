#include <iostream>
#include <string>
#include <verilated.h>
#include "Vuart_send.h"

Vuart_send* ptop;
vluint64_t main_time=0;

void print(Vuart_send* ptr)
{
	std::cout << "tx\t"          << (int)ptr->tx          << std::endl
	          << "clock\t"       << (int)ptr->clock       << std::endl
	          << "data_buffer\t" << (char*)ptr->data_buffer << std::endl
	          << "proceed\t"     << (int)ptr->proceed     << std::endl
	          << "buffer_pos\t"  << (int)ptr->buffer_pos  << std::endl
	          << "frame_pos\t"   << (int)ptr->frame_pos   << std::endl;
}

int main(int argc, char** argv)
{
	Verilated::commandArgs(argc, argv);

	ptop=new Vuart_send;
	strcpy((char*)(ptop->data_buffer),"All hail hypnotoad!");
	ptop->proceed=1;

	std::string received_data;

	while (!Verilated::gotFinish() && main_time<1024)
	{
		ptop->eval();

		std::cout << "main_time\t" << main_time << std::endl;
		print(ptop);
		std::cout << std::endl;
		std::cout << "received_data\t" << received_data << std::endl;
		
		if (main_time%2)
			received_data+=ptop->tx ? '1' : '0';

		ptop->clock=++main_time%2;
	}
}

