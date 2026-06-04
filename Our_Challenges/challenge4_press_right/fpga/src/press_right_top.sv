// Challenge 4: Press Right — FPGA top module (DE10-Lite / MAX10)
// Counter increments every 10 ms. KEY[0] starts, KEY[0] again stops.
// Stopped value sent to ESP32 over UART. LEDs show proximity to 1000.

module press_right_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,          // active-low pushbuttons
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output logic        UART_TX       // to ESP32 ARDUINO_IO[1] / GPIO16-RX
);

    // -------------------------------------------------------------------
    // 10 ms tick — 500 000 cycles @ 50 MHz
    // -------------------------------------------------------------------
    logic [18:0] tick_ctr;
    logic        tick;

    always_ff @(posedge MAX10_CLK1_50) begin
        if (tick_ctr == 19'd499_999) begin
            tick_ctr <= '0;
            tick     <= 1;
        end else begin
            tick_ctr <= tick_ctr + 1;
            tick     <= 0;
        end
    end

    // -------------------------------------------------------------------
    // KEY[0] debounce — 20 ms (1 000 000 cycles)
    // k0_press: one-cycle pulse on falling edge (key pressed)
    // -------------------------------------------------------------------
    logic [1:0]  k0_sync;
    logic [19:0] k0_cnt;
    logic        k0_db, k0_prev, k0_press;

    always_ff @(posedge MAX10_CLK1_50) begin
        k0_sync <= {k0_sync[0], KEY[0]};

        if (k0_sync[1] == k0_db) begin
            k0_cnt <= '0;
        end else begin
            if (k0_cnt == 20'd999_999) begin
                k0_db  <= k0_sync[1];
                k0_cnt <= '0;
            end else
                k0_cnt <= k0_cnt + 1;
        end

        k0_prev  <= k0_db;
        k0_press <= k0_prev & ~k0_db;  // falling edge = key pressed
    end

    // -------------------------------------------------------------------
    // Game state machine
    // -------------------------------------------------------------------
    typedef enum logic [1:0] { IDLE, RUNNING, STOPPED } game_state_t;
    game_state_t game_state;

    logic [13:0] counter;
    logic [13:0] stopped_val;
    logic        send_trigger;   // one-cycle pulse → UART controller

    always_ff @(posedge MAX10_CLK1_50) begin
        send_trigger <= 0;
        case (game_state)
            IDLE: if (k0_press) begin
                counter    <= '0;
                game_state <= RUNNING;
            end

            RUNNING: begin
                if (tick)
                    counter <= (counter == 14'd9999) ? '0 : counter + 1;
                if (k0_press) begin
                    stopped_val  <= counter;
                    send_trigger <= 1;
                    game_state   <= STOPPED;
                end
            end

            STOPPED: if (k0_press) begin
                counter    <= '0;
                game_state <= RUNNING;
            end

            default: game_state <= IDLE;
        endcase
    end

    // -------------------------------------------------------------------
    // UART TX controller — sends stopped_val as 2 bytes: hi then lo
    // Uses tx_done (falling edge of tx_busy) to sequence bytes safely.
    // -------------------------------------------------------------------
    logic [7:0] tx_data_reg;
    logic       tx_start_r;
    logic       tx_busy_sig, tx_busy_prev, tx_done;

    always_ff @(posedge MAX10_CLK1_50)
        tx_busy_prev <= tx_busy_sig;

    assign tx_done = tx_busy_prev & ~tx_busy_sig;

    typedef enum logic [1:0] { UTX_IDLE, UTX_B0, UTX_B1, UTX_SPARE } utx_t;
    utx_t utx_state;

    always_ff @(posedge MAX10_CLK1_50) begin
        tx_start_r <= 0;
        case (utx_state)
            UTX_IDLE: if (send_trigger) begin
                tx_data_reg <= {2'b00, stopped_val[13:8]};
                tx_start_r  <= 1;
                utx_state   <= UTX_B0;
            end

            UTX_B0: if (tx_done) begin
                tx_data_reg <= stopped_val[7:0];
                tx_start_r  <= 1;
                utx_state   <= UTX_B1;
            end

            UTX_B1: if (tx_done)
                utx_state <= UTX_IDLE;

            default: utx_state <= UTX_IDLE;
        endcase
    end

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(9600)) u_tx (
        .clk     (MAX10_CLK1_50),
        .rst_n   (1'b1),
        .tx_start(tx_start_r),
        .tx_data (tx_data_reg),
        .tx_busy (tx_busy_sig),
        .tx_out  (UART_TX)
    );

    // -------------------------------------------------------------------
    // 7-segment display — show counter while running, stopped_val after
    // -------------------------------------------------------------------
    logic [13:0] disp_val;
    always_comb
        case (game_state)
            RUNNING: disp_val = counter;
            STOPPED: disp_val = stopped_val;
            default: disp_val = '0;
        endcase

    logic [13:0] rem3, rem2;
    logic [3:0]  d3, d2, d1, d0;
    always_comb begin
        d3   = disp_val / 1000;
        rem3 = disp_val % 1000;
        d2   = rem3 / 100;
        rem2 = rem3 % 100;
        d1   = rem2 / 10;
        d0   = rem2 % 10;
    end

    logic [7:0] seg0, seg1, seg2, seg3;
    seven_segment s0(.value(d0), .segments(seg0));
    seven_segment s1(.value(d1), .segments(seg1));
    seven_segment s2(.value(d2), .segments(seg2));
    seven_segment s3(.value(d3), .segments(seg3));

    assign HEX0 = seg0[6:0];
    assign HEX1 = seg1[6:0];
    assign HEX2 = seg2[6:0];
    assign HEX3 = seg3[6:0];
    assign HEX4 = 7'h7F;   // blank
    assign HEX5 = 7'h7F;   // blank

    // -------------------------------------------------------------------
    // LED proximity — more LEDs lit = closer to target 1000
    // Only active in STOPPED state; clears on next run.
    // -------------------------------------------------------------------
    logic [13:0] diff;
    always_comb begin
        diff = (stopped_val >= 14'd1000)
               ? (stopped_val - 14'd1000)
               : (14'd1000 - stopped_val);

        if      (game_state != STOPPED) LEDR = 10'b00_0000_0000;
        else if (diff <= 10)            LEDR = 10'b11_1111_1111; // WIN ±10
        else if (diff <= 50)            LEDR = 10'b01_1111_1111;
        else if (diff <= 100)           LEDR = 10'b00_1111_1111;
        else if (diff <= 200)           LEDR = 10'b00_0111_1111;
        else if (diff <= 300)           LEDR = 10'b00_0011_1111;
        else if (diff <= 500)           LEDR = 10'b00_0001_1111;
        else if (diff <= 700)           LEDR = 10'b00_0000_1111;
        else if (diff <= 1000)          LEDR = 10'b00_0000_0111;
        else if (diff <= 2000)          LEDR = 10'b00_0000_0011;
        else if (diff <= 4000)          LEDR = 10'b00_0000_0001;
        else                            LEDR = 10'b00_0000_0000;
    end

endmodule
