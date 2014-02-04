/* verilator lint_off WIDTH */

module FIFO
#(
	parameter data_width=32,
	parameter size=32,
	parameter device_id=1
)
(
	input [data_width-1:0] data_in		/*verilator public*/,
	output [data_width-1:0] data_out	/*verilator public*/,
	input clk				/*verilator public*/,
	input next				/*verilator public*/,
	input insert				/*verilator public*/,
	input clear				/*verilator public*/,
	output full				/*verilator public*/,
	output empty				/*verilator public*/
);
	reg [data_width-1:0] mem[size];
	reg [9:0] words_inside=0;

	assign data_out=mem[0];
	assign full=words_inside==size;
	assign empty=words_inside==0;

	always @(posedge clk) begin
		if (!(insert&&next)) begin
			if (clear)
				words_inside<=0;
			else if (insert && ~full)
				words_inside<=words_inside+1;
			else if (next && ~empty)
				words_inside<=words_inside-1;
		end
	end

	generate
		genvar pos;
		for (pos=0; pos<size; pos=pos+1) begin: registers
			always @(posedge clk) begin
				mem[pos]<=
					insert^next?
						insert && words_inside==pos?
							data_in
						:
							next?
								pos+1!=size?
									mem[pos+1]
								:
									0
							:
								mem[pos]
					:
						insert&&next?
							// -1 : location of
							// the last word
							pos<words_inside-1?
								mem[pos+1]
							:
								data_in
						:
							mem[pos];
				// I'm so sorry... This evil language
				// made me do it.
			end
		end
	endgenerate
endmodule

