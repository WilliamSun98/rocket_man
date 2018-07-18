module week3_5(
	input			CLOCK_50,
	input	[9:0]	SW,
	input	[3:0]	KEY,
	output	[6:0]	HEX0, HEX1, HEX2, HEX3,
	output	[9:0]	LEDR,

	// Declare your inputs and outputs here
	// Do not change the following outputs
	output			VGA_CLK,   				//	VGA Clock
	output			VGA_HS,					//	VGA H_SYNC
	output			VGA_VS,					//	VGA V_SYNC
	output			VGA_BLANK_N,			//	VGA BLANK
	output			VGA_SYNC_N,				//	VGA SYNC
	output	[9:0]	VGA_R,   				//	VGA Red[9:0]
	output	[9:0]	VGA_G,	 				//	VGA Green[9:0]
	output	[9:0]	VGA_B   				//	VGA Blue[9:0]
	);

	wire resetn;
	assign resetn = KEY[0];
	
	// Create the colour, x, y wires that are inputs to the controller.
	wire [2:0] colour;
	wire [7:0] x;
	wire [6:0] y;

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(resetn),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(1),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "black.mif";

	// those are feedback signal send from datapath to control
	wire finish_jump, finish_reset, finish_check;
	// those are signals send to control to start work
	wire start, count, move, check, reset;

	// connect each state to one LEDR for tracing the state
	assign LEDR[0] = start;
	assign LEDR[1] = count;
	assign LEDR[2] = move;
	assign LEDR[3] = check;
	assign LEDR[4] = reset;

	// connect the energy to hex display to view the energy
	wire [7:0] energy;
	wire [7:0] score;
	
	hex_display least(
			.IN(energy[3:0]),
			.OUT(HEX0[6:0])
			);
			
	hex_display most(
			.IN(energy[7:4]),
			.OUT(HEX1[6:0])
			);

	hex_display score_display1(
			.IN(score[3:0]),
			.OUT(HEX2[6:0])
			);
	
	hex_display score_display2(
	        .IN(score[7:4]),
	        .OUT(HEX3[6:0])
	        );

	// control is here
	control c0(
		.clk(CLOCK_50),
		.jump(SW[0]),
		.finish_jump(finish_jump),
		.finish_reset(finish_reset),
		.finish_check(finish_check),
		.start(start),
		.count(count),
		.move(move),
		.check(check),
		.reset(reset)
		);

	// datapath is here
	datapath d0(
		.clk(CLOCK_50),
		.start(start),
		.count(count),
		.move(move),
		.check(check),
		.reset(reset),
		.x(x),
		.y(y),
		.finish_jump(finish_jump),
		.finish_reset(finish_reset),
		.finish_check(finish_check),
		.colour(colour),
		.energy(energy),
		.score(score)
		);
 
endmodule

module control(
	input clk,
	input jump,
	input finish_jump,
	input finish_reset,
	input finish_check,
	output reg start, count, move, check, reset
	);

	reg [2:0] current_state, next_state;

	localparam	S_START 		= 3'd0,
				S_COUNT 		= 3'd1,
				S_JUMP			= 3'd2,
				S_CHECK			= 3'd3,
				S_RESET			= 3'd4;

	always @(*)
	begin: state_table
		case(current_state)
			S_START: next_state = jump ? S_COUNT : S_START;
			S_COUNT: next_state = jump ? S_COUNT : S_JUMP;
			S_JUMP: next_state = finish_jump ? S_CHECK : S_JUMP;
			S_CHECK: next_state = finish_check ? S_RESET : S_CHECK;
			S_RESET: next_state = finish_reset ? S_START : S_RESET;
			default: next_state = S_START;
		endcase
	end

	always @(*)
	begin: send_signals
		start = 1'b0;
		count = 1'b0;
		move = 1'b0;
		check = 1'b0;
		reset = 1'b0;

		case (current_state)
			S_START: begin
				start = 1'b1;
			end
			S_COUNT: begin
				count = 1'b1;
			end
			S_JUMP: begin
				move = 1'b1;
			end
			S_CHECK: begin
				check = 1'b1;
			end
			S_RESET: begin
				reset = 1'b1;
			end
			default: begin
			end
		endcase

	end

	always @(posedge clk) begin
		current_state <= next_state;
	end
endmodule

