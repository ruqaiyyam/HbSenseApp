# HbSense — Non-Invasive Hemoglobin Detection

HbSense estimates hemoglobin (Hb) levels non-invasively using PPG (MAX30102) and
spectral (AS7343) signals from a fingertip, with an ESP32 running the sensors
and a Flutter app handling the measurement flow, ML prediction, and results.

> **Status:** Student project / proof of concept. Not a medical device. Hb
> predictions have **not** been clinically validated — see
> [Validation status](#validation-status) below before presenting results as accurate.

---

## How it works

1. **ESP32** collects ~5 seconds of raw PPG (red/IR) samples from the MAX30102,
   plus one spectral reading from the AS7343, and streams both over **BLE** to
   the phone.
2. **Flutter app** receives the raw signal, sends it to the **Flask backend**
   along with age/gender, and gets back a predicted Hb value.
3. **Flask backend** extracts pulse-shape features (perfusion index, R-ratio,
   skew, kurtosis), runs them through a trained **ML model**, applies an
   (unvalidated) melanin-based correction, and returns the result.
4. The app displays raw Hb, corrected Hb, and Melanin Index. The ESP32's OLED
   mirrors the measurement flow (waiting → place finger → measuring →
   analysing → result).

```
ESP32 (MAX30102 + AS7343 + OLED)
        │  BLE
        ▼
   Flutter app  ───HTTP (/predict)───▶  Flask backend (cloud-hosted)
        ▲                                     │
        └──────────── result ─────────────────┘
```

---

## Repo structure

```
├── firmware/
│   └── firmware_hb_ble_sh1106_2.ino   # ESP32 firmware (BLE + sensors + OLED)
├── backend/
│   ├── app_api.py                     # Flask API used by the Flutter app
│   ├── app.py                         # Standalone test script (serial, browser UI)
│   └── hb_model_phase1.joblib         # Trained ML model (not committed — see below)
├── lib/                                # Flutter app source
│   ├── main.dart
│   ├── screens/home_screen.dart
│   ├── services/ble_service.dart
│   ├── services/api_service.dart
│   └── models/reading.dart
└── README.md
```

---

## Hardware

| Component | Notes |
|---|---|
| ESP32 (DOWD V3, 30-pin) | Runs sensors + BLE |
| MAX30102 | PPG (red/IR) sensor |
| AS7343 | 14-channel spectral sensor, used for Melanin Index (F1/FZ) |
| SH1106 128×64 OLED | I²C, address `0x3C` |
| MT3608 | Boost converter, battery → 5V |
| 3.7V Li-ion battery + charger module | Power |
| SPST switch | Power on/off |

All I²C devices (MAX30102, AS7343, OLED) share the same SDA/SCL bus. See
`firmware_hb_ble_sh1106_2.ino` for pin definitions.

---

## Setup

### 1. Firmware

1. Open `firmware/firmware_hb_ble_sh1106_2.ino` in Arduino IDE.
2. Install libraries: **U8g2** (olikraus), **Adafruit AS7343**, **SparkFun MAX3010x**.
3. Set `FINGER_IR_THRESHOLD` for your sensor/skin tone (see
   `ir_threshold_finder.ino` to measure this yourself).
4. Flash to the ESP32. It advertises as `HbSense-ESP32` over BLE.

### 2. Backend

```bash
cd backend
pip install -r requirements.txt   # flask, joblib, numpy, pandas, scipy
python app_api.py
```

By default this runs on `http://0.0.0.0:5000`. For the app to reach it:

- **Same WiFi network:** use your machine's LAN IP (`ipconfig` / `ifconfig`).
- **Cloud-hosted (recommended for sharing/demos):** deploy to
  [Render](https://render.com), Railway, or similar, and use the public URL.
  `app.run(debug=True)` is for local testing only — in production, start the
  app with a proper WSGI server instead:
  ```bash
  gunicorn app_api:app
  ```
  (On Render/Railway, set this as the service's start command. `gunicorn` is
  already in `requirements.txt`.)
- **USB only (no WiFi available):** run `adb reverse tcp:5000 tcp:5000` and
  use `http://127.0.0.1:5000` as the base URL (Android only).

> `hb_model_phase1.joblib` is required by `app_api.py` and `app.py` but is
> **not committed** to this repo (binary model files don't belong in git
> history). Get it from [teammate/drive link] and place it in `backend/`.

### 3. Flutter app

1. Set the backend URL in `lib/screens/home_screen.dart`:
   ```dart
   final _api = ApiService(baseUrl: 'https://your-backend-url');
   ```
2. `flutter pub get`
3. `flutter run`

On Android 12+, grant Bluetooth and Location permissions at runtime (BLE
scanning requires both). On older Android, enable system Location services.

---

## Validation status

The melanin correction formula is:

```
Hb_corrected = Hb_raw − K × (Melanin_Index − Baseline)
```

`K` and `Baseline` are currently **set to 0 / disabled by default**
(`MELANIN_K`, `MELANIN_BASELINE` in `app_api.py`). An initial calibration
attempt on 24 subjects found no statistically significant relationship
between Melanin Index and model error (p ≈ 0.99), likely because the sample
didn't span a wide enough range of skin tones. Melanin Index is still
computed and displayed for every reading so that **data collection can
continue** — recalibrate once a more diverse dataset (ideally spanning
Fitzpatrick I–VI, with ground-truth Hb from a reference device) is available.

Raw model accuracy on the same 24-subject pilot: MAE ≈ 1.5 g/dL. This should
be reported alongside any demo results.

---

## Known limitations

- Small pilot validation sample (24 subjects); not powered for clinical claims.
- Melanin correction is unvalidated and currently disabled (see above).
- MAX30102 sample rate is lower than the 100Hz assumed by the feature
  extraction in `app.py`/`app_api.py` — worth revisiting if the model is
  retrained.
- Not a certified medical device; for research/educational use only.

---


