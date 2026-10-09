import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/api_service.dart';
import '../models/reading.dart';
import '../theme.dart';
import '../widgets/pulse_wave.dart';

enum FlowState { idle, connecting, connected, measuring, predicting, done, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ble = BleService();
  final _api = ApiService(baseUrl: 'your url');

  final _ageController = TextEditingController(text: '30');
  String _gender = 'M';

  FlowState _state = FlowState.idle;
  String? _errorMessage;
  HbResult? _result;

  bool get _connected => _ble.isConnected;
  bool get _busy => _state == FlowState.connecting ||
      _state == FlowState.measuring ||
      _state == FlowState.predicting;

  Future<void> _connect() async {
    setState(() { _state = FlowState.connecting; _errorMessage = null; });
    try {
      await _ble.scanAndConnect();
      setState(() => _state = FlowState.connected);
    } catch (e) {
      setState(() { _state = FlowState.error; _errorMessage = e.toString(); });
    }
  }

  Future<void> _runMeasurement() async {
    setState(() { _state = FlowState.measuring; _errorMessage = null; _result = null; });
    try {
      final reading = await _ble.takeMeasurement();
      setState(() => _state = FlowState.predicting);
      final age = int.tryParse(_ageController.text) ?? 30;
      final result = await _api.predict(reading, age: age, gender: _gender);
      final displayValue = result.hbCorrected ?? result.hbRaw;
      await _ble.sendResultToDevice(displayValue, hbRaw: result.hbRaw, melaninIndex: result.melaninIndex);
      setState(() { _result = result; _state = FlowState.done; });
    } catch (e) {
      _ble.sendErrorToDevice('Failed');
      setState(() { _state = FlowState.error; _errorMessage = e.toString(); });
    }
  }

  @override
  void dispose() {
    _ble.disconnect();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(textTheme),
              const SizedBox(height: 28),
              _buildConnectionRow(),
              const SizedBox(height: 16),
              _buildDemographicsForm(textTheme),
              const SizedBox(height: 16),
              _buildMeasureButton(),
              const SizedBox(height: 28),
              _buildStatusArea(textTheme),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Header ----------------

  Widget _buildHeader(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HbSense', style: textTheme.displayLarge),
        const SizedBox(height: 4),
        Text(
          'Non-invasive hemoglobin reading',
          style: textTheme.bodyMedium?.copyWith(color: HbColors.neutral),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: PulseWavePainter(
              color: _connected ? HbColors.teal : HbColors.line,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------- Connection ----------------

  Widget _buildConnectionRow() {
    final label = _connected
        ? 'Connected to HbSense-ESP32'
        : _state == FlowState.connecting
            ? 'Searching for HbSense-ESP32...'
            : 'Device not connected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: HbColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HbColors.line),
      ),
      child: Row(
        children: [
          Icon(
            _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: _connected ? HbColors.teal : HbColors.neutral,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (!_connected)
            TextButton(
              onPressed: _state == FlowState.connecting ? null : _connect,
              style: TextButton.styleFrom(foregroundColor: HbColors.garnet),
              child: _state == FlowState.connecting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: HbColors.garnet),
                    )
                  : const Text('Connect'),
            ),
        ],
      ),
    );
  }

  // ---------------- Demographics ----------------

  Widget _buildDemographicsForm(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Age'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: const [
              DropdownMenuItem(value: 'M', child: Text('Male')),
              DropdownMenuItem(value: 'F', child: Text('Female')),
            ],
            onChanged: (v) => setState(() => _gender = v ?? 'M'),
          ),
        ),
      ],
    );
  }

  // ---------------- Primary action ----------------

  Widget _buildMeasureButton() {
    return ElevatedButton(
      onPressed: (!_connected || _busy) ? null : _runMeasurement,
      child: Text(
        _state == FlowState.measuring
            ? 'Reading sensor...'
            : _state == FlowState.predicting
                ? 'Getting result...'
                : 'Start measurement',
      ),
    );
  }

  // ---------------- Status / result area ----------------
  // Deliberately never left blank: idle state explains what happens next,
  // rather than showing an empty screen with nothing to look at.

  Widget _buildStatusArea(TextTheme textTheme) {
    switch (_state) {
      case FlowState.measuring:
      case FlowState.predicting:
        return _progressCard(
          _state == FlowState.measuring
              ? 'Reading sensor over Bluetooth (about 5 seconds). Keep the finger still on the sensor.'
              : 'Sending the reading to the model for a prediction.',
        );
      case FlowState.done:
        return _resultCard(_result!, textTheme);
      case FlowState.error:
        return _errorCard();
      case FlowState.idle:
      case FlowState.connecting:
      case FlowState.connected:
        return _idleCard(textTheme);
    }
  }

  Widget _idleCard(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: HbColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How this works', style: textTheme.titleMedium),
          const SizedBox(height: 10),
          _stepLine('1', 'Connect to the sensor over Bluetooth.'),
          _stepLine('2', 'Place a finger on the sensor and start the measurement.'),
          _stepLine('3', 'The reading is sent for a prediction, then shown here and on the device display.'),
        ],
      ),
    );
  }

  Widget _stepLine(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: HbColors.line, shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(fontSize: 11, color: HbColors.ink)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: HbColors.ink))),
        ],
      ),
    );
  }

  Widget _progressCard(String label) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: HbColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HbColors.line),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: HbColors.garnet),
          ),
          const SizedBox(height: 14),
          Text(label, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: HbColors.ink)),
        ],
      ),
    );
  }

  Widget _resultCard(HbResult r, TextTheme textTheme) {
    final displayValue = r.hbCorrected ?? r.hbRaw;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: HbColors.garnet,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text('ESTIMATED HEMOGLOBIN',
              style: textTheme.bodySmall?.copyWith(
                  color: Colors.white70, letterSpacing: 0.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(displayValue.toStringAsFixed(1),
                  style: textTheme.displayLarge?.copyWith(color: Colors.white, fontSize: 56)),
              const SizedBox(width: 6),
              Text('g/dL', style: textTheme.headlineMedium?.copyWith(color: Colors.white70, fontSize: 18)),
            ],
          ),
          if (!r.melaninCorrectionValidated) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Melanin correction applied but not yet clinically validated. '
                'Model output before correction: ${r.hbRaw.toStringAsFixed(2)} g/dL. '
                'Melanin Index: ${r.melaninIndex?.toStringAsFixed(3) ?? 'N/A'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: Colors.white, height: 1.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEAEA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7C6C6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: HbColors.garnetDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_errorMessage ?? 'Something went wrong.',
                style: const TextStyle(color: HbColors.garnetDark, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}