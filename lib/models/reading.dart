/// A single raw sensor reading pulled from the ESP32 over BLE,
/// before it's sent to Flask for feature extraction + prediction.
class SensorReading {
  final List<int> red;
  final List<int> ir;
  final double f1;
  final double fz;

  SensorReading({
    required this.red,
    required this.ir,
    required this.f1,
    required this.fz,
  });

  Map<String, dynamic> toJson({required int age, required String gender}) => {
        'red': red,
        'ir': ir,
        'f1': f1,
        'fz': fz,
        'age': age,
        'gender': gender,
      };
}

/// The prediction result returned by Flask's /predict endpoint.
class HbResult {
  final double hbRaw;
  final double? hbCorrected;
  final double? melaninIndex;
  final bool melaninCorrectionValidated;

  HbResult({
    required this.hbRaw,
    required this.hbCorrected,
    required this.melaninIndex,
    required this.melaninCorrectionValidated,
  });

  factory HbResult.fromJson(Map<String, dynamic> json) => HbResult(
        hbRaw: (json['hb_raw'] as num).toDouble(),
        hbCorrected: (json['hb_corrected'] as num?)?.toDouble(),
        melaninIndex: (json['melanin_index'] as num?)?.toDouble(),
        melaninCorrectionValidated:
            json['melanin_correction_validated'] as bool? ?? false,
      );
}
