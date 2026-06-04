// Challenge 2: Accelerometer 3D Cube — ESP32 side
//
// Receives 7-byte frames from FPGA at 115200 baud:
//   [0xFF, X_L, X_H, Y_L, Y_H, Z_L, Z_H]  (signed 16-bit, ADXL345 full-res)
// Computes pitch & roll, draws a rotating wireframe cube on the SSD1306 OLED.

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <math.h>
#include "../../../../projects/common/esp32/pin_config.h"

// Override baud — challenge 2 uses 115200 for low-latency accel streaming
#define ACCEL_BAUD  115200

Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
HardwareSerial   FpgaSerial(2);

// ---- UART frame parser state ----
static enum { WAIT_FF, READ_DATA } rx_state = WAIT_FF;
static uint8_t  rx_buf[6];
static int      rx_idx = 0;

// ---- Latest angles (radians) ----
static volatile float g_pitch = 0.0f;
static volatile float g_roll  = 0.0f;
static volatile bool  g_new   = false;

// ---- 3D wireframe cube ----
struct Vec3 { float x, y, z; };

static const Vec3 VERTS[8] = {
    {-1,-1,-1}, { 1,-1,-1}, { 1, 1,-1}, {-1, 1,-1},
    {-1,-1, 1}, { 1,-1, 1}, { 1, 1, 1}, {-1, 1, 1}
};
static const uint8_t EDGES[12][2] = {
    {0,1},{1,2},{2,3},{3,0},   // back face
    {4,5},{5,6},{6,7},{7,4},   // front face
    {0,4},{1,5},{2,6},{3,7}    // connecting edges
};

static void project(const Vec3 &v, int16_t &sx, int16_t &sy) {
    constexpr float DIST = 4.0f;
    constexpr float FOV  = 26.0f;
    float w = FOV / (v.z + DIST);
    sx = (int16_t)(v.x * w + 64.0f);
    sy = (int16_t)(v.y * w + 32.0f);
}

static void drawCube(float pitch, float roll) {
    float cp = cosf(pitch), sp = sinf(pitch);
    float cr = cosf(roll),  sr = sinf(roll);

    int16_t px[8], py[8];
    for (int i = 0; i < 8; i++) {
        float x = VERTS[i].x, y = VERTS[i].y, z = VERTS[i].z;
        // Rotate around Y (roll — tilting left/right)
        float x1 =  cr*x + sr*z;
        float y1 =  y;
        float z1 = -sr*x + cr*z;
        // Rotate around X (pitch — tilting forward/back)
        float x2 =  x1;
        float y2 =  cp*y1 - sp*z1;
        float z2 =  sp*y1 + cp*z1;
        project({x2, y2, z2}, px[i], py[i]);
    }

    display.clearDisplay();
    for (int e = 0; e < 12; e++) {
        int a = EDGES[e][0], b = EDGES[e][1];
        display.drawLine(px[a], py[a], px[b], py[b], SSD1306_WHITE);
    }
    display.display();
}

// ---- Process a fully received 6-byte data frame ----
static void processFrame(const uint8_t *d) {
    int16_t raw_x = (int16_t)((d[1] << 8) | d[0]);
    int16_t raw_y = (int16_t)((d[3] << 8) | d[2]);
    int16_t raw_z = (int16_t)((d[5] << 8) | d[4]);
    Serial.printf("X=%d Y=%d Z=%d\n", raw_x, raw_y, raw_z);

    // Normalize to approximate g units (full-res: 1g ≈ 256 LSBs)
    float ax = raw_x / 256.0f;
    float ay = raw_y / 256.0f;
    float az = raw_z / 256.0f;

    g_roll  = atan2f(ax,  az);
    g_pitch = atan2f(-ay, sqrtf(ax*ax + az*az));
    g_new   = true;
}

// ---- Parse incoming bytes ----
static void readSerial() {
    while (FpgaSerial.available()) {
        uint8_t b = (uint8_t)FpgaSerial.read();
        switch (rx_state) {
            case WAIT_FF:
                if (b == 0xFF) { rx_idx = 0; rx_state = READ_DATA; }
                break;
            case READ_DATA:
                rx_buf[rx_idx++] = b;
                if (rx_idx == 6) { processFrame(rx_buf); rx_state = WAIT_FF; }
                break;
        }
    }
}

void setup() {
    Serial.begin(115200);
    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR)) {
        Serial.println("OLED init failed");
        for (;;);
    }

    // RX = GPIO17 (from FPGA ARDUINO_IO[1] / PIN_AB6), TX unused
    FpgaSerial.begin(ACCEL_BAUD, SERIAL_8N1, PIN_FPGA_RX, PIN_FPGA_TX);

    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 20); display.println("  Accel 3D Cube");
    display.setCursor(0, 36); display.println(" Waiting for FPGA...");
    display.display();
    Serial.println("Challenge 2 — waiting for FPGA accel data...");
}

void loop() {
    readSerial();
    if (g_new) {
        g_new = false;
        drawCube(g_pitch, g_roll);
    }
}
