`include "fifo.v"

/*
 *	This one is based on CY7C1041V33 datasheet, but I'll try to make
 *	it portable. Maybe interfaces won't differ that much.
 *
 *	Maximum access time is 12-25 ns, don't know exact model number.
 */
typedef enum {highz,read,write} SRAMMode;
typedef enum {busy,ready} SRAMState;
module SRAMInterface
#(
	// chip-related
	parameter bus_period_ns=7,	// 150MHz
	parameter access_time_ns=20,
	parameter ready_timer_bits=8,
	parameter word_length=16,
	parameter address_width=18,	
	// bus-related
	parameter bus_width=32,
	parameter bus_max_devices=16,
	parameter bus_buffer_size=32,
	parameter device_id=1
)
(
	// bus side
	input clk,
	inout [bus_width-1:0] bus_data,
	inout [bus_max_devices-1:0] bus_receiver,
	inout [bus_max_devices-1:0] bus_write_request,
	inout [bus_max_devices-1:0] bus_buffer_full,
	input [bus_max_devices-1:0] bus_voice,
	// ram chip side
	output reg [address_width-1:0] chip_address_lines,
	inout [word_length-1:0] chip_data_lines,
	output reg chip_disable,	// "enable" in datasheet, inverted input
	output reg write_disable,
	output reg byte_low_disable,
	output reg byte_high_disable,
	output reg output_disable
);
	specparam tick_access_time=access_time_ns/bus_period_ns;

	wire [bus_width-1:0]		bus_in;
	wire [bus_max_devices-1:0]	bus_source;
	wire [bus_width-1:0]		bus_out;
	reg [bus_max_devices-1:0]	bus_target;	// yup, reg - I'll need this
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

	// Huh, looks like we need some kind of device protocol.
	// Let's say that first 2 LSB's of data on bus indicates action: one of
	// these in SRAMMode, next N bits are address, and depending on
	// action, there can also be 8 bits of data to write.
	// |AC|		ADDR		       |	DATA   |
	// 0..2..4..6..8..10..12..14..16..18..20..22..24..26..28..30..32
	// LSB								MSB

	wire [1:0] action=bus_in[0+:2];					// TODO is it the correct notation for LSB==0?
	wire [address_width-1:0] address=bus_in[2+:address_width];	// TODO read/write word length
	wire [7:0] data=bus_in[address_width+2+:8];

	assign bus_out[0+:word_length]=chip_data_lines;
	assign bus_out[word_length+:address_width]=chip_address_lines;

	reg [ready_timer_bits-1:0] ready_timer=0;
	SRAMState state=ready;

	always @(negedge clk) begin
		if (state==ready) begin
			bus_send<=0;
			bus_next<=0;
			if (~bus_input_empty) begin
				state<=busy;
				bus_target<=bus_source;		// bus_target is reg
				case (SRAMMode'(action))
					read: begin
						chip_address_lines<=address;
							chip_read;
						ready_timer<=tick_access_time;
					end
					write: begin
						chip_address_lines<=address;
						chip_data_lines<=data;
						chip_write;
							ready_timer<=tick_access_time;
					end
					highz: chip_highz;
				endcase
			end
		end
		else if (state==busy) begin
			if (~ready_timer) begin
				bus_send<=1;
				bus_next<=1; //	get another request
				state<=ready;
			end
			else begin
				ready_timer<=ready_timer-1;
			end
		end
	end

	task chip_highz;
		chip_disable<=1;
		write_disable<=1;
		byte_low_disable<=1;
		byte_high_disable<=1;
		output_disable<=1;
	endtask

	task chip_read;
		chip_disable<=0;
		write_disable<=1;
		byte_low_disable<=0;
		byte_high_disable<=0;
		output_disable<=0;
	endtask

	task chip_write;
		chip_disable<=0;
		write_disable<=0;
		byte_low_disable<=0;
		byte_high_disable<=0;
		// probably don't care
		//output_disable<=0;
	endtask
endmodule

module VGAGenerator
#(
	parameter pixel_freq=25_000_000,
	parameter clock_freq=150_000_000,
	parameter VRAM_freq=50_000_000,
	parameter line_front_porch=16,	// pixels
	parameter line_sync_pulse=96,
	parameter line_active_video=640,
	parameter line_back_porch=48,
	parameter frame_front_porch=10,	// lines
	parameter frame_sync_pulse=2,
	parameter frame_active_video=480,
	parameter frame_back_porch=33,
	parameter VRAM_address_lines=18,
	parameter vga_red_bits=3,
	parameter vga_green_bits=3,
	parameter vga_blue_bits=2,
	parameter bus_device_id=1,
	parameter bus_max_devices=16,
	parameter bus_width=32
)
(
	input clk,
	input enable,
	// system bus
	inout [bus_width-1:0] bus_data_lines,
	inout [bus_max_devices-1:0] bus_receiver_device,
	input [bus_max_devices-1:0] voice,	
	inout [bus_max_devices-1:0] buffer_full,	// hold your horses (raised by receiving device)
	output bus_write_request,	
	// VGA output
	output hsync,
	output vsync,
	output [vga_red_bits-1:0] red,
	output [vga_green_bits-1:0] green,
	output [vga_blue_bits-1:0] blue
);
	// boundaries for each stage (line, pixels)
	specparam line_past_front_porch=line_front_porch;
	specparam line_past_sync_pulse=
			line_past_front_porch+line_sync_pulse;
	specparam line_past_back_porch=
			line_past_sync_pulse+line_back_porch;
	specparam line_past_active_video=
			line_past_back_porch+line_active_video;
	// (frame, lines)
	specparam frame_past_front_porch=frame_front_porch;
	specparam frame_past_sync_pulse=
			frame_past_front_porch+frame_sync_pulse;
	specparam frame_past_back_porch=
			frame_past_sync_pulse+frame_back_porch;
	specparam frame_past_active_video=
			frame_past_back_porch+frame_active_video;
	specparam pixels_per_line=line_past_active_video;
	specparam lines_per_frame=frame_past_active_video;

	specparam ticks_per_pixel=clock_freq/pixel_freq;
	specparam pixel_bits=vga_red_bits+vga_green_bits+vga_blue_bits;

	reg [15:0] current_line;
	reg [15:0] current_pixel;
	reg [VRAM_address_lines-1:0] next_read_address;

	reg [pixel_bits-1:0] current_pixel_data;
	reg [pixel_bits-1:0] next_pixel_data;		// 16-bit reads from VRAM
	reg no_next_pixel_in_buffer;
	reg [7:0] next_pixel_timer;
	reg request_new_pixels;

	assign bus_data_lines=voice ?   : 'bz;
	assign bus_sender_device=voice ? bus_device_id : 'bz;
	assign bus_receiver_device=voice ? VRAM_bus_id : 'bz;
	assign bus_write_request=request_new_pixels;
	assign bus_buffer_full=0;

	wire active_video=current_line<frame_past_active_video && current_line>=frame_past_back_porch
		&& current_pixel<line_past_active_video && current_pixel>=line_past_back_porch;
	assign vsync=~(current_line<frame_past_sync_pulse && current_line>=frame_past_front_porch);
	assign hsync=~(current_pixel<line_past_sync_pulse && current_pixel>=line_past_front_porch);

	wire [vga_red_bits-1:0] current_pixel_red=current_pixel_data[pixel_bits-1:pixel_bits-vga_red_bits];
	wire [vga_green_bits-1:0] current_pixel_green=current_pixel_data[pixel_bits-vga_red_bits-1:vga_blue_bits];
	wire [vga_blue_bits-1:0] current_pixel_blue=current_pixel_data[vga_blue_bits-1:0]; 

	assign red=active_video ? current_pixel_red : 0;
	assign green=active_video ? current_pixel_green : 0;
	assign blue=active_video ? current_pixel_blue : 0;

	always @(posedge clk) begin
		if (enable) begin
			if (~next_pixel_timer) begin
				if (current_pixel<pixels_per_line) begin
					current_pixel<=current_pixel+1;
				end
				else begin
					if (current_line<lines_per_frame)
						current_line<=current_line+1;
					else
						current_line<=1;
					current_pixel<=1;
				end
				next_pixel_timer<=ticks_per_pixel-1; // every 4th posedge
				if (~no_next_pixel_in_buffer) begin
					request_new_pixels<=1;
					next_read_address<=(pixels_per_line*current_line+current_pixel+1)/2;
				end
				else begin
					current_pixel_data<=next_pixel_data;
					no_next_pixel_in_buffer<=1;
				end
			end
			else begin
				next_pixel_timer<=next_pixel_timer-1;
				if (request_new_pixels) begin
					
				end
			end
		end
	end
endmodule

