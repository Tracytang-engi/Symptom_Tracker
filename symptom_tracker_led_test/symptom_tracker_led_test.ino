/**
 * symptom_tracker_led_test — 独立状态灯测试（无 BLE / 麦 / 马达）
 *
 * 当前接线（低电平点亮 / 灌电流）：
 *   Vin(或 3.3V) → 限流电阻 → LED(+) → LED(-) → GPIO13
 *   GPIO=LOW 亮，GPIO=HIGH 灭
 *
 * ⚠ 更安全：把 Vin 那一脚改接到 3.3V（经 220~330Ω），
 *   不要直接用 5V Vin 灌进 ESP32 引脚。
 *
 * 串口 115200：
 *   H     帮助
 *   1     亮
 *   0     灭
 *   T     翻转
 *   B     慢闪开关（500ms）
 *   F     快闪 5 次后灭
 */

#define LED_PIN  13
// 你的接法：一脚 D13、一脚 Vin → 低电平点亮
#define LED_ON_LEVEL   LOW
#define LED_OFF_LEVEL  HIGH

static bool blinkOn = false;
static uint32_t lastToggle = 0;
static bool ledState = false;

static void setLed(bool on) {
  digitalWrite(LED_PIN, on ? LED_ON_LEVEL : LED_OFF_LEVEL);
  ledState = on;
  Serial.printf("LED %s  (GPIO%d=%s)\n",
                on ? "ON" : "OFF", LED_PIN,
                (on ? LED_ON_LEVEL : LED_OFF_LEVEL) == HIGH ? "HIGH" : "LOW");
}

static void printHelp() {
  Serial.println();
  Serial.println("=== LED 测试 GPIO13 ===");
  Serial.println("1  亮");
  Serial.println("0  灭");
  Serial.println("T  翻转");
  Serial.println("B  慢闪开关");
  Serial.println("F  快闪 5 次");
  Serial.println("H  帮助");
  Serial.println();
}

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(LED_PIN, OUTPUT);
  setLed(false);  // 上电默认灭
  Serial.println("LED 独立测试");
  printHelp();
}

void loop() {
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    line.toUpperCase();
    if (line.length() == 0) return;

    if (line == "H" || line == "?") {
      printHelp();
    } else if (line == "1" || line == "ON") {
      blinkOn = false;
      setLed(true);
    } else if (line == "0" || line == "OFF") {
      blinkOn = false;
      setLed(false);
    } else if (line == "T") {
      blinkOn = false;
      setLed(!ledState);
    } else if (line == "B") {
      blinkOn = !blinkOn;
      lastToggle = millis();
      Serial.println(blinkOn ? "慢闪 ON" : "慢闪 OFF");
      if (!blinkOn) setLed(false);
    } else if (line == "F") {
      blinkOn = false;
      Serial.println("快闪 5 次...");
      for (int i = 0; i < 5; i++) {
        setLed(true);
        delay(80);
        setLed(false);
        delay(80);
      }
    } else {
      Serial.println("未知，发 H");
    }
  }

  if (blinkOn && millis() - lastToggle >= 500) {
    lastToggle = millis();
    setLed(!ledState);
  }
}
