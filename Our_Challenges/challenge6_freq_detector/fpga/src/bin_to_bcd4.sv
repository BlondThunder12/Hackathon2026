// bin_to_bcd4.sv — Double-Dabble binary to 4-digit BCD converter
// Purely combinational. 11-bit input (0–2047) → thousands, hundreds, tens, ones.
// Used to display frequency values 0–2000 Hz on HEX3..HEX0.
//
// Algorithm: for each input bit MSB→LSB, add 3 to any BCD nibble ≥ 5,
// then left-shift the entire BCD register by 1, feeding in the next bit.

module bin_to_bcd4 #(
    parameter int BIN_W = 11
)(
    input  logic [BIN_W-1:0] bin,
    output logic [3:0]       thousands,
    output logic [3:0]       hundreds,
    output logic [3:0]       tens,
    output logic [3:0]       ones
);

logic [3:0] th, h, t, o;

always_comb begin
    th = 4'd0;
    h  = 4'd0;
    t  = 4'd0;
    o  = 4'd0;
    for (int i = BIN_W - 1; i >= 0; i--) begin
        // Add 3 to any BCD digit already >= 5 before the shift
        if (th >= 4'd5) th = th + 4'd3;
        if (h  >= 4'd5) h  = h  + 4'd3;
        if (t  >= 4'd5) t  = t  + 4'd3;
        if (o  >= 4'd5) o  = o  + 4'd3;
        // Left-shift: each nibble feeds its MSB into the nibble above
        th = {th[2:0], h[3]};
        h  = {h[2:0],  t[3]};
        t  = {t[2:0],  o[3]};
        o  = {o[2:0],  bin[i]};
    end
    thousands = th;
    hundreds  = h;
    tens      = t;
    ones      = o;
end

endmodule
