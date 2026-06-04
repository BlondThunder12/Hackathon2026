// seg7_dec.sv — active-low seven-segment decoder
// Output format matches DE10-Lite HEX pin order:
//   segments[7:0] = {DP, G, F, E, D, C, B, A}  (0 = segment ON)
//
// NOTE: The DE10-Lite does not route the DP pin (bit 7) to the FPGA fabric
// in the standard board configuration. The top-level assigns only [6:0] to
// the HEX output ports. Bit 7 is set correctly here so that if the DP pin
// is ever bridged to a GPIO the code requires no change.

module seg7_dec (
    input  logic [3:0] digit,
    input  logic       dp_on,    // 1 = illuminate decimal point
    output logic [7:0] segments  // active-low: {DP, G, F, E, D, C, B, A}
);

always_comb begin
    case (digit)
        4'd0: segments[6:0] = 7'b1000000;
        4'd1: segments[6:0] = 7'b1111001;
        4'd2: segments[6:0] = 7'b0100100;
        4'd3: segments[6:0] = 7'b0110000;
        4'd4: segments[6:0] = 7'b0011001;
        4'd5: segments[6:0] = 7'b0010010;
        4'd6: segments[6:0] = 7'b0000010;
        4'd7: segments[6:0] = 7'b1111000;
        4'd8: segments[6:0] = 7'b0000000;
        4'd9: segments[6:0] = 7'b0010000;
        default: segments[6:0] = 7'b1111111; // blank
    endcase
    segments[7] = ~dp_on; // active-low: dp_on=1 drives pin to 0 (lit)
end

endmodule
