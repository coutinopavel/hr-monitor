/*
  Monitor FC — XIAO nRF52840 + MAX30102
  Board package: Adafruit nRF52 (usa <bluefruit.h>)
  Board seleccionada: Adafruit Feather nRF52840 Express

  Conexión MAX30102:
    SDA → D4
    SCL → D5
    VIN → 3.3V  (NO 5V)
    GND → GND

  UUIDs deben coincidir con Flutter:
    Service : 12345678-1234-1234-1234-1234567890ab
    TX (notify) : 12345678-1234-1234-1234-1234567890ac
    RX (write)  : 12345678-1234-1234-1234-1234567890ad
*/

#include <bluefruit.h>
#include <Wire.h>

// ── UUIDs ──────────────────────────────────────
#define SERVICE_UUID "12345678-1234-1234-1234-1234567890ab"
#define TX_CHAR_UUID "12345678-1234-1234-1234-1234567890ac"
#define RX_CHAR_UUID "12345678-1234-1234-1234-1234567890ad"

// ── MAX30102 registros ──────────────────────────
#define MAX30102_ADDR   0x57
#define REG_FIFO_WR_PTR 0x04
#define REG_OVF_COUNTER 0x05
#define REG_FIFO_RD_PTR 0x06
#define REG_FIFO_DATA   0x07
#define REG_FIFO_CONFIG 0x08
#define REG_MODE_CONFIG 0x09
#define REG_SPO2_CONFIG 0x0A
#define REG_LED1_PA     0x0C
#define REG_LED2_PA     0x0D

// ── BLE ────────────────────────────────────────
BLEService        sensorService(SERVICE_UUID);
BLECharacteristic txChar(TX_CHAR_UUID);
BLECharacteristic rxChar(RX_CHAR_UUID);

bool g_enviando = false;

// ── MAX30102 helpers ───────────────────────────
void max_write(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MAX30102_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

uint8_t max_read(uint8_t reg) {
  Wire.beginTransmission(MAX30102_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MAX30102_ADDR, 1);
  return Wire.available() ? Wire.read() : 0xFF;
}

bool max30102_init() {
  Wire.begin();
  delay(100);

  // Verificar que el sensor responde en 0x57
  Wire.beginTransmission(MAX30102_ADDR);
  if (Wire.endTransmission() != 0) return false;

  // Reset completo
  max_write(REG_MODE_CONFIG, 0x40);
  delay(200);

  // Limpiar FIFO
  max_write(REG_FIFO_WR_PTR, 0x00);
  max_write(REG_OVF_COUNTER, 0x00);
  max_write(REG_FIFO_RD_PTR, 0x00);

  // Configurar:
  //   FIFO: avg=4 muestras, rollover habilitado, 17 muestras antes de interrupción
  //   Modo: SpO2 (IR + Red)
  //   ADC: 4096nA, 100Hz, 411us pulso
  //   LEDs: ~7mA
  max_write(REG_FIFO_CONFIG, 0x5F);
  max_write(REG_MODE_CONFIG, 0x03);
  max_write(REG_SPO2_CONFIG, 0x27);
  max_write(REG_LED1_PA,     0x24);
  max_write(REG_LED2_PA,     0x24);

  return true;
}

bool max30102_read(uint32_t &ir, uint32_t &red) {
  uint8_t wr = max_read(REG_FIFO_WR_PTR);
  uint8_t rd = max_read(REG_FIFO_RD_PTR);
  if (wr == rd) return false;  // FIFO vacío

  Wire.beginTransmission(MAX30102_ADDR);
  Wire.write(REG_FIFO_DATA);
  Wire.endTransmission(false);
  Wire.requestFrom(MAX30102_ADDR, 6);

  if (Wire.available() < 6) return false;

  // El MAX30102 en modo SpO2 manda: RED primero, luego IR
  red = ((uint32_t)(Wire.read() & 0x03) << 16)
      | ((uint32_t)Wire.read() << 8)
      |  Wire.read();
  ir  = ((uint32_t)(Wire.read() & 0x03) << 16)
      | ((uint32_t)Wire.read() << 8)
      |  Wire.read();

  // Avanzar puntero de lectura
  max_write(REG_FIFO_RD_PTR, (rd + 1) & 0x1F);
  return true;
}

// ── BLE callbacks ──────────────────────────────
void rxCB(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t len) {
  if (len > 0) {
    g_enviando = (data[0] == '1');
    Serial.printf("[RX] enviando=%d\n", g_enviando);
  }
}

void onConnect(uint16_t) {
  Serial.println("[BLE] Conectado");
}

void onDisconnect(uint16_t, uint8_t) {
  g_enviando = false;
  Serial.println("[BLE] Desconectado — volviendo a anunciar");
  Bluefruit.Advertising.start(0);
}

// ── Setup ──────────────────────────────────────
void setup() {
  Serial.begin(115200);

  // Esperar Serial hasta 4s sin bloquear indefinidamente
  unsigned long t = millis();
  while (!Serial && millis() - t < 4000);
  delay(200);

  Serial.println("=== Monitor FC ===");

  // Iniciar sensor
  if (!max30102_init()) {
    Serial.println("ERROR: MAX30102 no encontrado en 0x57");
    Serial.println("Revisa: SDA->D4, SCL->D5, VIN->3.3V, GND->GND");
    // Parpadear LED para indicar error sin bloquear el BLE
    pinMode(LED_RED, OUTPUT);
    while (true) {
      digitalWrite(LED_RED, LOW);  delay(200);
      digitalWrite(LED_RED, HIGH); delay(200);
    }
  }
  Serial.println("MAX30102 OK");

  // Iniciar BLE
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("MAX30102 BLE");   // <-- nombre que busca Flutter

  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);

  // Servicio
  sensorService.begin();

  // TX: Flutter se suscribe aquí para recibir "ir,red"
  txChar.setProperties(CHR_PROPS_NOTIFY);
  txChar.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  txChar.setMaxLen(32);
  txChar.begin();

  // RX: Flutter escribe "1" para iniciar, "0" para detener
  rxChar.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  rxChar.setPermission(SECMODE_OPEN, SECMODE_OPEN);
  rxChar.setMaxLen(4);
  rxChar.setWriteCallback(rxCB);
  rxChar.begin();

  // Advertising
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(sensorService);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);

  Serial.println("[BLE] Listo. Esperando conexion de Flutter...");
}

// ── Loop ───────────────────────────────────────
void loop() {
  uint32_t ir = 0, red = 0;

  if (!max30102_read(ir, red)) {
    delay(10);
    return;
  }

  // Siempre imprimir en Serial para diagnóstico
  Serial.printf("IR=%lu  RED=%lu\n", ir, red);

  // Enviar por BLE solo si Flutter lo pidió
  if (g_enviando && Bluefruit.connected()) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lu,%lu", ir, red);
    txChar.notify((uint8_t*)buf, strlen(buf));
  }

  delay(10);  // ~100Hz
}
