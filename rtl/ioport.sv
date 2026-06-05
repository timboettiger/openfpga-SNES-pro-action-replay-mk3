
module ioport
(
	input        CLK,

	input        MULTITAP,

	input        PORT_LATCH,
	input        PORT_CLK,
	input        PORT_P6,
	output [1:0] PORT_DO,

	input	[11:0] JOYSTICK1,
	input	[11:0] JOYSTICK2,
	input	[11:0] JOYSTICK3,
	input	[11:0] JOYSTICK4,

	input [7:0]  JOY_X,
	input [7:0]  JOY_Y,

	input [7:0]  DPAD_AIM_SPEED,

	input        MOUSE_EN,

	// Real mouse (cont4): [50] present [49] R [48] L
	// [47:32] counter [31:16] dy [15:0] dx
	input [50:0] MOUSE_DATA
);

assign PORT_DO = {(JOY_LATCH1[15] & ~PORT_LATCH) | ~MULTITAP, MOUSE_EN ? MS_LATCH[31] : JOY_LATCH0[15]};

wire [11:0] JOYSTICK[4] = '{JOYSTICK1,JOYSTICK2,JOYSTICK3,JOYSTICK4};

wire JOYn = ~PORT_P6 & MULTITAP;

wire [15:0] JOY0 = {JOYSTICK[{JOYn,1'b0}][5],  JOYSTICK[{JOYn,1'b0}][7],
                    JOYSTICK[{JOYn,1'b0}][10], JOYSTICK[{JOYn,1'b0}][11],
                    JOYSTICK[{JOYn,1'b0}][3],  JOYSTICK[{JOYn,1'b0}][2],
                    JOYSTICK[{JOYn,1'b0}][1],  JOYSTICK[{JOYn,1'b0}][0],
                    JOYSTICK[{JOYn,1'b0}][4],  JOYSTICK[{JOYn,1'b0}][6],
                    JOYSTICK[{JOYn,1'b0}][8],  JOYSTICK[{JOYn,1'b0}][9], 4'b0000};

wire [15:0] JOY1 = {JOYSTICK[{JOYn,1'b1}][5],  JOYSTICK[{JOYn,1'b1}][7],
                    JOYSTICK[{JOYn,1'b1}][10], JOYSTICK[{JOYn,1'b1}][11],
                    JOYSTICK[{JOYn,1'b1}][3],  JOYSTICK[{JOYn,1'b1}][2],
                    JOYSTICK[{JOYn,1'b1}][1],  JOYSTICK[{JOYn,1'b1}][0],
                    JOYSTICK[{JOYn,1'b1}][4],  JOYSTICK[{JOYn,1'b1}][6],
                    JOYSTICK[{JOYn,1'b1}][8],  JOYSTICK[{JOYn,1'b1}][9], 4'b0000};

// Gamepads
reg [15:0] JOY_LATCH0;
always @(posedge CLK) begin
	reg old_clk, old_n;
	old_clk <= PORT_CLK;
	old_n <= JOYn;
	if(PORT_LATCH | (~old_n & JOYn)) JOY_LATCH0 <= ~JOY0;
	else if (~old_clk & PORT_CLK) JOY_LATCH0 <= JOY_LATCH0 << 1;
end

reg [15:0] JOY_LATCH1;
always @(posedge CLK) begin
	reg old_clk, old_n;
	old_clk <= PORT_CLK;
	old_n <= JOYn;
	if(PORT_LATCH | (~old_n & JOYn)) JOY_LATCH1 <= ~JOY1;
	else if (~old_clk & PORT_CLK) JOY_LATCH1 <= JOY_LATCH1 << 1;
end

// Virtual mouse (D-pad / stick)
wire dpad_mouse_sdy = JOYSTICK1[3];
wire dpad_mouse_sdx = JOYSTICK1[1];
wire [6:0] dpad_mouse_dy = JOYSTICK1[3] | JOYSTICK1[2] ? DPAD_AIM_SPEED[6:0] : 7'd0;
wire [6:0] dpad_mouse_dx = JOYSTICK1[0] | JOYSTICK1[1] ? DPAD_AIM_SPEED[6:0] : 7'd0;
wire joy_mouse_sdy = ~JOY_Y[7];
wire joy_mouse_sdx = ~JOY_X[7];
wire [6:0] joy_mouse_dy = joy_mouse_sdy ? (8'd128-JOY_Y) >> 4 : (JOY_Y[6:0]) >> 4;
wire [6:0] joy_mouse_dx = joy_mouse_sdx ? (8'd128-JOY_X) >> 4 : (JOY_X[6:0]) >> 4;
wire mouse_left = JOYSTICK1[5];
wire mouse_right = JOYSTICK1[4];

// Real mouse (cont4)
wire               ms_present = MOUSE_DATA[50];
wire               ms_r       = MOUSE_DATA[49];
wire               ms_l       = MOUSE_DATA[48];
wire signed [15:0] ms_dx      = MOUSE_DATA[15:0];
wire signed [15:0] ms_dy      = MOUSE_DATA[31:16];

// Sum cont4 deltas per report (new report = delta value changed), clear on
// read. Sign + 7-bit magnitude.
reg  signed [15:0] ms_acc_x, ms_acc_y;
reg  signed [15:0] ms_dx_prev, ms_dy_prev;
wire               ms_new = (ms_dx != ms_dx_prev) || (ms_dy != ms_dy_prev);
wire        [15:0] ms_absx = ms_acc_x[15] ? (~ms_acc_x + 16'sd1) : ms_acc_x;
wire        [15:0] ms_absy = ms_acc_y[15] ? (~ms_acc_y + 16'sd1) : ms_acc_y;
wire         [6:0] ms_mx   = (ms_absx > 16'd127) ? 7'd127 : ms_absx[6:0];
wire         [6:0] ms_my   = (ms_absy > 16'd127) ? 7'd127 : ms_absy[6:0];
wire               ms_sx   = ms_acc_x[15];
wire               ms_sy   = ms_acc_y[15];

reg joystick_detected = 0;
reg  [1:0] speed = 0;
reg [31:0] MS_LATCH;
always @(posedge CLK) begin
	reg old_clk, old_latch;

	old_clk <= PORT_CLK;
	old_latch <= PORT_LATCH;

	if (JOY_Y || JOY_X)
		joystick_detected <= 1'b1;

	if (!ms_present) begin
		ms_acc_x   <= 16'sd0;
		ms_acc_y   <= 16'sd0;
		ms_dx_prev <= ms_dx;
		ms_dy_prev <= ms_dy;
	end else if (ms_new) begin
		ms_dx_prev <= ms_dx;
		ms_dy_prev <= ms_dy;
		ms_acc_x   <= ms_acc_x + ms_dx;
		ms_acc_y   <= ms_acc_y + ms_dy;
	end

	if(old_latch & ~PORT_LATCH) begin
		if (ms_present) begin
			MS_LATCH <= ~{8'h00, ms_r, ms_l, speed, 4'b0001, ms_sy, ms_my, ms_sx, ms_mx};
			// clear; carry a delta seen this cycle
			ms_acc_x <= ms_new ? ms_dx : 16'sd0;
			ms_acc_y <= ms_new ? ms_dy : 16'sd0;
		end else if(joystick_detected && (joy_mouse_dy + joy_mouse_dx > 0)) begin
			MS_LATCH <= ~{8'h00, mouse_left, mouse_right, speed, 4'b0001, joy_mouse_sdy, joy_mouse_dy, joy_mouse_sdx, joy_mouse_dx};
		end else begin
			MS_LATCH <= ~{8'h00, mouse_left, mouse_right, speed, 4'b0001, dpad_mouse_sdy, dpad_mouse_dy, dpad_mouse_sdx, dpad_mouse_dx};
		end
	end

	if(~old_clk & PORT_CLK) begin
		if(PORT_LATCH) begin
			speed <= speed + 1'd1;
			if(speed == 2) speed <= 0;
		end
		else MS_LATCH <= MS_LATCH << 1;
	end
end

endmodule
