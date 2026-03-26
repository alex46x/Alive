import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/alert_service.dart';
import '../services/crash_detector_service.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import 'crash_alert_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Services
  late final LocationService _locationService;
  late final SensorService _sensorService;
  late final CrashDetectorService _crashDetector;
  late final AlertService _alertService;

  // Live values
  double _speedKmh = 0.0;
  double _gForce = 1.0;
  double _angularVelocity = 0.0;
  DetectionState _detectionState = DetectionState.idle;
  bool _detectionEnabled = true;
  DetectionThresholds _thresholds = DetectionThresholds();

  final List<CrashEvent> _history = [];

  // Subscriptions
  StreamSubscription? _speedSub;
  StreamSubscription? _gForceSub;
  StreamSubscription? _gyroSub;
  Timer? _uiRefreshTimer;

  // Animations
  late AnimationController _statusPulse;

  bool _alertShowing = false;

  @override
  void initState() {
    super.initState();

    _statusPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initServices();
  }

  void _initServices() {
    _locationService = LocationService();
    _sensorService = SensorService();
    _alertService = AlertService();

    _crashDetector = CrashDetectorService(
      locationService: _locationService,
      sensorService: _sensorService,
      thresholds: _thresholds,
    );

    _crashDetector.onCrashDetected = (CrashEvent event) {
      if (!mounted || _alertShowing) return;
      setState(() => _history.insert(0, event));
      _showCrashAlert(event);
    };

    // Subscribe to streams
    _speedSub = _locationService.speedStream.listen((speed) {
      if (mounted) setState(() => _speedKmh = speed);
    });

    _gForceSub = _sensorService.gForceStream.listen((g) {
      if (mounted) setState(() => _gForce = g);
    });

    _gyroSub = _sensorService.gyroStream.listen((av) {
      if (mounted) setState(() => _angularVelocity = av);
    });

    // Start all services
    _locationService.start();
    _sensorService.start();
    _crashDetector.startMonitoring();

    // Refresh detection state indicator every 500ms
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() => _detectionState = _crashDetector.state);
      }
    });
  }

  void _showCrashAlert(CrashEvent event) {
    if (_alertShowing) return;
    _alertShowing = true;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => CrashAlertScreen(
          event: event,
          alertService: _alertService,
          onDismissed: () {
            _crashDetector.resetAfterAlert();
            _alertShowing = false;
            Navigator.of(context).pop();
          },
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          thresholds: _thresholds,
          detectionEnabled: _detectionEnabled,
          onSimulateCrash: () {
            _crashDetector.triggerSimulation();
          },
          onThresholdsChanged: (t) {
            setState(() => _thresholds = t);
            _crashDetector.thresholds = t;
          },
          onToggleDetection: (enabled) {
            setState(() => _detectionEnabled = enabled);
            if (enabled) {
              _crashDetector.enable();
            } else {
              _crashDetector.disable();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    _gForceSub?.cancel();
    _gyroSub?.cancel();
    _uiRefreshTimer?.cancel();
    _statusPulse.dispose();
    _locationService.dispose();
    _sensorService.dispose();
    _crashDetector.dispose();
    _alertService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF3D00).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.car_crash,
                color: Color(0xFFFF3D00),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crash Detector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'TEST VERSION',
                  style: TextStyle(
                    color: Color(0xFFFF3D00),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.tune, color: Colors.white70),
            tooltip: 'Settings & Thresholds',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // Detection status card
          _buildStatusCard(),
          const SizedBox(height: 16),

          // Metric grid
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: _speedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  color: _speedKmh >= _thresholds.minSpeedKmh
                      ? const Color(0xFF4FC3F7)
                      : Colors.white54,
                  subtext: _speedKmh >= _thresholds.minSpeedKmh
                      ? '🟢 Armed'
                      : '⚪ Below threshold',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.vibration,
                  label: 'G-Force',
                  value: _gForce.toStringAsFixed(2),
                  unit: 'g',
                  color: _gForce >= _thresholds.gForceThreshold
                      ? Colors.orange
                      : Colors.white54,
                  subtext: _gForce >= _thresholds.gForceThreshold
                      ? '⚡ Spike!'
                      : 'Normal',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.rotate_90_degrees_cw,
                  label: 'Gyroscope',
                  value: _angularVelocity.toStringAsFixed(2),
                  unit: 'rad/s',
                  color: _angularVelocity >= _thresholds.gyroThreshold
                      ? Colors.pinkAccent
                      : Colors.white54,
                  subtext: _angularVelocity >= _thresholds.gyroThreshold
                      ? '🌀 Spike!'
                      : 'Stable',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildConditionsCard()),
            ],
          ),

          const SizedBox(height: 20),

          // History section
          const Row(
            children: [
              Icon(Icons.history, color: Colors.white38, size: 16),
              SizedBox(width: 6),
              Text(
                'DETECTION HISTORY',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._buildHistory(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final stateColor = _detectionEnabled
        ? (_detectionState == DetectionState.armed
            ? const Color(0xFFFFB74D)
            : _detectionState == DetectionState.crashed
                ? const Color(0xFFFF3D00)
                : const Color(0xFF00E676))
        : Colors.grey;

    final stateLabel = !_detectionEnabled
        ? 'DISABLED'
        : _detectionState == DetectionState.armed
            ? 'ARMED'
            : _detectionState == DetectionState.crashed
                ? 'CRASH DETECTED'
                : 'MONITORING';

    final stateIcon = !_detectionEnabled
        ? Icons.pause_circle
        : _detectionState == DetectionState.armed
            ? Icons.shield
            : _detectionState == DetectionState.crashed
                ? Icons.warning
                : Icons.radar;

    return AnimatedBuilder(
      animation: _statusPulse,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                stateColor.withValues(alpha: 0.15 + _statusPulse.value * 0.05),
                const Color(0xFF1A1A2E),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: stateColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stateColor.withValues(alpha: 0.2),
                  border: Border.all(color: stateColor, width: 2),
                ),
                child: Icon(stateIcon, color: stateColor, size: 28),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stateLabel,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detectionEnabled
                        ? 'Crash detection is running'
                        : 'Tap Settings to enable',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: color,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(subtext,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildConditionsCard() {
    final speedOk = _speedKmh >= _thresholds.minSpeedKmh;
    final gForceOk = _gForce >= _thresholds.gForceThreshold;
    final gyroOk = _angularVelocity >= _thresholds.gyroThreshold;
    final allMet = speedOk && gForceOk && gyroOk;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: allMet
              ? Colors.red.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conditions',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 10),
          _conditionRow('Speed', speedOk),
          _conditionRow('G-Force', gForceOk),
          _conditionRow('Gyro', gyroOk),
          const SizedBox(height: 6),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                allMet ? Icons.warning : Icons.check_circle_outline,
                color: allMet ? Colors.red : Colors.green,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                allMet ? 'CRASH!' : 'Safe',
                style: TextStyle(
                  color: allMet ? Colors.red : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conditionRow(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            met ? Icons.circle : Icons.radio_button_unchecked,
            color: met ? Colors.orange : Colors.white24,
            size: 10,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: met ? Colors.white : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildHistory() {
    if (_history.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Column(
              children: [
                Icon(Icons.history, color: Colors.white24, size: 40),
                SizedBox(height: 8),
                Text(
                  'No crash events detected yet',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return _history.take(10).map((event) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber,
                  color: Colors.redAccent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crash Event @ ${event.formattedTime}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.speedBefore.toStringAsFixed(0)} → ${event.speedAfter.toStringAsFixed(0)} km/h  •  ${event.peakGForce.toStringAsFixed(1)}g  •  ${event.peakAngularVelocity.toStringAsFixed(1)} rad/s',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
