// Challenge 6 — Frequency Detector (ESP32 side)
//
// Reads potentiometer on GPIO34 (ADC), maps 0–4095 → 100–2000 Hz,
// generates 256 signed 8-bit sine wave samples at 8000 Hz sample rate,
// and streams the raw frame over UART2 at 115200 baud to the FPGA.
//
// Wiring (Arduino header on DE10-Lite):
//   ESP32 GPIO16 (UART2 TX) → FPGA ARDUINO_IO[0]  (PIN_AB5)
//   ESP32 GND               → FPGA Arduino header GND

#include <Arduino.h>
#include <math.h>
#include "../../../../projects/common/esp32/pin_config.h"

// ---- Sine-generation parameters ----------------------------------------
static constexpr int   SAMPLE_RATE = 8000;   // Hz
static constexpr int   NUM_SAMPLES = 256;    // samples per frame
static constexpr float MIN_FREQ    = 100.0f; // Hz
static constexpr float MAX_FREQ    = 2000.0f;// Hz
static constexpr int   ADC_OVERSAMPLE = 16;  // averages to reduce ADC noise

// This challenge runs UART at 115200, not the shared default of 9600
static constexpr int FREQ_BAUD = 115200;

// Frame buffer — signed 8-bit samples
static int8_t frame[NUM_SAMPLES];

// ---- generateSineFrame --------------------------------------------------
// Fills `frame[]` with one period (or partial period) of a sine wave at
// `freq_hz`, sampled at SAMPLE_RATE.  Amplitude is scaled to ±127.
// -------------------------------------------------------------------------
static void generateSineFrame(float freq_hz) {
    const float k = 2.0f * (float)M_PI * freq_hz / (float)SAMPLE_RATE;
    for (int i = 0; i < NUM_SAMPLES; i++) {
        frame[i] = (int8_t)(127.0f * sinf(k * (float)i));
    }
}

// ---- setup --------------------------------------------------------------
void setup() {
    Serial.begin(115200);

    // ADC: 12-bit, 0–3.3 V input range
    analogReadResolution(12);
    analogSetPinAttenuation(PIN_ANALOG_IN, ADC_11db);

    // UART2: TX = PIN_FPGA_TX (GPIO16) → FPGA ARDUINO_IO[0]
    //        RX = PIN_FPGA_RX (GPIO17) ← unused this challenge, still configured
    Serial2.begin(FREQ_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);

    Serial.println(F("Challenge 6 — Frequency Detector ready"));
    Serial.printf("Range: %.0f–%.0f Hz | %d samples @ %d Hz | UART %d baud\n",
                  MIN_FREQ, MAX_FREQ, NUM_SAMPLES, SAMPLE_RATE, FREQ_BAUD);
}

// ---- loop ---------------------------------------------------------------
void loop() {
    // ---- 1. Read potentiometer (averaged) ----
    long sum = 0;
    for (int i = 0; i < ADC_OVERSAMPLE; i++) {
        sum += analogRead(PIN_ANALOG_IN);
    }
    int raw = (int)(sum / ADC_OVERSAMPLE);

    // ---- 2. Map ADC (0–4095) → frequency (100–2000 Hz) ----
    float freq = MIN_FREQ + ((float)raw / 4095.0f) * (MAX_FREQ - MIN_FREQ);
    if (freq < MIN_FREQ) freq = MIN_FREQ;
    if (freq > MAX_FREQ) freq = MAX_FREQ;

    // ---- 3. Generate 256-sample signed-byte sine frame ----
    generateSineFrame(freq);

    // ---- 4. Send raw frame to FPGA ----
    Serial2.write((const uint8_t *)frame, NUM_SAMPLES);

    // ---- 5. Debug output on USB serial ----
    Serial.printf("Sent: %.1f Hz (ADC=%d)\n", freq, raw);

    // Inter-frame gap: ensures FPGA gap-timeout fires cleanly between frames.
    // 50 ms >> 22 ms (time to send 256 bytes @ 115200) + FPGA timeout 3 ms.
    delay(50);
}
