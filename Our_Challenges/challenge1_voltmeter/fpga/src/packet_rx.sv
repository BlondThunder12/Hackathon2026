// packet_rx.sv — reassembles two UART bytes into a 9-bit voltage integer
// ESP32 sends HIGH byte first, then LOW byte (big-endian).
// Max value 330 = 0x014A → 9 bits suffice (hi_byte is always 0x00 or 0x01).

module packet_rx (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] byte_data,
    input  logic       byte_valid,
    output logic [8:0] voltage_int,
    output logic       voltage_valid
);

logic [7:0] hi_reg;
logic       got_hi;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hi_reg        <= '0;
        got_hi        <= 1'b0;
        voltage_int   <= '0;
        voltage_valid <= 1'b0;
    end else begin
        voltage_valid <= 1'b0;

        if (byte_valid) begin
            if (!got_hi) begin
                hi_reg <= byte_data;
                got_hi <= 1'b1;
            end else begin
                // hi_reg[0] is bit 8 of the value; max hi byte = 0x01
                voltage_int   <= {hi_reg[0], byte_data};
                voltage_valid <= 1'b1;
                got_hi        <= 1'b0;
            end
        end
    end
end

endmodule
