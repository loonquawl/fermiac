module PCM
#(
	data_resolution=8,
)
(
	input [data_resolution-1:0] in,
	input clk,
	output out
);
	reg [data_resolution-1:0] accumulator;
	assign out=accumulator[data_resolution-1];

	always @(clk) begin
		accumulator<=accumulator[7:0]+in;
	end
endmodule

