#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// ── Hardware constants ────────────────────────────────────────
#define POT_PIN          34       // GPIO34 — ADC input only
#define ADC_MAX        4095       // 12-bit resolution
#define VREF            3.3f
#define ADC_SAMPLES      16       // average to reduce noise

#define OLED_W          128
#define OLED_H           64
#define OLED_RESET       -1
#define OLED_ADDR      0x3C

// UART2: TX=GPIO17 → FPGA ARDUINO_IO[0] (PIN_V10)
#define FPGA_TX         17
#define FPGA_RX         16        // not used; required by Serial2.begin()
#define FPGA_BAUD   115200

#define LOOP_MS         100       // 10 Hz update rate

Adafruit_SSD1306 display(OLED_W, OLED_H, &Wire, OLED_RESET);

// ── ADC averaging ────────────────────────────────────────────
static int adcAverage() {
    long sum = 0;
    for (int i = 0; i < ADC_SAMPLES; i++) sum += analogRead(POT_PIN);
    return (int)(sum / ADC_SAMPLES);
}

// ── OLED display ─────────────────────────────────────────────
// Formats voltage as "X.XXV", centred on screen at text size 3.
static void oledShowVoltage(float v) {
    int whole = (int)v;
    int frac  = (int)((v - whole) * 100.0f + 0.5f);
    if (frac >= 100) { whole++; frac = 0; }

    char buf[8];
    snprintf(buf, sizeof(buf), "%d.%02dV", whole, frac);

    display.clearDisplay();
    display.setTextSize(3);
    display.setTextColor(SSD1306_WHITE);

    int16_t  x1, y1;
    uint16_t tw, th;
    display.getTextBounds(buf, 0, 0, &x1, &y1, &tw, &th);
    display.setCursor((OLED_W - (int16_t)tw) / 2,
                      (OLED_H - (int16_t)th) / 2);
    display.print(buf);
    display.display();
}

// ── UART protocol ────────────────────────────────────────────
// 16-bit payload: high byte first, then low byte.
// Value range: 0–330 representing 0.00–3.30 V.
static void sendToFPGA(uint16_t val) {
    Serial2.write((uint8_t)((val >> 8) & 0xFF));
    Serial2.write((uint8_t)(val        & 0xFF));
}

// ── Setup ────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);

    analogReadResolution(12);
    analogSetPinAttenuation(POT_PIN, ADC_11db); // input range 0–3.3 V

    Serial2.begin(FPGA_BAUD, SERIAL_8N1, FPGA_RX, FPGA_TX);

    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
        Serial.println(F("SSD1306 init failed"));
        for (;;);
    }
    display.clearDisplay();
    display.display();
    Serial.println(F("Voltmeter ready"));
}

// ── Loop ─────────────────────────────────────────────────────
void loop() {
    int   raw     = adcAverage();
    float voltage = (raw / (float)ADC_MAX) * VREF;
    if (voltage < 0.0f) voltage = 0.0f;
    if (voltage > VREF)  voltage = VREF;

    uint16_t intVal = (uint16_t)(voltage * 100.0f + 0.5f);
    if (intVal > 330) intVal = 330;

    oledShowVoltage(voltage);
    sendToFPGA(intVal);

    delay(LOOP_MS);
}
