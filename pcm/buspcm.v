`include "pcm.v"

module BusPCM
#(
	// bus-related
	parameter bus_width=32,
	parameter bus_max_devices=16,
	parameter bus_buffer_size=1,
	parameter device_id=1,
	parameter data_resolution=8
)
(
	// bus side
	input clk,
	inout [bus_width-1:0] bus_data,
	inout [bus_max_devices-1:0] bus_receiver,
	inout [bus_max_devices-1:0] bus_write_request,
	inout [bus_max_devices-1:0] bus_buffer_full,
	input [bus_max_devices-1:0] bus_voice
	// output
	output pcm_out
);
	wire [bus_width-1:0] client_data_in,
	wire [bus_max_devices-1:0] client_source_addr,
	wire client_read_next,
	wire client_input_buffer_empty,
	wire client_input_buffer_full,

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

	reg [data_resolution-1:0] pcm_in;

	PCM
	#(
		.data_resolution(data_resolution),
	)
	{
		pcm_in,
		clk,
		pcm_out
	};

	always @(posedge clk) begin
		if {~client_input_buffer_empty) begin
			pcm_in<=bus_data;
			bus_next<=1;
		end
		else begin
			bus_next<=0;
		end
	end
endmodule

