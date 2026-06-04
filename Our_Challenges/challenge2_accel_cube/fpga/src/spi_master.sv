// SPI Master — Mode 3 (CPOL=1, CPHA=1), 8-bit transfers
// CS_N is managed by the caller; this module drives SCK, MOSI, samples MISO.

module spi_master #(
    parameter CLK_DIV = 25  // SCK half-period cycles; SCK freq = clk / (2*CLK_DIV)
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,      // 1-cycle pulse to begin transfer
    input  logic [7:0] tx_byte,
    output logic [7:0] rx_byte,
    output logic       done,       // 1-cycle pulse: rx_byte valid
    output logic       busy,
    output logic       sclk,       // idle-high (Mode 3)
    output logic       mosi,
    input  logic       miso
);

    localparam HALF = CLK_DIV - 1;

    // phase: 0=IDLE, 1=SCK_LOW, 2=SCK_HIGH
    logic [1:0]  phase;
    logic [4:0]  cnt;
    logic [2:0]  bit_cnt;
    logic [7:0]  shift_tx;
    logic [7:0]  shift_rx;

    assign sclk = (phase != 2'd1);   // high in IDLE and SCK_HIGH, low in SCK_LOW
    assign mosi = shift_tx[7];
    assign busy = (phase != 2'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase    <= 2'd0;
            cnt      <= '0;
            bit_cnt  <= '0;
            shift_tx <= '0;
            shift_rx <= '0;
            rx_byte  <= '0;
            done     <= 1'b0;
        end else begin
            done <= 1'b0;

            case (phase)
                2'd0: begin  // IDLE
                    if (start) begin
                        shift_tx <= tx_byte;
                        cnt      <= '0;
                        bit_cnt  <= '0;
                        phase    <= 2'd1;
                    end
                end

                2'd1: begin  // SCK_LOW
                    if (cnt == HALF) begin
                        cnt   <= '0;
                        phase <= 2'd2;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end

                2'd2: begin  // SCK_HIGH — sample MISO at end of phase
                    if (cnt == HALF) begin
                        cnt <= '0;
                        if (bit_cnt == 3'd7) begin
                            rx_byte  <= {shift_rx[6:0], miso};
                            done     <= 1'b1;
                            phase    <= 2'd0;
                        end else begin
                            shift_rx <= {shift_rx[6:0], miso};
                            shift_tx <= {shift_tx[6:0], 1'b0};
                            bit_cnt  <= bit_cnt + 1;
                            phase    <= 2'd1;
                        end
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
            endcase
        end
    end

endmodule
