/**
 * symptom_tracker_motor_fsr_test — 马达跟随 FSR 压力（独立验证，无 BLE）
 *
 * 接线（与主工程一致）：
 *   FSR：一端 3.3V，一端 GPIO34，GPIO34 经 10k 下拉 GND
 *   马达：GPIO27 → 基极电阻 → NPN → 低边开关马达（续流二极管并联马达）
 *
 * 串口 115200：
 *   按压 FSR，看马达是否随力度变强，并观察打印的 FSR / PWM
 *   H  帮助
 *   Z  强制马达全开 1 秒（对照硬件）
 *   0  马达关闭
 */

#define FSR_PIN     34
#define MOTOR_PIN   27

#define FSR_THRESHOLD  200
#define FSR_MAP_MAX    1500
#define PWM_MIN        65
#define PWM_MAX        255
#define LEDC_FREQ_HZ   5000
#define LEDC_RES_BITS  8

static void pwmWrite(uint8_t v) {
  ledcWrite(MOTOR_PIN, v);
}

static void printHelp() {
  Serial.println();
  Serial.println("=== 马达跟随 FSR 测试 ===");
  Serial.println("按压 FSR：PWM 随压力变化（无需 App）");
  Serial.println("Z  全开 1 秒（硬件对照）");
  Serial.println("0  关闭马达");
  Serial.println("H  帮助");
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  delay(300);

  analogReadResolution(12);
  ledcAttach(MOTOR_PIN, LEDC_FREQ_HZ, LEDC_RES_BITS);
  pwmWrite(0);

  Serial.println("Motor+FSR 跟随测试");
  printHelp();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    line.toUpperCase();
    if (line == "H" || line == "?") {
      printHelp();
    } else if (line == "Z") {
      Serial.println("全开 1s...");
      pwmWrite(PWM_MAX);
      delay(10000);
      pwmWrite(0);
      Serial.println("已关");
    } else if (line == "0") {
      pwmWrite(0);
      Serial.println("马达 OFF");
    }
  }

  uint16_t raw = (uint16_t)analogRead(FSR_PIN);
  uint8_t pwm = 0;

  if (raw >= FSR_THRESHOLD) {
    uint16_t clamped = (raw < FSR_MAP_MAX) ? raw : FSR_MAP_MAX;
    pwm = (uint8_t)map(clamped, FSR_THRESHOLD, FSR_MAP_MAX, PWM_MIN, PWM_MAX);
  }
  pwmWrite(pwm);

  static uint32_t lastPrint = 0;
  if (millis() - lastPrint >= 200) {
    lastPrint = millis();
    Serial.printf("FSR=%4u  PWM=%3u  (%.0f%%)\n",
                  raw, pwm, pwm * 100.0f / 255.0f);
  }

  delay(20);
}
