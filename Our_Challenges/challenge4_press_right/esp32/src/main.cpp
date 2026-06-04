// Challenge 4: Press Right — ESP32 side
// Receives 2-byte stopped counter value from FPGA via UART.
// Plays buzzer if value is within ±10 of 1000. Shows result on OLED.

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "../../../../projects/common/esp32/pin_config.h"

#define TARGET      1000
#define WIN_RANGE   10

Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
HardwareSerial FpgaSerial(2);

static void beep(int freq, int ms) {
    tone(PIN_BUZZER, freq);
    delay(ms);
    noTone(PIN_BUZZER);
}

static void setProximityLeds(int diff) {
    digitalWrite(PIN_LED_1, diff <= 500 ? HIGH : LOW);
    digitalWrite(PIN_LED_2, diff <= 100 ? HIGH : LOW);
    digitalWrite(PIN_LED_3, diff <= WIN_RANGE ? HIGH : LOW);
}

static void showResult(int value) {
    int  diff = abs(value - TARGET);
    bool win  = (diff <= WIN_RANGE);

    setProximityLeds(diff);

    // Proximity bar width (0-10 blocks)
    int bars = 0;
    if      (diff <= 10)   bars = 10;
    else if (diff <= 50)   bars = 9;
    else if (diff <= 100)  bars = 8;
    else if (diff <= 200)  bars = 7;
    else if (diff <= 300)  bars = 6;
    else if (diff <= 500)  bars = 5;
    else if (diff <= 700)  bars = 4;
    else if (diff <= 1000) bars = 3;
    else if (diff <= 2000) bars = 2;
    else if (diff <= 4000) bars = 1;

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);

    // Line 1: value
    display.setTextSize(2);
    display.setCursor(0, 0);
    display.printf("Val: %d", value);

    // Line 2: WIN or diff
    display.setCursor(0, 20);
    if (win) {
        display.println("** WIN! **");
    } else {
        display.printf("Off: %d", diff);
        display.setCursor(0, 40);
        display.setTextSize(1);
        display.print("Miss — try again!");
    }

    // Line 3: proximity bar
    display.setTextSize(1);
    display.setCursor(0, 56);
    for (int i = 0; i < bars; i++)       display.print('#');
    for (int i = bars; i < 10; i++)      display.print('.');

    display.display();

    // Sound
    if (win) {
        beep(880,  150); delay(50);
        beep(1047, 150); delay(50);
        beep(1319, 500);
    } else {
        beep(330, 200); delay(50);
        beep(262, 400);
    }
}

static void showSplash() {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0,  0); display.println("=== Press Right! ===");
    display.setCursor(0, 12); display.println("Target: 1000 (10 s)");
    display.setCursor(0, 24); display.println("KEY[0] start");
    display.setCursor(0, 36); display.println("KEY[0] stop");
    display.setCursor(0, 48); display.println("Win range: 990-1010");
    display.display();
}

void setup() {
    Serial.begin(115200);

    pinMode(PIN_LED_1, OUTPUT);
    pinMode(PIN_LED_2, OUTPUT);
    pinMode(PIN_LED_3, OUTPUT);
    digitalWrite(PIN_LED_1, LOW);
    digitalWrite(PIN_LED_2, LOW);
    digitalWrite(PIN_LED_3, LOW);

    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR)) {
        Serial.println("OLED init failed");
        for (;;);
    }

    // UART2: RX = GPIO17 (from FPGA ARDUINO_IO[1]), TX unused
    FpgaSerial.begin(FPGA_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);

    showSplash();
    Serial.println("Press Right — waiting for FPGA...");
}

void loop() {
    if (FpgaSerial.available() >= 2) {
        uint8_t hi = FpgaSerial.read();
        uint8_t lo = FpgaSerial.read();
        while (FpgaSerial.available()) FpgaSerial.read();  // drain noise

        int value = ((int)hi << 8) | lo;
        Serial.printf("Received: %d  diff: %d\n", value, abs(value - TARGET));
        showResult(value);
    }
}
