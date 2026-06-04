// bin_to_bcd.sv — Double-Dabble (shift-and-add-3) binary to BCD converter
// Purely combinational. 8-bit input (0–255) → hundreds, tens, ones digits.
// Used here to display zero-crossing count (0–128) in debug mode.

module bin_to_bcd #(
    parameter int BIN_W = 8
)(
    input  logic [BIN_W-1:0] bin,
    output logic [3:0]       hundreds,
    output logic [3:0]       tens,
    output logic [3:0]       ones
);

logic [3:0] h, t, o;

always_comb begin
    h = 4'd0;
    t = 4'd0;
    o = 4'd0;
    for (int i = BIN_W - 1; i >= 0; i--) begin
        if (h >= 4'd5) h = h + 4'd3;
        if (t >= 4'd5) t = t + 4'd3;
        if (o >= 4'd5) o = o + 4'd3;
        h = {h[2:0], t[3]};
        t = {t[2:0], o[3]};
        o = {o[2:0], bin[i]};
    end
    hundreds = h;
    tens     = t;
    ones     = o;
end

endmodule
