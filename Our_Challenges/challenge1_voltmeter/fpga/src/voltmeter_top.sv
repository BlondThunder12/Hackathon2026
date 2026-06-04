// voltmeter_top.sv — DE10-Lite top-level for Challenge 5: Digital Voltmeter
//
// Display layout (HEX2 is left, HEX0 is right):
//   HEX2 = units digit  (+ decimal point intent, see seg7_dec.sv note)
//   HEX1 = tenths digit
//   HEX0 = hundredths digit
// Example: 3.30 V → HEX2="3.", HEX1="3", HEX0="0"
//
// Wiring:
//   ESP32 GPIO17 (UART2 TX) → FPGA ARDUINO_IO[0] = UART_RXD (PIN_V10)
//   Common GND between ESP32 and FPGA Arduino header

module voltmeter_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,           // KEY[0] = active-low reset
    input  logic        UART_RXD,      // from ESP32 GPIO17
    output logic [6:0]  HEX0,          // hundredths digit
    output logic [6:0]  HEX1,          // tenths digit
    output logic [7:0]  HEX2,          // units digit; [7] = decimal point
    output logic [6:0]  HEX3,          // unused — blank
    output logic [6:0]  HEX4,          // unused — blank
    output logic [6:0]  HEX5,          // unused — blank
    output logic [9:0]  LEDR           // bar-graph LEDs
);

logic        rst_n;
logic [7:0]  rx_byte;
logic        rx_valid;
logic [8:0]  voltage_raw;
logic        voltage_valid;
logic [8:0]  voltage_reg;
logic [3:0]  bcd_h, bcd_t, bcd_o;
logic [7:0]  seg_h, seg_t, seg_o;

assign rst_n = KEY[0];

// ── UART byte receiver ──────────────────────────────────────
uart_rx #(
    .CLK_FREQ  (50_000_000),
    .BAUD_RATE (115_200)
) u_uart (
    .clk   (MAX10_CLK1_50),
    .rst_n (rst_n),
    .rx    (UART_RXD),
    .data  (rx_byte),
    .valid (rx_valid)
);

// ── Two-byte packet assembler ───────────────────────────────
packet_rx u_pkt (
    .clk          (MAX10_CLK1_50),
    .rst_n        (rst_n),
    .byte_data    (rx_byte),
    .byte_valid   (rx_valid),
    .voltage_int  (voltage_raw),
    .voltage_valid(voltage_valid)
);

// ── Hold last valid reading (stable display between packets) ─
always_ff @(posedge MAX10_CLK1_50 or negedge rst_n) begin
    if (!rst_n)             voltage_reg <= '0;
    else if (voltage_valid) voltage_reg <= voltage_raw;
end

// ── Binary → BCD ────────────────────────────────────────────
bin_to_bcd #(.BIN_W(9)) u_bcd (
    .bin     (voltage_reg),
    .hundreds(bcd_h),
    .tens    (bcd_t),
    .ones    (bcd_o)
);

// ── 7-segment decoders ───────────────────────────────────────
seg7_dec u_hex2 (.digit(bcd_h), .dp_on(1'b1), .segments(seg_h)); // DP always ON
seg7_dec u_hex1 (.digit(bcd_t), .dp_on(1'b0), .segments(seg_t));
seg7_dec u_hex0 (.digit(bcd_o), .dp_on(1'b0), .segments(seg_o));

assign HEX2 = seg_h;        // full 8 bits — [7]=DP (0=ON, active-low) → PIN_B15
assign HEX1 = seg_t[6:0];
assign HEX0 = seg_o[6:0];

// ── HEX2 Decimal Point (active-low: 0 = ON always) ──────────
// HEX2_DP removed — DP is now driven through HEX2[7] on PIN_B15

// Blank unused displays (all segments off = all pins high)
assign HEX3 = 7'h7F;
assign HEX4 = 7'h7F;
assign HEX5 = 7'h7F;

// ── LED bar graph ────────────────────────────────────────────
led_bargraph u_bar (
    .voltage_int(voltage_reg),
    .leds       (LEDR)
);

endmodule
