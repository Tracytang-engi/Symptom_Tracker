/**
 * symptom_tracker_diag.ino
 *
 * 裸 ESP32 分步硬件诊断（不初始化 BLE / I2S / SPIFFS）
 *
 * 默认只测 GPIO25(SOS) 与 GPIO26(REC)。
 * 确认独立后再用命令测 FSR / LED / GPIO27 / 短脉冲马达。
 *
 * Arduino IDE：
 *   Board = ESP32 Dev Module
 *   Upload Speed = 115200（建议）
 *   Erase Flash = Disabled（除非必须）
 *   串口监视器 = 115200
 *
 * 建议：ESP32 先不插洞洞板，只用 USB。
 */

#include <Arduino.h>

static const int PIN_SOS   = 25;
static const int PIN_REC   = 26;
static const int PIN_FSR   = 34;
static const int PIN_LED   = 13;
static const int PIN_MOTOR = 27;

static const int FSR_IDLE_MAX   = 200;   // 未按压常见上限（约）
static const int FSR_PRESS_MIN  = 400;   // 明显按压下限（约）

static bool motorPwmReady = false;
static uint32_t lastPrintMs = 0;

static void printHelp() {
  Serial.println();
  Serial.println("======== ESP32 裸板分步诊断 ========");
  Serial.println("命令:");
  Serial.println("  H  帮助");
  Serial.println("  1  步骤1说明：GPIO25/26（默认一直在跑）");
  Serial.println("  2  步骤2说明：GPIO34/FSR");
  Serial.println("  3  步骤3：点亮 GPIO13 LED 1秒");
  Serial.println("  4  步骤4说明：GPIO27 电压自测");
  Serial.println("  5  步骤5：GPIO27 保持 HIGH 5秒（方便万用表；先不接马达）");
  Serial.println("  V  GPIO27 保持 HIGH 直到输入 O（读电压最稳）");
  Serial.println("  6  步骤6：GPIO27 短脉冲 150ms（可接马达，仅一次短振）");
  Serial.println("  O  GPIO27 强制 LOW");
  Serial.println("  S  立刻打印一次 25/26/34");
  Serial.println("===================================");
  Serial.println();
}

static void printStep1() {
  Serial.println();
  Serial.println("----- 步骤1：GPIO25 / GPIO26 -----");
  Serial.println("接线（裸板，无洞洞板）：");
  Serial.println("  两脚悬空；用杜邦线临时对 GND 短接做测试。");
  Serial.println("  不要同时把 25 和 26 接到同一根 GND 测试线上并缠在一起造成误判。");
  Serial.println();
  Serial.println("正常：");
  Serial.println("  悬空:     GPIO25=1  GPIO26=1");
  Serial.println("  只短25地: GPIO25=0  GPIO26=1");
  Serial.println("  只短26地: GPIO25=1  GPIO26=0");
  Serial.println("  电压(悬空): 对 GND 约 3.0~3.3V");
  Serial.println("  电压(接地): 约 0~0.2V");
  Serial.println();
  Serial.println("异常：");
  Serial.println("  悬空已是 0 0     → 引脚对地损坏/板上仍有短路物");
  Serial.println("  短一个变 0 0     → 25 与 26 仍互连（芯片外或排针残留焊锡）");
  Serial.println("  短地不变 0       → 该 GPIO 开路损坏，或测到了错误焊盘");
  Serial.println("----------------------------------");
  Serial.println();
}

static void printStep2() {
  Serial.println();
  Serial.println("----- 步骤2：GPIO34 / FSR -----");
  Serial.println("接线：");
  Serial.println("  3V3 -- FSR一端");
  Serial.println("  FSR另一端 -- GPIO34");
  Serial.println("  GPIO34 -- 10kΩ -- GND");
  Serial.println();
  Serial.println("正常（串口每行里的 FSR=）：");
  Serial.println("  未按: 大约 0~200");
  Serial.println("  按压: 明显升高，常 >400，重按可达上千");
  Serial.println("  此时 GPIO25/26 必须仍保持 1（除非你同时短接了按钮脚）");
  Serial.println();
  Serial.println("异常：");
  Serial.println("  一直 0 且按压不变 → 3V3未接到FSR / FSR断线 / 34未接到");
  Serial.println("  一直很高(~4095) → 34被拉到3V3，或下拉10k缺失/接到3V3");
  Serial.println("  按FSR时25/26变0 → 仍有共地/共铜箔串扰，先别上洞洞板整板");
  Serial.println("----------------------------------");
  Serial.println();
}

static void printStep4() {
  Serial.println();
  Serial.println("----- 步骤4：GPIO27 输出能力（先不接三极管）-----");
  Serial.println("接线：GPIO27 悬空，万用表红笔 GPIO27，黑笔 GND。");
  Serial.println("操作（二选一）：");
  Serial.println("  输入 5 → GPIO27 保持 HIGH 约 5 秒，然后自动 LOW");
  Serial.println("  输入 V → GPIO27 一直 HIGH，读完后输入 O 关掉");
  Serial.println();
  Serial.println("正常：");
  Serial.println("  LOW 时:  ~0V");
  Serial.println("  HIGH 时: ~3.2~3.3V");
  Serial.println();
  Serial.println("异常：");
  Serial.println("  拉高仍接近 0V → GPIO27 损坏或对地短路");
  Serial.println("  输入 O 后仍 ~3.3V → 对 3V3 短路");
  Serial.println("----------------------------------");
  Serial.println();
}

static void motorPinSafe() {
  if (motorPwmReady) {
    ledcWrite(PIN_MOTOR, 0);
    motorPwmReady = false;
  }
  pinMode(PIN_MOTOR, OUTPUT);
  digitalWrite(PIN_MOTOR, LOW);
}

