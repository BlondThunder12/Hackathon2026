// Challenge 8: PC Retro Game — FPGA top module (DE10-Lite / MAX10)
// Reads KEY[0], KEY[1] (debounced) and SW[9:0], then streams 3-byte
// control packets to ESP32 at 50 Hz over UART.
//
// Packet format (3 bytes, sent every 20 ms):
//   Byte 0: 0xAA              — sync marker
//   Byte 1: {4'b0, SW[9:8], KEY1_pressed, KEY0_pressed}
//   Byte 2: SW[7:0]
//
// LEDR[9] lights when KEY[0] is held; LEDR[8] when KEY[1] is held.
// LEDR[7:0] mirrors SW[7:0] for live visual feedback.
// All HEX displays are blanked.

module retro_game_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,          // active-low pushbuttons
    input  logic [9:0]  SW,
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
    output logic        UART_TX       // to ESP32 ARDUINO_IO[1] / GPIO17-RX
);

    // -------------------------------------------------------------------
    // 20 ms tick — 1 000 000 cycles @ 50 MHz → 50 Hz packet rate
    // -------------------------------------------------------------------
    logic [19:0] tick_ctr;
    logic        tick;

    always_ff @(posedge MAX10_CLK1_50) begin
        if (tick_ctr == 20'd999_999) begin
            tick_ctr <= '0;
            tick     <= 1;
        end else begin
            tick_ctr <= tick_ctr + 1;
            tick     <= 0;
        end
    end

    // -------------------------------------------------------------------
    // KEY[0] debounce — 20 ms (1 000 000 cycles)
    // -------------------------------------------------------------------
    logic [1:0]  k0_sync;
    logic [19:0] k0_cnt;
    logic        k0_db;

    always_ff @(posedge MAX10_CLK1_50) begin
        k0_sync <= {k0_sync[0], KEY[0]};
        if (k0_sync[1] == k0_db)
            k0_cnt <= '0;
        else if (k0_cnt == 20'd999_999) begin
            k0_db  <= k0_sync[1];
            k0_cnt <= '0;
        end else
            k0_cnt <= k0_cnt + 1;
    end

    // -------------------------------------------------------------------
    // KEY[1] debounce — 20 ms (1 000 000 cycles)
    // -------------------------------------------------------------------
    logic [1:0]  k1_sync;
    logic [19:0] k1_cnt;
    logic        k1_db;

    always_ff @(posedge MAX10_CLK1_50) begin
        k1_sync <= {k1_sync[0], KEY[1]};
        if (k1_sync[1] == k1_db)
            k1_cnt <= '0;
        else if (k1_cnt == 20'd999_999) begin
            k1_db  <= k1_sync[1];
            k1_cnt <= '0;
        end else
            k1_cnt <= k1_cnt + 1;
    end

    // Active-high pressed signals (KEY pins are active-low)
    logic key0, key1;
    assign key0 = ~k0_db;
    assign key1 = ~k1_db;

    // -------------------------------------------------------------------
    // UART TX controller — sends 3-byte packet on each 20 ms tick
    // Packet: 0xAA | ctrl_byte | sw_lo_byte
    // -------------------------------------------------------------------
    logic [7:0] tx_data_reg;
    logic       tx_start_r;
    logic       tx_busy_sig, tx_busy_prev, tx_done;

    always_ff @(posedge MAX10_CLK1_50)
        tx_busy_prev <= tx_busy_sig;

    assign tx_done = tx_busy_prev & ~tx_busy_sig;  // falling edge of busy

    typedef enum logic [1:0] { UTX_IDLE, UTX_B0, UTX_B1, UTX_B2 } utx_t;
    utx_t utx_state;

    logic [7:0] ctrl_latch;
    logic [7:0] swl_latch;

    always_ff @(posedge MAX10_CLK1_50) begin
        tx_start_r <= 0;
        case (utx_state)
            UTX_IDLE: if (tick) begin
                ctrl_latch  <= {4'b0, SW[9:8], key1, key0};
                swl_latch   <= SW[7:0];
                tx_data_reg <= 8'hAA;
                tx_start_r  <= 1;
                utx_state   <= UTX_B0;
            end

            UTX_B0: if (tx_done) begin   // sync done → send ctrl
                tx_data_reg <= ctrl_latch;
                tx_start_r  <= 1;
                utx_state   <= UTX_B1;
            end

            UTX_B1: if (tx_done) begin   // ctrl done → send sw_lo
                tx_data_reg <= swl_latch;
                tx_start_r  <= 1;
                utx_state   <= UTX_B2;
            end

            UTX_B2: if (tx_done)         // sw_lo done → back to idle
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
    // LED feedback
    // -------------------------------------------------------------------
    assign LEDR[9]   = key0;      // lights when KEY0 (pushbutton) is held
    assign LEDR[8]   = key1;      // lights when KEY1 (pushbutton) is held
    assign LEDR[7:0] = SW[7:0];   // mirrors the 8 lower sliding switches

    // -------------------------------------------------------------------
    // 7-segment — all blank
    // -------------------------------------------------------------------
    assign HEX0 = 7'h7F;
    assign HEX1 = 7'h7F;
    assign HEX2 = 7'h7F;
    assign HEX3 = 7'h7F;
    assign HEX4 = 7'h7F;
    assign HEX5 = 7'h7F;

endmodule
