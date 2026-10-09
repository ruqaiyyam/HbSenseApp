import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/reading.dart';

class ApiService {
  /// Set this to wherever app_api.py is actually running:
  ///   - same laptop, Android emulator:      http://10.0.2.2:5000
  ///   - real phone, same Wi-Fi as laptop:    http://<laptop-LAN-IP>:5000
  ///   - hosted remotely (e.g. behind ngrok): https://your-tunnel-url
  final String baseUrl;

  ApiService({required this.baseUrl});

  Future<HbResult> predict(SensorReading reading, {required int age, required String gender}) async {
    final uri = Uri.parse('$baseUrl/predict');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(reading.toJson(age: age, gender: gender)),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Prediction failed (${response.statusCode}): ${response.body}');
    }
    return HbResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
