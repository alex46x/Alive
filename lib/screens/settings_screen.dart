import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

class SettingsScreen extends StatefulWidget {
  final DetectionThresholds thresholds;
  final VoidCallback onSimulateCrash;
  final ValueChanged<DetectionThresholds> onThresholdsChanged;
  final bool detectionEnabled;
  final ValueChanged<bool> onToggleDetection;

  const SettingsScreen({
    super.key,
    required this.thresholds,
    required this.onSimulateCrash,
    required this.onThresholdsChanged,
    required this.detectionEnabled,
    required this.onToggleDetection,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DetectionThresholds _thresholds;
  late bool _detectionEnabled;

  @override
  void initState() {
    super.initState();
    // Copy every field so we have a working draft of the thresholds
    _thresholds = widget.thresholds.copyWith();
    _detectionEnabled = widget.detectionEnabled;
  }

  void _notifyChange() {
    widget.onThresholdsChanged(_thresholds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Detection Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionHeader('Emergency Action'),
          const SizedBox(height: 12),
          _textFieldCard(
            label: 'Emergency Contact Number',
            subtitle:
                'This number will be dialed and SMSed if you do not cancel an alert',
            hintText: 'e.g. +88019...',
            initialValue: _thresholds.emergencyNumber,
            onChanged: (v) {
              _thresholds.emergencyNumber = v;
              _notifyChange();
            },
          ),
          const SizedBox(height: 24),

          // Enable toggle
          _sectionHeader('Detection Control'),
          const SizedBox(height: 12),
          _toggleCard(
            'Crash Detection Active',
            'Toggle the crash detection engine',
            _detectionEnabled,
            (bool value) {
              setState(() => _detectionEnabled = value);
              widget.onToggleDetection(value);
            },
          ),
          const SizedBox(height: 24),

          _sectionHeader('Speed Thresholds'),
          const SizedBox(height: 12),

          _sliderCard(
            label: 'Minimum Speed to Arm',
            subtitle: 'Detection starts above this speed',
            value: _thresholds.minSpeedKmh,
            unit: 'km/h',
            min: 10,
            max: 80,
            divisions: 14,
            onChanged: (v) => setState(() {
              _thresholds.minSpeedKmh = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFF4FC3F7),
          ),

          const SizedBox(height: 16),

          _sliderCard(
            label: 'Speed Drop Required',
            subtitle: 'How fast speed must fall to trigger',
            value: _thresholds.speedDropKmh,
            unit: 'km/h',
            min: 10,
            max: 60,
            divisions: 10,
            onChanged: (v) => setState(() {
              _thresholds.speedDropKmh = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFFFFB74D),
          ),

          const SizedBox(height: 24),

          _sectionHeader('2-Stage Detection'),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            child: Text(
              'Stage 1: hard impact opens a verification window. '
              'Stage 2: GPS speed-drop confirms the crash inside that window.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),

          _sliderCard(
            label: 'Hard Impact G',
            subtitle: 'Strict G spike that opens the verification window',
            value: _thresholds.hardImpactG,
            unit: 'g',
            min: 2.0,
            max: 8.0,
            divisions: 24,
            decimalPlaces: 1,
            onChanged: (v) => setState(() {
              _thresholds.hardImpactG = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFFEF5350),
          ),

          const SizedBox(height: 16),

          _sliderCard(
            label: 'Hard Impact Gyro',
            subtitle: 'Strict angular-velocity spike that opens the window',
            value: _thresholds.hardImpactGyro,
            unit: 'rad/s',
            min: 3.0,
            max: 15.0,
            divisions: 24,
            decimalPlaces: 1,
            onChanged: (v) => setState(() {
              _thresholds.hardImpactGyro = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFFFF8A65),
          ),

          const SizedBox(height: 16),

          _sliderCard(
            label: 'Verification Window',
            subtitle:
                'How long after the impact to wait for GPS-confirmed speed drop',
            value: _thresholds.verificationWindowMs.toDouble(),
            unit: 'ms',
            min: 1000,
            max: 6000,
            divisions: 10,
            step: 500,
            onChanged: (v) => setState(() {
              _thresholds.verificationWindowMs = v.round();
              _notifyChange();
            }),
            accentColor: const Color(0xFF80DEEA),
          ),

          const SizedBox(height: 24),

          _sectionHeader('Sensor Thresholds'),
          const SizedBox(height: 12),

          _sliderCard(
            label: 'Linear G-Force Threshold',
            subtitle: 'Minimum impact force to detect (gravity removed)',
            value: _thresholds.gForceThreshold,
            unit: 'g',
            min: 1.5,
            max: 6.0,
            divisions: 18,
            decimalPlaces: 1,
            onChanged: (v) => setState(() {
              _thresholds.gForceThreshold = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFFF48FB1),
          ),

          const SizedBox(height: 16),

          _sliderCard(
            label: 'Gyroscope Threshold',
            subtitle: 'Minimum angular velocity to detect',
            value: _thresholds.gyroThreshold,
            unit: 'rad/s',
            min: 1.0,
            max: 10.0,
            divisions: 18,
            decimalPlaces: 1,
            onChanged: (v) => setState(() {
              _thresholds.gyroThreshold = v;
              _notifyChange();
            }),
            accentColor: const Color(0xFFA5D6A7),
          ),

          const SizedBox(height: 16),

          _sliderCard(
            label: 'Tilt Rate Threshold',
            subtitle:
                'Roll/flip rate (°/s) — only used if "Use tilt signal" is on',
            value: _thresholds.tiltThresholdDegPerSec,
            unit: '°/s',
            min: 30,
            max: 360,
            divisions: 33,
            onChanged: _thresholds.useTiltSignal
                ? (v) => setState(() {
                      _thresholds.tiltThresholdDegPerSec = v;
                      _notifyChange();
                    })
                : null,
            accentColor: const Color(0xFFFFD54F),
          ),

          const SizedBox(height: 24),

          _sectionHeader('Decision Logic'),
          const SizedBox(height: 12),

          _sliderCard(
            label: 'Confirmation Window',
            subtitle: 'How long all conditions must hold before triggering',
            value: _thresholds.confirmationMs.toDouble(),
            unit: 'ms',
            min: 0,
            max: 2000,
            divisions: 20,
            step: 100,
            onChanged: (v) => setState(() {
              _thresholds.confirmationMs = v.round();
              _notifyChange();
            }),
            accentColor: const Color(0xFFCE93D8),
          ),

          const SizedBox(height: 16),

          _toggleCard(
            'Adaptive Thresholds',
            'Lower the G threshold at higher speeds (highway = less sensitive)',
            _thresholds.adaptiveThresholds,
            (v) {
              setState(() {
                _thresholds.adaptiveThresholds = v;
                _notifyChange();
              });
            },
          ),

          const SizedBox(height: 12),

          _toggleCard(
            'Use Tilt Signal',
            'Require a high roll/flip rate as a third condition (off = 2-of-2, on = 2-of-3)',
            _thresholds.useTiltSignal,
            (v) {
              setState(() {
                _thresholds.useTiltSignal = v;
                _notifyChange();
              });
            },
          ),

          const SizedBox(height: 32),

          // Simulate crash button
          _sectionHeader('Testing Tools'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🧪 Simulate Crash',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Fires a fake crash event to test the alert system (sound + vibration + screen).',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onSimulateCrash();
                    },
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text(
                      'TRIGGER SIMULATION',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        letterSpacing: 2,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _toggleCard(
      String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF00E676),
          ),
        ],
      ),
    );
  }

  Widget _sliderCard({
    required String label,
    required String subtitle,
    required double value,
    required String unit,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
    required Color accentColor,
    int decimalPlaces = 0,
    double step = 1,
  }) {
    final displayValue = decimalPlaces == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(decimalPlaces);

    final disabled = onChanged == null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: disabled ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: disabled ? 0.08 : 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$displayValue $unit',
                  style: TextStyle(
                      color: disabled
                          ? accentColor.withValues(alpha: 0.4)
                          : accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor:
                  disabled ? accentColor.withValues(alpha: 0.3) : accentColor,
              thumbColor:
                  disabled ? accentColor.withValues(alpha: 0.3) : accentColor,
              inactiveTrackColor: accentColor.withValues(alpha: 0.2),
              overlayColor: accentColor.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textFieldCard({
    required String label,
    required String subtitle,
    required String hintText,
    required String initialValue,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: initialValue,
            keyboardType: TextInputType.phone,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 0),
              filled: true,
              fillColor: const Color(0xFF0F0F1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
              ),
              prefixIcon:
                  const Icon(Icons.emergency, color: Colors.redAccent, size: 20),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
