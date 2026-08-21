# NeckLife

A connected fall-detection necklace, designed to look like a piece of jewelry rather than a medical device.

Project developed as part of the RNCP 36463 certification — Concepteur Développeur d'Applications Numériques / Digital Application Designer-Developer (Ynov Bordeaux).

## Project description

NeckLife is an IoT system worn on the sternum that automatically detects falls using an inertial sensor (IMU), and alerts one or more caregivers via a mobile app when a fall is confirmed. The goal is to offer an alternative to traditional assistance devices (medical alert pendants, mainstream smartwatches), addressing their main limitations: stigmatizing design, dependency on a fixed base station, and false positives caused by wrist placement.

The wearer can:
- Be tracked in real time by one or more caregivers (with their explicit consent).
- Trigger a manual alert via a push button (SOS).
- Confirm or dismiss an automatically detected fall directly from the app.

The caregiver can:
- Monitor the necklace status and the wearer's fall history.
- Receive a notification when a fall is detected.
- View the wearer's location at the time of the alert (if location consent is active).

## Architecture

The system relies on a 3-tier architecture:

```
┌─────────────────┐        BLE        ┌──────────────────┐      Firebase SDK      ┌───────────────────┐
│   Tier 1         │ ───────────────▶ │   Tier 2           │ ──────────────────▶  │   Tier 3            │
│   ESP32 necklace   │                  │   Flutter app       │                       │   Firebase backend   │
│   (MicroPython)   │ ◀─────────────── │   (Android / iOS)   │ ◀────────────────── │   (Firestore, Auth,   │
│                    │   commands        │                     │                       │    Cloud Functions)   │
└─────────────────┘                  └──────────────────┘                       └───────────────────┘
```

- **Tier 1 — Necklace (MicroPython firmware)**: acquires acceleration data from the IMU, runs the fall-detection algorithm locally (edge computing, finite state machine), transmits the alert and receives commands via a BLE server (GATT).
- **Tier 2 — Mobile app (Flutter)**: bridges the necklace and the internet, provides the user interface for both wearer and caregivers, relays alerts to the backend.
- **Tier 3 — Backend (Firebase)**: data persistence (Firestore), authentication (Firebase Auth), automatic caregiver notification via a Cloud Function triggered on alert creation.

No intermediate API server is used: the app accesses Firebase services directly through their official SDKs, with data access secured by Firestore rules (`firestore.rules`) rather than by a dedicated application layer.

## Project structure

```
Projet-RNCPNiv6-Necklife-/
├── README.md
├── firmware_esp32/                  # Necklace firmware (MicroPython)
│   ├── main.py                      # Entry point, main loop
│   ├── boot.py                      # Startup configuration
│   ├── fall_detector.py             # Fall-detection algorithm (FSM)
│   ├── ble_server.py                # BLE server (GATT)
│   ├── src/
│   │   └── fall_detector.py         # Copy used by the tests
│   └── test/
│       └── test_fall_detector.py    # Unit tests (pytest)
│
├── flutter_application_necklife/    # Mobile application
│   ├── lib/
│   │   ├── main.dart                # App entry point
│   │   ├── core/
│   │   │   └── api/
│   │   │       └── api_client.dart  # Not currently used (direct access via Firebase SDK)
│   │   └── features/
│   │       ├── auth/
│   │       │   ├── login_screen.dart
│   │       │   └── auth_service.dart
│   │       ├── home/
│   │       │   └── home_screen.dart
│   │       ├── imu/
│   │       │   └── imu_screen.dart      # "My curve" screen
│   │       ├── profile/
│   │       │   └── profile_screen.dart
│   │       ├── sos/
│   │       │   └── sos_screen.dart
│   │       └── services/
│   │           ├── link_code_service.dart
│   │           ├── location_service.dart
│   │           └── push_service.dart
│   └── pubspec.yaml
│
├── functions/                       # Firebase backend (Cloud Functions)
│   ├── index.js                     # notifierChuteDetectee Cloud Function
│   ├── package.json
│   └── package-lock.json
│
├── firestore.rules                  # Firestore security rules
├── firebase.json                    # Firebase project configuration
└── .firebaserc                      # Firebase project alias
```

## Hardware list

| Component | Reference | Role |
|---|---|---|
| Microcontroller | ESP32-C3 Super Mini | Runs the firmware, reads the IMU, handles BLE communication |
| IMU sensor | MPU-6050 | Measures acceleration and angular velocity on 3 axes |
| Buzzer | Passive buzzer | Audible alarm when a fall is detected |
| Push button | — | Manual SOS alert trigger / alarm stop |
| Battery | 3.7V LiPo | Powers the necklace |
| Charging module | TP4056 | Charges the battery via USB |
| Switch | ON/OFF, 3 pins | Powers the necklace on/off |

## Wiring diagram (ESP32 ↔ IMU / Button / Buzzer)

Wiring of the active detection-system components, excluding the power circuit:

```
                     ESP32-C3 Super Mini
                    ┌───────────────────┐
                    │                    │
      IMU MPU-6050  │                    │
   ┌───────────┐    │                    │
   │       VCC ├────┤ 3V3                │
   │       GND ├────┤ GND                │
   │       SCL ├────┤ GPIO9  (I2C SCL)   │
   │       SDA ├────┤ GPIO8  (I2C SDA)   │
   └───────────┘    │                    │
                    │                    │
   Push button        │                    │
   ┌───────────┐    │                    │
   │   Signal  ├────┤ GPIO2  (internal  │
   │           │    │         pull-up)   │
   │       GND ├────┤ GND                │
   └───────────┘    │                    │
                    │                    │
   Passive buzzer     │                    │
   ┌───────────┐    │                    │
   │   Signal  ├────┤ GPIO4              │
   │        +  ├────┤ 3V3                │
   │        -  ├────┤ GND                │
   └───────────┘    │                    │
                    └───────────────────┘
```

**Wiring details:**

| Component | Pin | ESP32-C3 Pin | Note |
|---|---|---|---|
| IMU MPU-6050 | VCC | 3V3 | — |
| IMU MPU-6050 | GND | GND | — |
| IMU MPU-6050 | SCL | GPIO9 | I2C bus |
| IMU MPU-6050 | SDA | GPIO8 | I2C bus — 4.7 kΩ pull-ups to 3.3V required if not present on the module |
| Push button | Signal | GPIO2 | Internal pull-up enabled in software |
| Push button | GND | GND | — |
| Passive buzzer | Signal | GPIO4 | — |
| Passive buzzer | + | 3V3 | — |
| Passive buzzer | − | GND | — |

> The power circuit (battery, TP4056 charging module, switch) is wired upstream of the ESP32-C3 and is not represented here.

## Installation and setup

### Firmware
1. Flash MicroPython onto the ESP32-C3.
2. Copy the files from the `firmware_esp32/` folder onto the board using the MicroPico extension (VS Code).
3. Run `main.py` from the REPL.

_Use the MicroPico extension._

### Flutter application
```bash
cd flutter_application_necklife
flutter pub get
flutter run
```

### Firebase backend
```bash
firebase login
firebase deploy --only firestore:rules
firebase deploy --only functions
```

> Deploying Cloud Functions requires Firebase's Blaze (pay-as-you-go) billing plan.

## Tests

The firmware unit tests run with pytest:
```bash
pytest firmware_esp32/test/test_fall_detector.py -v
```

## Author

Erika Lajus — [github.com/erikaljs](https://github.com/erikaljs)