import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/reading.dart';

/// Must match esp32_ble_firmware.ino exactly.
class BleUuids {
  static final serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final txCharUuid = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e'); // ESP32 -> phone
  static final rxCharUuid = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // phone -> ESP32
}

const String kDeviceName = 'HbSense-ESP32'; // must match BLEDevice::init(...) in firmware

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  bool _isConnecting = false;

  String _lineBuffer = '';
  String? _pendingRLine; // holds "R:...|I:..." until we also have "M:f1,fz"

  /// Scans for the ESP32 by name and connects. Throws if not found within [timeout].
  Future<void> scanAndConnect({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isConnecting) {
      debugPrint('[BLE] scanAndConnect already in progress, ignoring extra tap');
      return;
    }
    _isConnecting = true;
    try {
      await _doScanAndConnect(timeout);
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _doScanAndConnect(Duration timeout) async {
    final completer = Completer<BluetoothDevice>();
    late final StreamSubscription sub;

    await FlutterBluePlus.stopScan(); // clear out any stuck previous scan first
    await FlutterBluePlus.startScan(timeout: timeout);
    sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName == kDeviceName && !completer.isCompleted) {
          completer.complete(r.device);
        }
      }
    });

    final device = await completer.future.timeout(
      timeout,
      onTimeout: () => throw Exception('HbSense-ESP32 not found -- is it powered on and advertising?'),
    );
    await FlutterBluePlus.stopScan();
    await sub.cancel();

    await device.connect(timeout: const Duration(seconds: 10));
    _device = device;
    debugPrint('[BLE] MTU = ${device.mtuNow}');

    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == BleUuids.serviceUuid,
      orElse: () => throw Exception('HbSense BLE service not found on device'),
    );
    _txChar = service.characteristics.firstWhere((c) => c.uuid == BleUuids.txCharUuid);
    _rxChar = service.characteristics.firstWhere((c) => c.uuid == BleUuids.rxCharUuid);

    await _txChar!.setNotifyValue(true);
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _txChar = null;
    _rxChar = null;
  }

  bool get isConnected => _device != null;

  /// Sends START, then listens for the two lines ("R:...|I:..." and "M:f1,fz")
  /// the firmware streams back in chunks, reassembles them, and returns a
  /// parsed SensorReading. Throws on timeout or malformed data.
  Future<SensorReading> takeMeasurement({Duration timeout = const Duration(seconds: 60)}) async {
    if (_txChar == null || _rxChar == null) {
      throw Exception('Not connected to HbSense-ESP32');
    }

    _lineBuffer = '';
    _pendingRLine = null;
    final completer = Completer<SensorReading>();

    final stopwatch = Stopwatch()..start();
    final sub = _txChar!.onValueReceived.listen((bytes) {
      if (bytes.isEmpty) return;
      debugPrint('[BLE] chunk received: ${bytes.length} bytes @ ${stopwatch.elapsedMilliseconds}ms');
      _lineBuffer += utf8.decode(bytes, allowMalformed: true);

      // process every complete line ('\n'-terminated) currently in the buffer
      while (_lineBuffer.contains('\n')) {
        final idx = _lineBuffer.indexOf('\n');
        final line = _lineBuffer.substring(0, idx).trim();
        _lineBuffer = _lineBuffer.substring(idx + 1);
        if (line.isEmpty) continue;

        if (line.startsWith('R:') && line.contains('|I:')) {
          debugPrint('[BLE] got R/I line @ ${stopwatch.elapsedMilliseconds}ms (len ${line.length})');
          _pendingRLine = line;
        } else if (line.startsWith('E:')) {
          debugPrint('[BLE] device error: $line');
          if (!completer.isCompleted) completer.completeError(Exception('Device: ${line.substring(2)}'));
        } else if (line.startsWith('M:') && _pendingRLine != null) {
          debugPrint('[BLE] got M line @ ${stopwatch.elapsedMilliseconds}ms -- reading complete');
          try {
            final reading = _parseReading(_pendingRLine!, line);
            if (!completer.isCompleted) completer.complete(reading);
          } catch (e) {
            debugPrint('[BLE] parse error: $e');
            if (!completer.isCompleted) completer.completeError(e);
          }
        }
      }
    });

    debugPrint('[BLE] sending START');
    await _rxChar!.write(utf8.encode('START'), withoutResponse: false);

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw Exception('Timed out waiting for sensor data over BLE'),
      );
    } finally {
      await sub.cancel();
    }
  }

  SensorReading _parseReading(String rLine, String mLine) {
    // rLine: "R:1,2,3,...|I:4,5,6,..."
    final withoutPrefix = rLine.substring(2); // drop "R:"
    final parts = withoutPrefix.split('|I:');
    final red = parts[0].split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
    final ir = parts[1].split(',').where((s) => s.isNotEmpty).map(int.parse).toList();

    // mLine: "M:f1,fz"
    final mParts = mLine.substring(2).split(',');
    final f1 = double.parse(mParts[0]);
    final fz = double.parse(mParts[1]);

    return SensorReading(red: red, ir: ir, f1: f1, fz: fz);
  }

  /// Relays the final Hb value back to the ESP32 so it can show it on the OLED.
  /// (Flask can't do this directly -- only the phone has the BLE link.)
  Future<void> sendResultToDevice(double hbValue, {double? hbRaw, double? melaninIndex}) async {
    if (_rxChar == null) throw Exception('Not connected to HbSense-ESP32');
    final msg = 'RES:${hbValue.toStringAsFixed(2)},'
        '${(hbRaw ?? hbValue).toStringAsFixed(2)},'
        '${(melaninIndex ?? 0).toStringAsFixed(3)}';
    await _rxChar!.write(utf8.encode(msg), withoutResponse: false);
  }

  Future<void> sendErrorToDevice(String text) async {
    if (_rxChar == null) return;
    final t = text.length > 20 ? text.substring(0, 20) : text;
    try { await _rxChar!.write(utf8.encode('ERR:$t'), withoutResponse: false); } catch (_) {}
  }
}