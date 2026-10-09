"""
Refactored from your app.py for the new architecture:

    OLD: Flask reads the ESP32 directly over a USB COM port (ESP32 had to be
         plugged into the same machine running Flask).
    NEW: Flutter reads the ESP32 over BLE, then POSTs the raw red/ir/f1/fz
         data to this Flask API over HTTP. Flask does feature extraction +
         prediction and returns JSON. No pyserial, no COM port, works with
         Flask hosted anywhere the phone can reach.

Same feature-extraction logic and same placeholder melanin correction as
your original app.py -- carried over as-is, still unvalidated (see the
same warning comment you already had).
"""
import joblib, numpy as np, pandas as pd
from scipy import signal as sig
from flask import Flask, request, jsonify

MODEL_PATH = "hb_model_phase1.joblib"

# --- PLACEHOLDER melanin correction constants (unchanged from your app.py) ---
# NOT calibrated - no real baseline/k derived from your own data yet.
# Literature-range guesses purely so the correction mechanism runs end-to-end.
# DO NOT present hb_corrected as a validated result until these are fit on
# real skin-tone-spread data.
MELANIN_BASELINE = 0.5
MELANIN_K = 1.0

model = joblib.load(MODEL_PATH)
app = Flask(__name__)


def extract_features(red, ir, fs=100):
    red, ir = np.array(red, float), np.array(ir, float)
    dc_r, dc_i = red.mean(), ir.mean()
    b, a = sig.butter(3, [0.5/(fs/2), 5/(fs/2)], btype='band')
    ac_r = sig.filtfilt(b, a, red)
    ac_i = sig.filtfilt(b, a, ir)
    pi_r, pi_i = 100*ac_r.std()/dc_r, 100*ac_i.std()/dc_i
    skew = pd.Series(ac_r).skew() - pd.Series(ac_i).skew()
    kurt = pd.Series(ac_r).kurt() - pd.Series(ac_i).kurt()
    return dict(DC_red=dc_r, DC_ir=dc_i, PI_red=pi_r, PI_ir=pi_i,
                R_value=pi_r/pi_i, skew=skew, kurt=kurt)


@app.route("/predict", methods=["POST"])
def predict():
    """
    Expected JSON body from Flutter:
    {
      "red": [ ...500 ints... ],
      "ir":  [ ...500 ints... ],
      "f1":  10.0,
      "fz":  82.0,
      "age": 30,
      "gender": "M"
    }
    """
    data = request.get_json(force=True)

    required = ["red", "ir", "f1", "fz", "age", "gender"]
    missing = [k for k in required if k not in data]
    if missing:
        return jsonify({"error": f"missing fields: {missing}"}), 400

    red, ir = data["red"], data["ir"]
    f1, fz = float(data["f1"]), float(data["fz"])
    age = float(data["age"])
    gender_m = 1 if str(data["gender"]).strip().upper().startswith("M") else 0

    if len(red) < 50 or len(ir) < 50:
        return jsonify({"error": "red/ir buffers too short for feature extraction"}), 400

    feats = extract_features(red, ir)
    X = np.array([[feats["PI_red"], feats["PI_ir"], feats["R_value"],
                    feats["skew"], feats["kurt"], gender_m, age]])
    hb_raw = round(float(model.predict(X)[0]), 2)

    melanin_index = round(f1 / fz, 3) if fz != 0 else None
    hb_corrected = None
    if melanin_index is not None:
        hb_corrected = round(hb_raw - MELANIN_K * (melanin_index - MELANIN_BASELINE), 2)

    return jsonify({
        "hb_raw": hb_raw,
        "hb_corrected": hb_corrected,
        "melanin_index": melanin_index,
        "melanin_correction_validated": False,   # be explicit in the API contract, not just a code comment
        "features": {k: (round(v, 4) if isinstance(v, float) else v) for k, v in feats.items()},
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    # host="0.0.0.0" so a phone on the same network (or via port-forwarding/ngrok
    # for internet access) can actually reach this -- 127.0.0.1 would only
    # accept connections from this same machine.
    app.run(host="0.0.0.0", port=5000, debug=True)
