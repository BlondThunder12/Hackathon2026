// uart_rx.sv — 8-N-1 UART byte receiver
// Samples start bit at ½ period, each data bit at centre of bit period.
// Two-stage synchroniser on rx prevents metastability.

module uart_rx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115_200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx,
    output logic [7:0] data,
    output logic       valid
);

localparam int FULL  = CLK_FREQ / BAUD_RATE;   // 434 clocks per bit
localparam int HALF  = FULL / 2;                // 217
localparam int CBITS = $clog2(FULL + 1);        // 9 bits wide

localparam logic [CBITS-1:0] CNT_HALF = CBITS'(HALF - 1);
localparam logic [CBITS-1:0] CNT_FULL = CBITS'(FULL - 1);

typedef enum logic [1:0] {
    S_IDLE  = 2'd0,
    S_START = 2'd1,
    S_DATA  = 2'd2,
    S_STOP  = 2'd3
} state_t;

state_t           state;
logic             rx_s1, rx_s2;
logic [CBITS-1:0] ctr;
logic [2:0]       bit_idx;
logic [7:0]       shift_reg;

// Two-stage synchroniser
always_ff @(posedge clk) begin
    rx_s1 <= rx;
    rx_s2 <= rx_s1;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= S_IDLE;
        ctr       <= '0;
        bit_idx   <= '0;
        shift_reg <= '0;
        data      <= '0;
        valid     <= 1'b0;
    end else begin
        valid <= 1'b0;

        case (state)
            S_IDLE: begin
                ctr     <= '0;
                bit_idx <= '0;
                if (!rx_s2) state <= S_START; // falling edge = start bit
            end

            S_START: begin
                if (ctr == CNT_HALF) begin
                    ctr   <= '0;
                    state <= (!rx_s2) ? S_DATA : S_IDLE; // verify still low
                end else
                    ctr <= ctr + 1'b1;
            end

            S_DATA: begin
                if (ctr == CNT_FULL) begin
                    ctr                <= '0;
                    shift_reg[bit_idx] <= rx_s2;
                    if (bit_idx == 3'd7) begin
                        bit_idx <= '0;
                        state   <= S_STOP;
                    end else
                        bit_idx <= bit_idx + 1'b1;
                end else
                    ctr <= ctr + 1'b1;
            end

            S_STOP: begin
                if (ctr == CNT_FULL) begin
                    ctr   <= '0;
                    state <= S_IDLE;
                    if (rx_s2) begin       // valid stop bit = line high
                        data  <= shift_reg;
                        valid <= 1'b1;
                    end
                end else
                    ctr <= ctr + 1'b1;
            end
        endcase
    end
end

endmodule