module datapath(
	input clk,
	input start,
	input count,
	input move,
	input reset,
	input check,
	output reg [7:0] x, energy,
	output reg [6:0] y,
	output reg [2:0] colour,
	output reg finish_jump = 0, finish_reset = 0, finish_check = 0,
	output reg [7:0] score = 0
	);
	wire enable_energy, enable_move;
	reg write, going_up;
	reg [7:0] init_x = 8'd30;
	reg [6:0] init_y = 7'd85;
	reg [7:0] tmp_x;
	reg [6:0] tmp_y;
	reg [99:0] platform= 100'b1111111111000000000000000000000000000000000000000000000000000000000000000000000000000000001111111111;
	reg [99:0] subpf;
	reg [7:0] counter = 8'd0, board_counter = 8'd0, length_counter = 8'd0;
	reg [107:0] randtree = 108'b010010000000011000100101011001111000000101000101001101110000001101001000001001100000001101110001001000010101;
	reg [3:0] randnum;

	rate_divisor clk_energy(clk, enable_energy, 28'd5_000_000, 1'b1);
	rate_divisor clk_move(clk, enable_move, 28'd2_500_000, 1'b1);
	
	always @(posedge clk) begin
		randnum <= randtree[107:104];
		if (start) begin
			// reset every value and the dot character
			if (board_counter == 8'd0) begin
				counter <= 8'd0;
				write <= 0;
				finish_jump <= 0;
				finish_reset <= 0;
				finish_check <= 0;
				x <= init_x;
				y <= init_y;
				going_up <= 1;
				colour <= 3'b100;
				energy <= 0;
				board_counter <= 8'd1;
				randtree[107:0] <= {randtree[103:0], randtree[107:104]};
				subpf <= {platform[99:90], platform[90:0] << (10 * randnum)};
				platform= 100'b1111111111000000000000000000000000000000000000000000000000000000000000000000000000000000001111111111;
			end
			// reset the platform
			else if (board_counter < 8'd101) begin
				x <= init_x + board_counter - 8'd5;
				y <= init_y + 8'd1;
				colour <= (subpf[99] == 1'b1) ? 3'b110 : 3'b000;
				length_counter <= (subpf[99] == 1'b1) ? (board_counter - 8'd10) : length_counter;
				board_counter <= board_counter + 8'd1;
				subpf <= subpf << 1;
			end
			// reset bonus point
			else if (board_counter == 8'd101) begin  //bonus target
				x <= init_x + (length_counter / 2);
				y <= init_y - (length_counter / 2);
				colour <= 3'b011;
			end
		end
		// count for energy
		else if (count) begin
			if (enable_energy) begin
				if (energy == 8'd100)
					energy <= 0;
				else
					energy <= energy + 8'd1;
			end
			else begin
				energy <= energy;
			end
			// reset coordinate for x and y
			x <= init_x;
			y <= init_y;
			colour <= 3'b100;
		end
		else if (move) begin
			// move based on energy
			if (counter < energy) begin
				if (enable_move) begin
					colour <= 3'b000;
					write <= 1'b1;
				end
				else if (write) begin
					x <= x + 1;
					y <= (going_up) ? y - 1 : y + 1;
					colour <= 3'b100;
					write <= 0;
					counter <= counter + 1;
					going_up <= (counter >= energy / 2) ? 0 : 1;
				end
				else begin
				end
			end
			// if energy is even so adjust the height
			else begin
				if (y != init_y) begin
					if (enable_move) begin
						colour <= 3'b000;
						write <= 1'b1;
					end
					else if (write) begin
						y <= init_y;
						colour <= 3'b100;
						write <= 0;
					end
					else begin
					end
				end
				else begin
					finish_jump <= 1;
					finish_reset <= 0;
					finish_check <= 0;
				end
			end
		end
		// check if jumped into the platform
		else if (check) begin
			if ((score < 100) && ((x >= init_x + length_counter) && ( init_x + length_counter + 5 >= x))) begin
				score <= score + 4'd2;
			end
			else if ((score < 100) && ((x >= init_x + length_counter - 5) && ( init_x + length_counter > x))) begin
				score <= score + 4'd1;
			end
			else begin
				score <= 4'd0;
			end
			finish_check <= 1;
			finish_reset <= 0;
			finish_jump <= 0;
		end
		// moving dot back to original position
		else if (reset) begin
			if (x != init_x) begin
				if (enable_move) begin
					colour <= 3'b000;
					write <= 1;
				end
				else if (write) begin
					x <= x - 1;
					colour <= 3'b100;
					write <= 0;
				end
			end
			// black the bonus
			else begin
				finish_jump <= 0;
				finish_reset <= 1;
				finish_check <= 0;
				board_counter <= 8'd0;
				x <= init_x + (length_counter / 2);
				y <= init_y - (length_counter / 2); 
				colour <= 3'b000;
				length_counter <= 0;
			end
		end
		else begin
		end
	end
endmodule

module rate_divisor(clk_in, clk_out, max, clear);
	input clk_in, clear;
	input [27:0] max;
	output clk_out;

	reg [27:0] counter = 28'd0;

	always @(posedge clk_in or negedge clear)
	begin
		if (~clear) begin
			counter <= 28'd0;
		end
		else if (counter >= max - 28'd1) begin
			counter <= 28'd0;
		end
		else begin
			counter <= counter + 28'd1;
		end
	end

	assign clk_out = (counter == 28'd0) ? 1 : 0;

endmodule

module hex_display(IN, OUT);
    input [3:0] IN;
	output reg [6:0] OUT;
	 
	always @(*)
	begin
		case(IN[3:0])
			4'b0000: OUT = 7'b1000000;
			4'b0001: OUT = 7'b1111001;
			4'b0010: OUT = 7'b0100100;
			4'b0011: OUT = 7'b0110000;
			4'b0100: OUT = 7'b0011001;
			4'b0101: OUT = 7'b0010010;
			4'b0110: OUT = 7'b0000010;
			4'b0111: OUT = 7'b1111000;
			4'b1000: OUT = 7'b0000000;
			4'b1001: OUT = 7'b0011000;
			4'b1010: OUT = 7'b0001000;
			4'b1011: OUT = 7'b0000011;
			4'b1100: OUT = 7'b1000110;
			4'b1101: OUT = 7'b0100001;
			4'b1110: OUT = 7'b0000110;
			4'b1111: OUT = 7'b0001110;
			
			default: OUT = 7'b0111111;
		endcase

	end
endmodule
