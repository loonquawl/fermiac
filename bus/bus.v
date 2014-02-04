`include "fifo/fifo.v"

module BusArbiter
#(
	parameter bus_width=32,
	parameter bus_max_devices=16	// -1, since device #0 can't be used
)
(
	input clk,
	inout [bus_width-1:0] data_lines,
	inout [bus_max_devices-1:0] receiver_device,	// one-hot 
	inout [bus_max_devices-1:0] buffer_full,	// hold your horses (raised by receiving device)
	input [bus_max_devices-1:0] write_request,	// priority queue: LSBs first, 0 is invalid
	output reg [bus_max_devices-1:0] voice		// one-hot signalling
);
	// device can hold the bus as long as it has to, and we need this
	// register to know when we can assign voice to another device
	reg [bus_max_devices-1:0] operating_device=0;

	generate
		genvar device;
		for (device=1; device<bus_max_devices; device=device+1) begin: voice_gen
			always @(negedge clk)
				// update voice when device has ended its transaction
				if (!operating_device || operating_device&&(~write_request[operating_device])) begin
					voice[device]=write_request[device] && !write_request[device-1:0];
					operating_device=voice; // TODO Will it synthesize?
				end
		end
	endgenerate

	always @(clk) begin
		if (clk)
			$display("BusArbiter: + posedge clk on bus");
		else
			$display("BusArbiter: - negedge clk on bus");
		$display("BusArbiter: bus_data_lines: %b",data_lines);
		$display("BusArbiter: bus_receiver_device: %b",receiver_device);
		$display("BusArbiter: bus_buffer_full: %b",buffer_full);
		$display("BusArbiter: bus_write_request: %b",write_request);
		$display("BusArbiter: bus_voice: %b",voice);
		$display("BusArbiter: operating_device: %b",operating_device);
	end
endmodule

module BusWriter
#(
	parameter bus_width=32,		// compatible with default bus width
	parameter device_id=1		// bit position in bus_voice or bus_receiver, ie. device_id 6 -> sixth bit
)
(
	// bus side
	input clk,
	output [bus_width-1:0] bus_data,
	output [bus_max_devices-1:0] bus_receiver,
	input [bus_max_devices-1:0] bus_buffer_full,
	output [bus_max_devices-1:0] bus_write_request,
	input  [bus_max_devices-1:0] bus_voice,
	// device side
	input [bus_width-1:0] client_data,
	input [bus_max_devices-1:0] client_target_addr,
	input client_enqueue,			// save client_data and client_target_addr in FIFOs
	output client_buffer_empty,		// true, if FIFO empty (all data sent)
	output client_buffer_full		// true, if FIFO full
);
	wire voice=bus_voice[device_id];
	wire receiver_buffer_full=bus_buffer_full[bus_receiver];

	// negedge copies of FIFO data

	wire [bus_width-1:0] buffer_out_net;
	reg [bus_width-1:0] buffer_out_reg;
	wire [bus_max_devices-1:0] receiver_addr_net;
	reg [bus_max_devices-1:0] receiver_addr_reg;
	wire client_buffer_full_net;
	reg client_buffer_full_reg;
	wire client_buffer_empty_net;
	reg client_buffer_empty_reg=1;

	always @(negedge clk) begin
		buffer_out_reg<=buffer_out_net;
		receiver_addr_reg<=receiver_addr_net;
		client_buffer_full_reg<=client_buffer_full_net;
		client_buffer_empty_reg<=client_buffer_empty_net;
	end

	assign bus_receiver=voice ? receiver_addr_reg : 'bz;
	assign bus_data=voice ? buffer_out_reg : 'bz;
	assign client_buffer_empty=client_buffer_empty_reg;
	assign client_buffer_full=client_buffer_full_reg;

	wire wreq=~client_buffer_empty && ~receiver_buffer_full;
	generate
		genvar id;
		for (id=0; id<bus_max_devices; id=id+1) begin: wreq_highz
			assign bus_write_request[id]=id==device_id ? wreq : 'bz; 
		end
	endgenerate

	wire buffer_next=voice && ~receiver_buffer_full && ~client_buffer_empty;
	wire clear=0;

	FIFO 
	#(
		.data_width(bus_width),
		.size(bus_buffer_size),
		.device_id(device_id)
	) buffer
	(	
		.data_in(client_data),
		.data_out(buffer_out_net),
		.clk(clk),
		.next(buffer_next),
		.insert(client_enqueue),
		.clear(clear),
		.full(client_buffer_full_net),
		.empty(client_buffer_empty_net)
	);

	wire recv_addresses_buffer_full;
	wire recv_addresses_buffer_empty;

	FIFO 
	#(
		.data_width(bus_max_devices),
		.size(bus_buffer_size),
		.device_id(device_id<<1)
	) recv_addresses
	(
		.data_in(client_target_addr),
		.data_out(receiver_addr_net),
		.clk(clk),
		.next(buffer_next),
		.insert(client_enqueue),
		.clear(clear),
		.full(recv_addresses_buffer_full),
		.empty(recv_addresses_buffer_empty)
	);

	always @(clk) begin
		if (clk) begin
			$display("BusWriter %d: buffer.next=%b",device_id,buffer_next);
			$display("BusWriter %d: buffer.insert=%b",device_id,client_enqueue);
			$display("BusWriter %d: buffer.full=%b",device_id,client_buffer_full);
			$display("BusWriter %d: buffer.client_buffer_empty=%b",device_id,client_buffer_empty);
			$display("BusWriter %d: buffer.data_in=%b",device_id,client_data);
			$display("BusWriter %d: recv_addresses.data_in=%b",device_id,client_target_addr);
		end
		else begin
			for (int i=0; i<4; i=i+1) begin
				$display("BusWriter %d: mem[%d]=%b",device_id,i,buffer.mem[i]);
			end
			if (receiver_addr_reg==0 && voice)
				$display("BusWriter %d: --MAJOR SCREWUP-- Sending to address 0",device_id);
		end
	end
endmodule

module BusReader
#(
	parameter bus_width=32,		// compatible with default bus width
	parameter bus_max_devices=16,
	parameter bus_buffer_size=32,
	parameter device_id=1		// bit position in bus_voice or bus_receiver, ie. device_id 6 -> sixth bit
)
(
	// bus side
	input clk,
	input [bus_width-1:0] bus_data,
	input [bus_max_devices-1:0] bus_receiver,
	output [bus_max_devices-1:0] bus_buffer_full,
	input  [bus_max_devices-1:0] bus_voice,
	// device side
	output [bus_width-1:0] client_data,
	output [bus_max_devices-1:0] client_source_addr,
	input client_next,			// save client_data and client_source_addr in FIFOs
	output client_buffer_empty,		// true, if FIFO empty (all data read)
	output client_buffer_full		// true, if FIFO full
);
	wire data_on_bus=bus_receiver[device_id] && bus_voice;
	assign bus_buffer_full[device_id]=client_buffer_full;

	wire clear=0;

	FIFO
	#(
		.data_width(bus_width),
		.size(bus_buffer_size),
		.device_id(device_id)
	) buffer
	(	
		.data_in(bus_data),
		.data_out(client_data),
		.clk(clk),
		.next(client_next),
		.insert(data_on_bus),
		.clear(clear),
		.full(client_buffer_full),
		.empty(client_buffer_empty)
	);
	
	wire sender_addresses_buffer_full;
	wire sender_addresses_buffer_empty;

	FIFO
	#(
		.data_width(bus_max_devices), 
		.size(bus_buffer_size),
		.device_id(device_id<<1)
	) sender_addresses
	(
		.data_in(bus_voice),
		.data_out(client_source_addr),
		.clk(clk),
		.next(client_next),
		.insert(data_on_bus),
		.clear(clear),
		.full(sender_addresses_buffer_full),
		.empty(sender_addresses_buffer_empty)
	);

	always @(posedge clk) begin
		if (data_on_bus && client_source_addr==0)
			$display("BusReader %d: --MAJOR SCREWUP-- Received data from address 0",device_id);
	end
endmodule

module BusClient
#(
	parameter bus_width=32,		// compatible with default bus width
	parameter bus_max_devices=16,
	parameter bus_buffer_size=32,
	parameter device_id=1		// bit position in bus_voice or bus_receiver, ie. device_id 6 -> sixth bit
)
(
	// bus side
	input clk,
	inout [bus_width-1:0] bus_data,
	inout [bus_max_devices-1:0] bus_receiver,
	inout [bus_max_devices-1:0] bus_write_request,
	inout [bus_max_devices-1:0] bus_buffer_full,
	input [bus_max_devices-1:0] bus_voice,
	// device side
	output [bus_width-1:0] client_data_in,
	output [bus_max_devices-1:0] client_source_addr,
	input [bus_width-1:0] client_data_out,
	input [bus_max_devices-1:0] client_destination_addr,
	input client_read_next,
	input client_send_next,
	output client_input_buffer_empty,
	output client_input_buffer_full,
	output client_output_buffer_empty,
	output client_output_buffer_full
);
	BusReader 
	#(
		.bus_width(bus_width),	
		.bus_max_devices(bus_max_devices),
		.bus_buffer_size(bus_buffer_size),
		.device_id(device_id)
	) reader
	(
		clk,
		bus_data,
		bus_receiver,
		bus_buffer_full,
		bus_voice,
		client_data_in,
		client_source_addr,
		client_read_next,
		client_input_buffer_empty,
		client_input_buffer_full
	);

	BusWriter 
	#(
		.bus_width(bus_width),	
		.bus_max_devices(bus_max_devices),
		.bus_buffer_size(bus_buffer_size),
		.device_id(device_id)
	) writer
	(
		clk,
		bus_data,
		bus_receiver,
		bus_buffer_full,
		bus_write_request,
		bus_voice,
		client_data_out,
		client_destination_addr,
		client_send_next,
		client_output_buffer_empty,
		client_output_buffer_full
	);

	always @(negedge clk) begin
		$display("BusClient %d: words in in_buffer: %d",device_id,reader.buffer.words_inside);
		$display("BusClient %d: words in out_buffer: %d",device_id,writer.buffer.words_inside);
	end
endmodule

module BusTester
#(
	// bus-related
	parameter bus_width=32,
	parameter bus_max_devices=16,
	parameter bus_buffer_size=32,
	parameter device_id=1,
	parameter send_to=2
)
(
	// bus side
	input clk,
	inout [bus_width-1:0] bus_data,
	inout [bus_max_devices-1:0] bus_receiver,
	inout [bus_max_devices-1:0] bus_write_request,
	inout [bus_max_devices-1:0] bus_buffer_full,
	input [bus_max_devices-1:0] bus_voice
);
	wire [bus_width-1:0]		bus_in;
	wire [bus_max_devices-1:0]	bus_source;
	wire [bus_width-1:0]		bus_out;
	reg [bus_max_devices-1:0]	bus_target;
	wire bus_next;					// read next from FIFO
	wire bus_send;
	wire bus_input_empty;
	wire bus_input_full;
	wire bus_output_empty;
	wire bus_output_full;

	BusClient
	#(
		.bus_width(bus_width),
		.bus_max_devices(bus_max_devices),
		.bus_buffer_size(bus_buffer_size),
		.device_id(device_id)
	) bus_client
	(
		clk,
		bus_data,
		bus_receiver,
		bus_write_request,
		bus_buffer_full,
		bus_voice,
		bus_in,
		bus_source,
		bus_out,
		bus_target,
		bus_next,
		bus_send,
		bus_input_empty,
		bus_input_full,
		bus_output_empty,
		bus_output_full
	);

	reg [31:0] counter;
	assign bus_out=counter;
	assign bus_target=1<<send_to;

	always @(negedge clk) begin
		if (device_id==2) begin
			bus_send<=1;
			bus_next<=0;
			counter<=counter+1;
			$display("BusTester %d: sending %d to %d",device_id,bus_out,bus_target);
		end
		else if (device_id==8) begin
			bus_send<=0;
			if (~bus_input_empty) begin
				bus_next<=1;
				$display("BusTester %d: received %d from %d",device_id,bus_in,bus_source);
			end
			else begin
				bus_next<=0;
				$display("BusTester %d: input buffer empty",device_id);
			end
		end
		else
			$display("BusTester: id==%d",device_id);
	end
endmodule

module BusTestRig
#(
	parameter bus_width=32,
	parameter bus_max_devices=16	// -1, since device #0 can't be used
)
(
	input clk
);
	// bus
	tri [bus_width-1:0] bus_data_lines;
	tri [bus_max_devices-1:0] bus_receiver_device;
	tri [bus_max_devices-1:0] bus_buffer_full;
	wire [bus_max_devices-1:0] bus_write_request;
	wire [bus_max_devices-1:0] bus_voice;

	BusArbiter bus_arbiter
	(
		clk,
		bus_data_lines,
		bus_receiver_device,
		bus_buffer_full,
		bus_write_request,
		bus_voice
	); 

	BusTester
	#(
		.bus_width(32),
		.bus_max_devices(16),
		.device_id(2),
		.send_to(8)
	) test_module_1
	(
		clk,
		bus_data_lines,
		bus_receiver_device,
		bus_write_request,
		bus_buffer_full,
		bus_voice
	);

	BusTester
	#(
		.bus_width(32),
		.bus_max_devices(16),
		.device_id(8),
		.send_to(2)
	) test_module_2
	(
		clk,
		bus_data_lines,
		bus_receiver_device,
		bus_write_request,
		bus_buffer_full,
		bus_voice
	);
endmodule


