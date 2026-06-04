// led_bargraph.sv — thermometer bar graph across LEDR[9:0]
// Range: 0–330. Each LED represents 33 units (330 / 10 = 33).
// LED[i] lights when voltage_int > i*33, giving a proportional fill.
// At full scale (330) all 10 LEDs are on; at zero all are off.

module led_bargraph (
    input  logic [8:0] voltage_int,
    output logic [9:0] leds
);

always_comb begin
    leds[0] = (voltage_int >  9'd0);
    leds[1] = (voltage_int >  9'd33);
    leds[2] = (voltage_int >  9'd66);
    leds[3] = (voltage_int >  9'd99);
    leds[4] = (voltage_int > 9'd132);
    leds[5] = (voltage_int > 9'd165);
    leds[6] = (voltage_int > 9'd198);
    leds[7] = (voltage_int > 9'd231);
    leds[8] = (voltage_int > 9'd264);
    leds[9] = (voltage_int > 9'd297);
end

endmodule
