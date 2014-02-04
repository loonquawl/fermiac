module uart_tx
#(
	parameter	clock_speed=100_000_000,
	parameter	baud_rate=115200
)
(
	output	reg			tx,
	input				clk,
	input		[7:0][63:0]	data_buffer,
	input				endianness,	// 1: big, 0: little
	input				proceed,
	input		[19:0]		skipcycles,	// keep it clock_speed/baud_rate-1
	output	reg	[2:0]		bytepos,
	output	reg	[5:0]		bufferpos,
	output	reg			bytestart,
	output	reg			byteend
);
	initial tx=1;
	initial bytepos=0;
	initial bufferpos=0;
	initial bytastart=1;
	initial byteend=0;

	reg [19:0] clkdivcnt=0;
	reg preamble=1;		// UART high before or low after every byte

	always @(posedge clk) begin
		clkdivcnt<=proceed? clkdivcnt+1 : 0;
		if (clkdivcnt==skip) begin
			clkdivcnt<=0;
			// UART
			tx<=data_buffer[bytepos][bufferpos];
			bytepos<=bytepos==7? 0 : bytepos+1;
			bufferpos<=bufferpos==63? 0 : bytepos==7? bufferpos+1 : bufferpos;
		end
	end
endmodule

