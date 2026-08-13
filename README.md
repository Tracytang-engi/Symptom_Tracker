# Symptom Tracker

Portable pain-event recorder: an **ESP32** hand device with FSR pressure sensing, optional voice notes, and SOS — plus a **Flutter** companion app for timelines, pressure curves, tags, and caregiver settings.

**Repo:** [github.com/Tracytang-engi/Symptom_Tracker](https://github.com/Tracytang-engi/Symptom_Tracker)

---

## What it does

1. User presses the force sensor (FSR) during a pain episode.
2. The device records duration and a pressure curve, with vibration feedback.
3. Events sync to the phone/tablet over **Bluetooth Low Energy** (works offline on-device, then syncs when connected).
4. Optional **voice note** (INMP441 mic) and **SOS** long-press (with location on the app side).
5. The app shows a timeline, charts, tags, and an **Accessible Mode** for simpler day-to-day use.

---

## Features

### Device (ESP32 firmware — `symptom_tracker/`)

- FSR press detection with debounce and event merge
- Real-time pressure stream + vibration (PWM motor)
- Offline event queue (SPIFFS) and BLE sync
- Voice notes via I2S mic (INMP441), file transfer over BLE
- SOS button (long-press) and status LED
- Separate REC button for voice notes after / during an episode

### Companion app (`symptom_tracker_app/`)

- BLE connect / disconnect, live pressure gauge
- Timeline, event detail (curve, peak, average, duration)
- Tags, voice playback, post-event prompts
- Calibration, vibration, appearance, privacy / export settings
- **Accessible Mode** — larger UI, Home + Timeline only, 2×2 action grid, 4 quick tags, SOS long-press
- Guardian / SOS flow for caregivers

### Hardware test sketches

| Folder | Purpose |
|--------|---------|
| `symptom_tracker_mic_test/` | INMP441 mic |
| `symptom_tracker_led_test/` | Status LED |
| `symptom_tracker_motor_fsr_test/` | Motor + FSR |
| `symptom_tracker_diag/` | Diagnostics |
| `mic_test/` | Minimal mic sketch |

---

## Hardware (main pins)

| Function | GPIO | Notes |
|----------|------|--------|
| FSR signal | 34 | ADC1; 10 kΩ to GND; other side of FSR → 3.3 V |
| Motor / vib PWM | 27 | Prefer transistor + flyback diode for a real motor |
| SOS button | 25 | INPUT_PULLUP, hold ~2 s |
| REC button | 26 | INPUT_PULLUP |
| Status LED | 13 | Active-low: 3.3 V → resistor → LED → GPIO13 |
| Mic SCK | 14 | INMP441 |
| Mic WS | 15 | INMP441 |
| Mic SD | 32 | INMP441; L/R → GND for LEFT slot |

BLE advertised name: **`SymptomTracker`**.

Pin and timing constants live in [`symptom_tracker/config.h`](symptom_tracker/config.h).

---

## Repository layout

```
Symptom_Tracker/
├── symptom_tracker/           # Arduino / ESP32 main firmware
├── symptom_tracker_app/       # Flutter app (Android primary)
├── symptom_tracker_*_test/    # Standalone hardware tests
└── README.md
```

---

## Build & flash — firmware

**Requirements**

- Arduino IDE (or PlatformIO) with **ESP32** board support
- Board: ESP32 Dev Module (or your module)
- SPIFFS / LittleFS data upload if you use on-device file storage tools for your toolchain

**Steps**

1. Open `symptom_tracker/symptom_tracker.ino`.
2. Select the correct board and port.
3. Upload.
4. Open Serial Monitor (115200) for debug if needed.

For isolated bring-up, flash the sketches under `symptom_tracker_*_test/` first.

---

## Build & run — Flutter app

**Requirements**

- [Flutter](https://docs.flutter.dev/get-started/install) (SDK matching `pubspec.yaml`: Dart `>=3.0.0 <4.0.0`)
- Android device/emulator with Bluetooth (real device recommended for BLE)

```bash
cd symptom_tracker_app
flutter pub get
flutter run
# or release APK:
flutter build apk --release
```

On first run, grant Bluetooth, location (for BLE scan / SOS), microphone, and notification permissions as prompted.

**Typical flow**

1. Turn on Accessible Mode (or use full Settings as a caregiver).
2. Connect to **SymptomTracker**.
3. Press the FSR → watch the gauge → release → check Timeline.
4. Optionally add a tag or voice note; long-press SOS to test the alert path.

---

## Accessible Mode (quick note)

Designed for adults who prefer a simpler UI:

- Larger text and tap targets
- Bottom nav: **Home** / **Timeline** only
- Home **2×2** actions (Connect, Manual, SOS, Accessible)
- Four picture tags: After Meal · After Exercise · During Sleep · After Medication
- SOS requires a **long press** to reduce accidental triggers

Caregivers can turn Accessible Mode off to reach calibration, BLE info, labels, Stats, Guardian, and export options under **Settings**.

---

## Tech stack

| Layer | Stack |
|-------|--------|
| Firmware | C++ / Arduino, ESP32 BLE, I2S, SPIFFS |
| App | Flutter, Riverpod, flutter_blue_plus, Hive, fl_chart |
| Radio | BLE GATT notify / write (events, pressure, file transfer) |

---

## Privacy

Events and audio stay on the phone/tablet (local Hive / files) unless the user exports them. Treat voice notes and location from SOS as sensitive personal data.

---

## License

No license file is attached yet. All rights reserved by the author unless otherwise stated. Add a `LICENSE` if you want to open-source under a specific terms.
