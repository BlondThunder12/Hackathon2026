// freq_detect.sv — Zero-crossing frequency detector
//
// Receives a 256-byte UART frame of signed 8-bit samples (Fs = 8000 Hz).
// Counts sign changes (zero crossings) across the 256 samples on-the-fly.
// When exactly 256 bytes have been received, computes:
//
//   f = crossings * Fs / (2 * N)
//     = crossings * 8000 / 512
//     = crossings * 15.625 Hz
//
// Integer approximation (no division):
//   f = (crossings * 125) >> 3
//
// Accuracy vs requirement:
//   Bin resolution ≈ 15.6 Hz — well within the ±35 Hz tolerance.
//   (e.g. 100 Hz input → ~6 crossings → 93 Hz detected, Δ = 7 Hz ✓)
//
// Frame synchronisation:
//   Primary:  frame completes after exactly 256 bytes received.
//   Fallback: if a gap of GAP_CLKS with no UART activity is detected
//             mid-frame, the partial frame is discarded (resync).
//             Between frames the gap timer stays asserted; it clears as
//             soon as the next byte arrives.

module freq_detect #(
    parameter int CLK_FREQ   = 50_000_000,
    parameter int GAP_CLKS   = 150_000    // 3 ms at 50 MHz (>> 86 µs/byte gap)
)(
    input  logic        clk,
    input  logic        rst_n,
    // From uart_rx
    input  logic [7:0]  rx_byte,
    input  logic        rx_valid,
    // Outputs
    output logic [7:0]  cross_out,   // last frame's zero-crossing count (debug)
    output logic [10:0] freq_hz,     // detected frequency in Hz (0–2000)
    output logic        freq_valid   // pulses high for one clock when result ready
);

// -----------------------------------------------------------------------
// Gap timer — clears on every received byte; fires after GAP_CLKS of silence
// -----------------------------------------------------------------------
localparam int GAP_W = $clog2(GAP_CLKS + 1);
logic [GAP_W-1:0] gap_ctr;
logic             gap_timeout;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gap_ctr <= '0;
    else if (rx_valid)
        gap_ctr <= '0;
    else if (!gap_timeout)
        gap_ctr <= gap_ctr + 1'b1;
end

assign gap_timeout = (gap_ctr >= GAP_W'(GAP_CLKS - 1));

// -----------------------------------------------------------------------
// Frame state
// -----------------------------------------------------------------------
logic [7:0]  byte_cnt;   // 0..255: position within current frame
logic [7:0]  cross_cnt;  // zero-crossing accumulator for current frame
logic        prev_sign;  // sign bit of the previous sample
logic        in_frame;   // 1 while receiving a frame

// -----------------------------------------------------------------------
// Combinational: zero-crossing detection and frequency calculation
// -----------------------------------------------------------------------
// crossing_now: true if this byte's sign differs from the previous byte.
//   Suppressed on byte 0 (no previous to compare against).
logic        crossing_now;
logic [7:0]  cross_cnt_nxt;  // cross_cnt updated to include current byte
logic [13:0] product;        // cross_cnt_nxt * 125  (max 128*125 = 16000 ≤ 14 bits)
logic [10:0] freq_nxt;       // product >> 3

assign crossing_now  = (byte_cnt != 8'd0) & rx_valid & (rx_byte[7] != prev_sign);
assign cross_cnt_nxt = crossing_now ? cross_cnt + 8'd1 : cross_cnt;
assign product       = (14'(cross_cnt_nxt)) * 14'd125;
assign freq_nxt      = product[13:3];   // divide by 8 = >> 3

// -----------------------------------------------------------------------
// Sequential: frame receive + output update
// -----------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        byte_cnt   <= '0;
        cross_cnt  <= '0;
        prev_sign  <= '0;
        in_frame   <= '0;
        cross_out  <= '0;
        freq_hz    <= '0;
        freq_valid <= '0;
    end else begin
        freq_valid <= 1'b0;

        // ------------------------------------------------------------------
        // Gap timeout: discard partial frame and resync.
        // The condition !rx_valid ensures we don't misfire on the first byte
        // of a new frame that arrives exactly when the timer saturates.
        // ------------------------------------------------------------------
        if (gap_timeout && in_frame && !rx_valid) begin
            byte_cnt  <= '0;
            cross_cnt <= '0;
            in_frame  <= '0;
        end

        // ------------------------------------------------------------------
        // Process incoming byte
        // ------------------------------------------------------------------
        if (rx_valid) begin
            in_frame  <= 1'b1;
            prev_sign <= rx_byte[7];   // always update for next comparison

            if (byte_cnt == 8'd0) begin
                // ---- First byte: initialise, no crossing to count ----
                cross_cnt <= '0;
                byte_cnt  <= 8'd1;

            end else if (byte_cnt == 8'd255) begin
                // ---- 256th byte: compute and output result, then reset ----
                freq_hz    <= freq_nxt;
                cross_out  <= cross_cnt_nxt;
                freq_valid <= 1'b1;
                // Reset for next frame
                byte_cnt   <= '0;
                cross_cnt  <= '0;
                in_frame   <= '0;

            end else begin
                // ---- Bytes 1..254: accumulate crossings ----
                cross_cnt <= cross_cnt_nxt;
                byte_cnt  <= byte_cnt + 8'd1;
            end
        end
    end
end

endmodule
