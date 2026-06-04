// freq_detector_top.sv — DE10-Lite top-level for Challenge 6: Frequency Detector
//
// The ESP32 generates a 256-sample signed sine wave at the frequency set by
// the potentiometer (100–2000 Hz, Fs = 8000 Hz) and streams the raw bytes to
// the FPGA over UART at 115200 baud.  This module receives the bytes, counts
// zero crossings, and computes:
//
//   detected_Hz = zero_crossings * 125 / 8
//
// Display (normal mode, SW[9] = 0):
//   HEX3..HEX0 → frequency in Hz, e.g. "1085"
//   LEDR[9:0]  → LED bar: LEDR[i] lights when freq ≥ (100 + i*200) Hz
//
// Display (debug mode, SW[9] = 1):
//   HEX2..HEX0 → raw zero-crossing count (0–128)
//   HEX3       → blank
//   LEDR       → unchanged
//
// Wiring:
//   ESP32 GPIO16 (UART2 TX) → FPGA ARDUINO_IO[0] (PIN_AB5)
//   ESP32 GND               → Arduino header GND
//
// Reset: KEY[0] active-low

module freq_detector_top (
    input  logic        MAX10_CLK1_50,
    input  logic [9:0]  SW,
    input  logic [1:0]  KEY,
    output logic [9:0]  LEDR,
    output logic [7:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    inout  logic [15:0] ARDUINO_IO,
    inout  logic        ARDUINO_RESET_N
);

// ── Reset ────────────────────────────────────────────────────────────────
logic rst_n;
assign rst_n = KEY[0];

// ── ARDUINO_IO: drive all unused pins high-Z ─────────────────────────────
// ARDUINO_IO[0] is the FPGA UART RX input (driven by ESP32 — not assigned here).
assign ARDUINO_IO[15:1] = 15'bz;
assign ARDUINO_RESET_N  = 1'bz;

// ── UART receiver at 115200 baud ─────────────────────────────────────────
logic [7:0] rx_byte;
logic       rx_valid;

uart_rx #(
    .CLK_FREQ  (50_000_000),
    .BAUD_RATE (115_200)
) u_uart (
    .clk   (MAX10_CLK1_50),
    .rst_n (rst_n),
    .rx    (ARDUINO_IO[0]),
    .data  (rx_byte),
    .valid (rx_valid)
);

// ── Zero-crossing frequency detector ────────────────────────────────────
logic [7:0]  cross_out;
logic [10:0] freq_hz;
logic        freq_valid;

freq_detect #(
    .CLK_FREQ (50_000_000),
    .GAP_CLKS (150_000)
) u_det (
    .clk       (MAX10_CLK1_50),
    .rst_n     (rst_n),
    .rx_byte   (rx_byte),
    .rx_valid  (rx_valid),
    .cross_out (cross_out),
    .freq_hz   (freq_hz),
    .freq_valid(freq_valid)
);

// ── Hold last valid result (stable display between frames) ──────────────
logic [10:0] freq_reg;
logic [7:0]  cross_reg;

always_ff @(posedge MAX10_CLK1_50 or negedge rst_n) begin
    if (!rst_n) begin
        freq_reg  <= '0;
        cross_reg <= '0;
    end else if (freq_valid) begin
        freq_reg  <= freq_hz;
        cross_reg <= cross_out;
    end
end

// ── BCD conversion — frequency (0–2000 Hz, 4 digits) ────────────────────
logic [3:0] f_th, f_h, f_t, f_o;

bin_to_bcd4 #(.BIN_W(11)) u_bcd_freq (
    .bin      (freq_reg),
    .thousands(f_th),
    .hundreds (f_h),
    .tens     (f_t),
    .ones     (f_o)
);

// ── BCD conversion — crossing count (0–128, 3 digits) ───────────────────
logic [3:0] c_h, c_t, c_o;

bin_to_bcd #(.BIN_W(8)) u_bcd_cross (
    .bin     (cross_reg),
    .hundreds(c_h),
    .tens    (c_t),
    .ones    (c_o)
);

// ── Seven-segment drivers ────────────────────────────────────────────────
// Frequency digits
logic [7:0] seg_fth, seg_fh, seg_ft, seg_fo;
seg7_dec u_fth (.digit(f_th), .dp_on(1'b0), .segments(seg_fth));
seg7_dec u_fh  (.digit(f_h),  .dp_on(1'b0), .segments(seg_fh));
seg7_dec u_ft  (.digit(f_t),  .dp_on(1'b0), .segments(seg_ft));
seg7_dec u_fo  (.digit(f_o),  .dp_on(1'b0), .segments(seg_fo));

// Crossing count digits
logic [7:0] seg_ch, seg_ct, seg_co;
seg7_dec u_ch  (.digit(c_h), .dp_on(1'b0), .segments(seg_ch));
seg7_dec u_ct  (.digit(c_t), .dp_on(1'b0), .segments(seg_ct));
seg7_dec u_co  (.digit(c_o), .dp_on(1'b0), .segments(seg_co));

localparam logic [7:0] SEG_BLANK = 8'hFF; // all segments OFF (active-low)

// ── Display mux (SW[9]: 0 = normal, 1 = debug) ──────────────────────────
always_comb begin
    HEX5 = SEG_BLANK;
    HEX4 = SEG_BLANK;

    if (!SW[9]) begin
        // ---- Normal: show frequency Hz on HEX3..HEX0 ----
        // Suppress leading thousands digit when freq < 1000 Hz
        HEX3 = (f_th == 4'd0) ? SEG_BLANK : seg_fth;
        HEX2 = seg_fh;
        HEX1 = seg_ft;
        HEX0 = seg_fo;
    end else begin
        // ---- Debug: show zero-crossing count on HEX2..HEX0 ----
        HEX3 = SEG_BLANK;
        HEX2 = (c_h == 4'd0) ? SEG_BLANK : seg_ch; // suppress hundreds if 0
        HEX1 = seg_ct;
        HEX0 = seg_co;
    end
end

// ── LED bar graph — frequency band ──────────────────────────────────────
// LEDR[i] lights when freq >= (100 + i*200) Hz:
//   LEDR[0]: >= 100 Hz   (any signal)
//   LEDR[1]: >= 300 Hz
//   ...
//   LEDR[9]: >= 1900 Hz
always_comb begin
    for (int i = 0; i < 10; i++) begin
        LEDR[i] = (freq_reg >= 11'(100 + i * 200));
    end
end

endmodule