static void pulseGpio27High(uint16_t ms) {
  motorPinSafe();
  Serial.printf("[GPIO27] HIGH %u ms（可测电压）...\n", ms);
  digitalWrite(PIN_MOTOR, HIGH);
  // 每秒提示一次，方便对准表笔
  uint16_t left = ms;
  while (left > 0) {
    const uint16_t slice = left > 1000 ? 1000 : left;
    delay(slice);
    left -= slice;
    if (left > 0) {
      Serial.printf("  ...仍 HIGH，剩余约 %u ms\n", left);
    }
  }
  digitalWrite(PIN_MOTOR, LOW);
  Serial.println("[GPIO27] LOW（结束）");
}

static void holdGpio27HighUntilCancel() {
  motorPinSafe();
  digitalWrite(PIN_MOTOR, HIGH);
  Serial.println("[GPIO27] 已保持 HIGH");
  Serial.println("  现在用万用表测 GPIO27↔GND，应约 3.3V");
  Serial.println("  读完后输入 O 关掉");
}

static void pulseLed() {
  Serial.println("[LED] GPIO13 HIGH 1000 ms");
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);
  delay(1000);
  digitalWrite(PIN_LED, LOW);
  pinMode(PIN_LED, INPUT);
  Serial.println("[LED] 结束（GPIO13 高阻）");
  Serial.println("正常: LED亮1秒。不亮→LED反接/电阻断/GPIO13坏/未共地");
}

static void printSnapshot() {
  const int sos = digitalRead(PIN_SOS);
  const int rec = digitalRead(PIN_REC);
  const int fsr = analogRead(PIN_FSR);
  Serial.printf("GPIO25=%d  GPIO26=%d  FSR=%d", sos, rec, fsr);
  if (sos == 1 && rec == 1) Serial.print("  | 两键悬空OK?");
  if (sos == 0 && rec == 1) Serial.print("  | 仅25低");
  if (sos == 1 && rec == 0) Serial.print("  | 仅26低");
  if (sos == 0 && rec == 0) Serial.print("  | 双低(异常或双接地)");
  if (fsr >= FSR_PRESS_MIN) Serial.print("  | FSR似按下");
  Serial.println();
}

static void handleCmd(char c) {
  switch (c) {
    case 'H': case 'h': case '?':
      printHelp();
      break;
    case '1':
      printStep1();
      break;
    case '2':
      printStep2();
      break;
    case '3':
      Serial.println();
      Serial.println("----- 步骤3：GPIO13 LED -----");
      Serial.println("接线: GPIO13 -- 220~330Ω -- LED(+) ; LED(-) -- GND");
      Serial.println("正常: 输入3后亮约1秒；GPIO13对地脉冲约3.3V");
      Serial.println("异常: 不亮→极性/电阻/开路；一直亮→短路到3V3");
      pulseLed();
      break;
    case '4':
      printStep4();
      break;
    case '5':
      Serial.println();
      Serial.println("----- 步骤5：GPIO27 / 三极管（先不接马达）-----");
      Serial.println("空载测脚：GPIO27 悬空，输入5，表笔测 5 秒内电压。");
      Serial.println("接三极管时：");
      Serial.println("  GPIO27 -- 1kΩ -- B ; E -- GND ; 马达断开");
      Serial.println("正常 HIGH: GPIO27≈3.3V；C 被拉通");
      Serial.println("异常: 拉高仍≈0 → GPIO27坏；未驱动C已对地短 → 换管");
      Serial.println("若 5 秒仍不够，改用命令 V（保持到 O）");
      pulseGpio27High(5000);
      break;
    case 'V': case 'v':
      holdGpio27HighUntilCancel();
      break;
    case '6':
      Serial.println();
      Serial.println("----- 步骤6：马达短脉冲（150ms）-----");
      Serial.println("接线:");
      Serial.println("  GPIO27 -- 1kΩ -- B");
      Serial.println("  E -- GND");
      Serial.println("  马达+ -- 3V3");
      Serial.println("  马达- -- C");
      Serial.println("  二极管: 条纹(阴极)--3V3/马达+ ; 无条纹(阳极)--C/马达-");
      Serial.println("正常: 短促一振后停止；3V3不明显崩溃");
      Serial.println("异常: 长转/发烫/3V3骤降→立刻拔USB，查二极管/三极管");
      Serial.println("注意: 仅短脉冲，旧管可能已受损，异常即停");
      pulseGpio27High(150);
      break;
    case 'O': case 'o':
      motorPinSafe();
      Serial.println("[GPIO27] 已强制 LOW");
      break;
    case 'S': case 's':
      printSnapshot();
      break;
    case '\r': case '\n': case ' ':
      break;
    default:
      Serial.printf("未知 '%c'，输入 H\n", c);
      break;
  }
}

void setup() {
  Serial.begin(115200);
  delay(400);

  // 只初始化输入；不碰 BLE / I2S / FS
  pinMode(PIN_SOS, INPUT_PULLUP);
  pinMode(PIN_REC, INPUT_PULLUP);
  pinMode(PIN_FSR, INPUT);
  pinMode(PIN_LED, INPUT);
  motorPinSafe();
  analogReadResolution(12);

  printHelp();
  printStep1();
  Serial.println("开始连续打印 GPIO25/26（每200ms）。按上面步骤操作。");
  Serial.println();
}

void loop() {
  while (Serial.available()) {
    handleCmd((char)Serial.read());
  }

  if (millis() - lastPrintMs < 200) return;
  lastPrintMs = millis();
  printSnapshot();
}
