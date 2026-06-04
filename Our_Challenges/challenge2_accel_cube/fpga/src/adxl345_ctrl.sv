// ADXL345 controller — SPI init + continuous burst-read at ~50 Hz
// SPI write: [RW=0, MB=0, ADDR5:0, DATA7:0]  (2 SPI bytes, CS low throughout)
// SPI read:  [RW=1, MB=1, 0x32]  then clock 6 dummy bytes, receive X0 X1 Y0 Y1 Z0 Z1
//
// DATA_FORMAT (0x31) = 0x0B : full-resolution, ±16g (3.9 mg/LSB)
// POWER_CTL  (0x2D) = 0x08 : measure mode

module adxl345_ctrl (
    input  logic        clk,
    input  logic        rst_n,
    // SPI interface
    output logic        spi_cs_n,
    output logic        spi_start,
    output logic [7:0]  spi_tx,
    input  logic [7:0]  spi_rx,
    input  logic        spi_done,
    input  logic        spi_busy,
    // Acceleration output (signed 16-bit, sign-extended 13-bit data)
    output logic [15:0] accel_x,
    output logic [15:0] accel_y,
    output logic [15:0] accel_z,
    output logic        data_valid  // 1-cycle pulse when new data latched
);

    // ---- SPI command constants ----
    localparam WR_DATA_FMT_ADDR = 8'h31;   // write, single, reg 0x31
    localparam WR_DATA_FMT_DATA = 8'h0B;   // full-res, ±16g
    localparam WR_POWER_ADDR    = 8'h2D;   // write, single, reg 0x2D
    localparam WR_POWER_DATA    = 8'h08;   // measure
    localparam RD_BURST_ADDR    = 8'hF2;   // read, multi-byte, from 0x32

    // ---- Timing constants (50 MHz clock) ----
    localparam PWRON_CYCLES  = 27'd5_000_000;  // 100 ms
    localparam SAMPLE_CYCLES = 27'd1_000_000;  // 20 ms → 50 Hz

    typedef enum logic [4:0] {
        S_PWRON,
        S_WR_FMT_CS,   S_WR_FMT_ADDR, S_WR_FMT_W1,
        S_WR_FMT_DATA, S_WR_FMT_W2,   S_WR_FMT_END,
        S_WR_PWR_CS,   S_WR_PWR_ADDR, S_WR_PWR_W1,
        S_WR_PWR_DATA, S_WR_PWR_W2,   S_WR_PWR_END,
        S_SAMPLE_WAIT,
        S_RD_CS,   S_RD_ADDR, S_RD_ADDR_W,
        S_RD_X0,   S_RD_X0_W,
        S_RD_X1,   S_RD_X1_W,
        S_RD_Y0,   S_RD_Y0_W,
        S_RD_Y1,   S_RD_Y1_W,
        S_RD_Z0,   S_RD_Z0_W,
        S_RD_Z1,   S_RD_Z1_W,
        S_RD_END
    } state_t;

    state_t      state;
    logic [26:0] timer;
    logic [7:0]  raw_x0, raw_x1, raw_y0, raw_y1, raw_z0, raw_z1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_PWRON;
            spi_cs_n   <= 1'b1;
            spi_start  <= 1'b0;
            spi_tx     <= 8'h00;
            timer      <= '0;
            data_valid <= 1'b0;
            accel_x    <= '0;
            accel_y    <= '0;
            accel_z    <= '0;
            raw_x0 <= '0; raw_x1 <= '0;
            raw_y0 <= '0; raw_y1 <= '0;
            raw_z0 <= '0; raw_z1 <= '0;
        end else begin
            spi_start  <= 1'b0;
            data_valid <= 1'b0;

            case (state)
                // ---- Power-on delay ----
                S_PWRON: begin
                    if (timer == PWRON_CYCLES) begin
                        timer <= '0;  state <= S_WR_FMT_CS;
                    end else timer <= timer + 1;
                end

                // ---- Write DATA_FORMAT = 0x0B ----
                S_WR_FMT_CS:   begin spi_cs_n <= 1'b0;  state <= S_WR_FMT_ADDR; end
                S_WR_FMT_ADDR: begin spi_tx <= WR_DATA_FMT_ADDR; spi_start <= 1'b1; state <= S_WR_FMT_W1; end
                S_WR_FMT_W1:   begin if (spi_done) state <= S_WR_FMT_DATA; end
                S_WR_FMT_DATA: begin spi_tx <= WR_DATA_FMT_DATA; spi_start <= 1'b1; state <= S_WR_FMT_W2; end
                S_WR_FMT_W2:   begin if (spi_done) state <= S_WR_FMT_END; end
                S_WR_FMT_END:  begin spi_cs_n <= 1'b1;  state <= S_WR_PWR_CS; end

                // ---- Write POWER_CTL = 0x08 ----
                S_WR_PWR_CS:   begin spi_cs_n <= 1'b0;  state <= S_WR_PWR_ADDR; end
                S_WR_PWR_ADDR: begin spi_tx <= WR_POWER_ADDR; spi_start <= 1'b1; state <= S_WR_PWR_W1; end
                S_WR_PWR_W1:   begin if (spi_done) state <= S_WR_PWR_DATA; end
                S_WR_PWR_DATA: begin spi_tx <= WR_POWER_DATA; spi_start <= 1'b1; state <= S_WR_PWR_W2; end
                S_WR_PWR_W2:   begin if (spi_done) state <= S_WR_PWR_END; end
                S_WR_PWR_END:  begin spi_cs_n <= 1'b1;  state <= S_SAMPLE_WAIT; end

                // ---- Inter-sample delay ----
                S_SAMPLE_WAIT: begin
                    if (timer == SAMPLE_CYCLES) begin
                        timer <= '0;  state <= S_RD_CS;
                    end else timer <= timer + 1;
                end

                // ---- Burst read: 0xF2 → X0 X1 Y0 Y1 Z0 Z1 ----
                S_RD_CS:     begin spi_cs_n <= 1'b0; state <= S_RD_ADDR; end
                S_RD_ADDR:   begin spi_tx <= RD_BURST_ADDR; spi_start <= 1'b1; state <= S_RD_ADDR_W; end
                S_RD_ADDR_W: begin if (spi_done) state <= S_RD_X0; end

                S_RD_X0:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_X0_W; end
                S_RD_X0_W: begin if (spi_done) begin raw_x0 <= spi_rx; state <= S_RD_X1; end end

                S_RD_X1:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_X1_W; end
                S_RD_X1_W: begin if (spi_done) begin raw_x1 <= spi_rx; state <= S_RD_Y0; end end

                S_RD_Y0:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_Y0_W; end
                S_RD_Y0_W: begin if (spi_done) begin raw_y0 <= spi_rx; state <= S_RD_Y1; end end

                S_RD_Y1:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_Y1_W; end
                S_RD_Y1_W: begin if (spi_done) begin raw_y1 <= spi_rx; state <= S_RD_Z0; end end

                S_RD_Z0:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_Z0_W; end
                S_RD_Z0_W: begin if (spi_done) begin raw_z0 <= spi_rx; state <= S_RD_Z1; end end

                S_RD_Z1:   begin spi_tx <= 8'h00; spi_start <= 1'b1; state <= S_RD_Z1_W; end
                S_RD_Z1_W: begin if (spi_done) begin raw_z1 <= spi_rx; state <= S_RD_END; end end

                S_RD_END: begin
                    spi_cs_n   <= 1'b1;
                    accel_x    <= {raw_x1, raw_x0};
                    accel_y    <= {raw_y1, raw_y0};
                    accel_z    <= {raw_z1, raw_z0};
                    data_valid <= 1'b1;
                    state      <= S_SAMPLE_WAIT;
                end

                default: state <= S_PWRON;
            endcase
        end
    end

endmodule
