// Challenge 2: Accelerometer 3D Cube — FPGA top module
//
// Reads ADXL345 via SPI (onboard sensor), sends raw X/Y/Z over UART at 115200 baud.
// Frame format: [0xFF, X_L, X_H, Y_L, Y_H, Z_L, Z_H]  (~50 Hz)
// LEDs: LEDR[9]=right, LEDR[8]=left, LEDR[7]=forward, LEDR[6]=back (tilt indicators)

module accel_cube_top (
    input  logic        MAX10_CLK1_50,
    input  logic [1:0]  KEY,        // KEY[0] = active-low reset

    // G-Sensor (ADXL345) SPI
    output logic        GSENSOR_CS_N,
    output logic        GSENSOR_SCLK,
    output logic        GSENSOR_SDI,   // MOSI
    input  logic        GSENSOR_SDO,   // MISO

    // UART TX to ESP32 (ARDUINO_IO[1] = PIN_AB6)
    output logic        UART_TX,

    // LEDs
    output logic [9:0]  LEDR
);

    // ---- Reset ----
    logic rst_n;
    assign rst_n = KEY[0];

    // ---- SPI master ↔ ADXL345 controller ----
    logic        spi_cs_n, spi_start;
    logic [7:0]  spi_tx_byte, spi_rx_byte;
    logic        spi_done, spi_busy;

    spi_master #(.CLK_DIV(25)) u_spi (
        .clk      (MAX10_CLK1_50),
        .rst_n    (rst_n),
        .start    (spi_start),
        .tx_byte  (spi_tx_byte),
        .rx_byte  (spi_rx_byte),
        .done     (spi_done),
        .busy     (spi_busy),
        .sclk     (GSENSOR_SCLK),
        .mosi     (GSENSOR_SDI),
        .miso     (GSENSOR_SDO)
    );
    assign GSENSOR_CS_N = spi_cs_n;

    // ---- ADXL345 controller ----
    logic [15:0] accel_x, accel_y, accel_z;
    logic        data_valid;

    adxl345_ctrl u_accel (
        .clk       (MAX10_CLK1_50),
        .rst_n     (rst_n),
        .spi_cs_n  (spi_cs_n),
        .spi_start (spi_start),
        .spi_tx    (spi_tx_byte),
        .spi_rx    (spi_rx_byte),
        .spi_done  (spi_done),
        .spi_busy  (spi_busy),
        .accel_x   (accel_x),
        .accel_y   (accel_y),
        .accel_z   (accel_z),
        .data_valid(data_valid)
    );

    // ---- UART TX ----
    logic       tx_start_r, tx_busy_r;
    logic [7:0] tx_data_r;

    uart_tx #(.CLK_FREQ(50_000_000), .BAUD(115200)) u_uart (
        .clk      (MAX10_CLK1_50),
        .rst_n    (rst_n),
        .tx_start (tx_start_r),
        .tx_data  (tx_data_r),
        .tx_busy  (tx_busy_r),
        .tx_out   (UART_TX)
    );

    // ---- UART frame sequencer ----
    // Frame: [0xFF, X_L, X_H, Y_L, Y_H, Z_L, Z_H]
    typedef enum logic [1:0] { US_IDLE, US_SEND, US_WAIT } uart_st_t;
    uart_st_t   uart_st;
    logic [2:0] uart_cnt;
    logic [7:0] frame [0:6];
    logic       prev_tx_busy;
    logic       tx_done;

    assign tx_done = prev_tx_busy & ~tx_busy_r;

    always_ff @(posedge MAX10_CLK1_50 or negedge rst_n) begin
        if (!rst_n) begin
            uart_st      <= US_IDLE;
            uart_cnt     <= '0;
            tx_start_r   <= 1'b0;
            tx_data_r    <= '0;
            prev_tx_busy <= 1'b0;
            for (int i = 0; i < 7; i++) frame[i] <= '0;
        end else begin
            prev_tx_busy <= tx_busy_r;
            tx_start_r   <= 1'b0;

            case (uart_st)
                US_IDLE: begin
                    if (data_valid) begin
                        frame[0] <= 8'hFF;
                        frame[1] <= accel_x[7:0];
                        frame[2] <= accel_x[15:8];
                        frame[3] <= accel_y[7:0];
                        frame[4] <= accel_y[15:8];
                        frame[5] <= accel_z[7:0];
                        frame[6] <= accel_z[15:8];
                        uart_cnt <= '0;
                        uart_st  <= US_SEND;
                    end
                end

                US_SEND: begin
                    if (!tx_busy_r) begin
                        tx_data_r  <= frame[uart_cnt];
                        tx_start_r <= 1'b1;
                        uart_cnt   <= uart_cnt + 1;
                        uart_st    <= US_WAIT;
                    end
                end

                US_WAIT: begin
                    if (tx_done) begin
                        if (uart_cnt == 3'd7)
                            uart_st <= US_IDLE;
                        else
                            uart_st <= US_SEND;
                    end
                end
            endcase
        end
    end

    // ---- LEDs: tilt direction indicators ----
    // Threshold ~100 counts ≈ 0.4g ≈ ~22° tilt (full-resolution mode)
    localparam signed [15:0] THRESH = 16'sd100;
    logic signed [15:0] ax_s, ay_s;
    assign ax_s = $signed(accel_x);
    assign ay_s = $signed(accel_y);

    assign LEDR[9] = (ax_s >  THRESH);   // tilt right
    assign LEDR[8] = (ax_s < -THRESH);   // tilt left
    assign LEDR[7] = (ay_s >  THRESH);   // tilt forward
    assign LEDR[6] = (ay_s < -THRESH);   // tilt back
    assign LEDR[5:0] = 6'b0;

endmodule
