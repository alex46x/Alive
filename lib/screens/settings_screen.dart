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

  @override
  void initState() {
    super.initState();
    _thresholds = DetectionThresholds(
      minSpeedKmh: widget.thresholds.minSpeedKmh,
      speedDropKmh: widget.thresholds.speedDropKmh,
      gForceThreshold: widget.thresholds.gForceThreshold,
      gyroThreshold: widget.thresholds.gyroThreshold,
    );
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
          // Enable toggle
          _sectionHeader('Detection Control'),
          const SizedBox(height: 12),
          _toggleCard(
            'Crash Detection Active',
            'Toggle the crash detection engine',
            widget.detectionEnabled,
            widget.onToggleDetection,
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

          _sectionHeader('Sensor Thresholds'),
          const SizedBox(height: 12),

          _sliderCard(
            label: 'G-Force Threshold',
            subtitle: 'Minimum impact force to detect',
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
    required ValueChanged<double> onChanged,
    required Color accentColor,
    int decimalPlaces = 0,
  }) {
    final displayValue = decimalPlaces == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(decimalPlaces);

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
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$displayValue $unit',
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accentColor,
              thumbColor: accentColor,
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
}
