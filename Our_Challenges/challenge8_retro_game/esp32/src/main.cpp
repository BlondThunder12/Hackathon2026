// Challenge 8: PC Retro Game — ESP32 bridge
// Receives 3-byte control packets from FPGA (9600 baud, UART2),
// forwards them to the PC over USB serial (115200 baud).
// Shows live status on OLED.
//
// Packet: 0xAA | {4'b0, SW[9:8], KEY1, KEY0} | SW[7:0]

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "../../../../projects/common/esp32/pin_config.h"

Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
HardwareSerial FpgaSerial(2);

static uint32_t pkt_count = 0;
static uint8_t  last_ctrl = 0;
static uint8_t  last_sw_lo = 0;

static void updateOled() {
    uint8_t keys = last_ctrl & 0x03;
    uint16_t sw  = (uint16_t)((last_ctrl & 0x0C) << 6) | last_sw_lo;

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0,  0); display.println("=== Retro Game ===");
    display.setCursor(0, 12); display.printf("Pkts: %lu", pkt_count);
    display.setCursor(0, 24); display.printf("K0:%d  K1:%d", keys & 1, (keys >> 1) & 1);
    display.setCursor(0, 36); display.printf("SW: 0x%03X", sw);
    display.display();
}

static void showSplash() {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0,  0); display.println("=== Retro Game ===");
    display.setCursor(0, 12); display.println("KEY0  = flap");
    display.setCursor(0, 24); display.println("KEY1  = pause/reset");
    display.setCursor(0, 36); display.println("SW9:8 = difficulty");
    display.setCursor(0, 48); display.println("Waiting for FPGA...");
    display.display();
}

void setup() {
    Serial.begin(115200);

    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR)) {
        Serial.println("OLED init failed");
        for (;;);
    }

    // UART2: RX = GPIO17 (from FPGA ARDUINO_IO[1]), TX unused
    FpgaSerial.begin(FPGA_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);

    showSplash();
    Serial.println("Challenge 8: bridge ready — waiting for FPGA packets...");
}

void loop() {
    // Sync: discard bytes until we see 0xAA
    if (!FpgaSerial.available()) return;
    if (FpgaSerial.peek() != 0xAA) {
        FpgaSerial.read();
        return;
    }

    // Need all 3 bytes before consuming
    if (FpgaSerial.available() < 3) return;

    uint8_t sync  = FpgaSerial.read();
    uint8_t ctrl  = FpgaSerial.read();
    uint8_t sw_lo = FpgaSerial.read();

    // Validate: ctrl upper nibble must be zero
    if (ctrl & 0xF0) return;

    // Forward to PC
    Serial.write(sync);
    Serial.write(ctrl);
    Serial.write(sw_lo);

    last_ctrl  = ctrl;
    last_sw_lo = sw_lo;
    pkt_count++;

    // Refresh OLED every 50 packets (~1 s)
    if ((pkt_count % 50) == 0)
        updateOled();
}
