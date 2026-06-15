import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../services/alert_service.dart';
import '../services/crash_detector_service.dart';
import '../services/foreground_task_service.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../services/settings_service.dart';
import 'crash_alert_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final DetectionThresholds initialThresholds;
  final SettingsService settings;
  final ForegroundTaskService? fg;
  const HomeScreen({
    super.key,
    required this.initialThresholds,
    required this.settings,
    required this.fg,
  });

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
  double _linearG = 0.0;
  double _angularVelocity = 0.0;
  double _tiltRate = 0.0;
  DetectionState _detectionState = DetectionState.idle;
  bool _detectionEnabled = true;
  late DetectionThresholds _thresholds;

  final List<CrashEvent> _history = [];

  // Subscriptions
  StreamSubscription? _speedSub;
  StreamSubscription? _linearGSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _tiltSub;
  StreamSubscription? _fgDataSub;
  Timer? _uiRefreshTimer;

  // Animations
  late AnimationController _statusPulse;

  bool _alertShowing = false;
  bool _fgStarted = false;

  @override
  void initState() {
    super.initState();

    _thresholds = widget.initialThresholds;

    _statusPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _initServices();
    _wireForegroundCallbacks();
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

    _linearGSub = _sensorService.linearGStream.listen((g) {
      if (mounted) setState(() => _linearG = g);
    });

    _gyroSub = _sensorService.gyroStream.listen((av) {
      if (mounted) setState(() => _angularVelocity = av);
    });

    _tiltSub = _sensorService.tiltStream.listen((t) {
      if (mounted) setState(() => _tiltRate = t);
    });

    // Start all in-app services. On web these plugins have no real backend,
    // so the stream subscriptions stay open but never emit - the UI still
    // renders and the simulate-crash button still works.
    if (!kIsWeb) {
      _locationService.start();
      _sensorService.start();
      _crashDetector.startMonitoring();
    }

    // Start the background task (so detection survives backgrounding)
    if (_detectionEnabled) {
      _startForeground();
    }

    // Refresh detection state indicator every 500ms
    _uiRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() => _detectionState = _crashDetector.state);
      }
    });
  }

  void _wireForegroundCallbacks() {
    // On web (or wherever the foreground plugin is unavailable) fg is null
    // and the background stream simply doesn't exist. Skip the wire-up.
    final fg = widget.fg;
    if (fg == null) return;

    // Receive crash events detected by the background isolate and surface
    // them on-screen in addition to the in-app detector.
    _fgDataSub = fg.dataStream.listen((data) {
      if (!mounted) return;
      if (data['event'] == 'crash') {
        if (_alertShowing) return;
        // Convert the map back to a CrashEvent-like display
        final ev = CrashEvent(
          timestamp: DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
              DateTime.now(),
          speedBefore: (data['speedBefore'] as num?)?.toDouble() ?? 0.0,
          speedAfter: (data['speedAfter'] as num?)?.toDouble() ?? 0.0,
          peakGForce: (data['peakGForce'] as num?)?.toDouble() ?? 0.0,
          peakAngularVelocity:
              (data['peakAngularVelocity'] as num?)?.toDouble() ?? 0.0,
          peakTiltRate: (data['peakTiltRate'] as num?)?.toDouble() ?? 0.0,
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
        );
        setState(() => _history.insert(0, ev));
        _showCrashAlert(ev);
      } else if (data['event'] == 'state') {
        // Background reported a state transition - keep indicator in sync
        final s = data['state']?.toString();
        if (s != null && mounted) {
          setState(() {
            _detectionState = s == 'crashed'
                ? DetectionState.crashed
                : s == 'armed'
                    ? DetectionState.armed
                    : DetectionState.idle;
          });
        }
      }
    });
  }

  Future<void> _startForeground() async {
    if (_fgStarted) return;
    final fg = widget.fg;
    if (fg == null) return;
    await fg.start(_thresholds);
    _fgStarted = await fg.isRunning();
  }

  Future<void> _stopForeground() async {
    if (!_fgStarted) return;
    final fg = widget.fg;
    if (fg == null) {
      _fgStarted = false;
      return;
    }
    await fg.stop();
    _fgStarted = false;
  }

  void _showCrashAlert(CrashEvent event) {
    if (_alertShowing) return;
    _alertShowing = true;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, anim, secondaryAnim) => CrashAlertScreen(
          event: event,
          alertService: _alertService,
          emergencyNumber: _thresholds.emergencyNumber,
          onDismissed: () {
            _crashDetector.resetAfterAlert();
            _alertShowing = false;
            Navigator.of(context).pop();
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnim, child) {
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
          onThresholdsChanged: (t) async {
            setState(() => _thresholds = t);
            _crashDetector.thresholds = t;
            await widget.settings.save(t);
            final fg = widget.fg;
            if (fg != null) await fg.updateThresholds(t);
          },
          onToggleDetection: (enabled) async {
            setState(() => _detectionEnabled = enabled);
            if (enabled) {
              _crashDetector.enable();
              await _startForeground();
            } else {
              _crashDetector.disable();
              await _stopForeground();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    _linearGSub?.cancel();
    _gyroSub?.cancel();
    _tiltSub?.cancel();
    _fgDataSub?.cancel();
    _uiRefreshTimer?.cancel();
    _statusPulse.dispose();
    _locationService.dispose();
    _sensorService.dispose();
    _crashDetector.dispose();
    _alertService.dispose();
    // Best-effort stop the foreground service on app exit
    _stopForeground();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speedMet = _speedKmh >= _thresholds.minSpeedKmh;
    final gMet = _linearG >= _thresholds.gForceThreshold;
    final gyroMet = _angularVelocity >= _thresholds.gyroThreshold;
    final tiltMet = !_thresholds.useTiltSignal ||
        _tiltRate >= _thresholds.tiltThresholdDegPerSec;
    final fgRunning = _fgStarted;

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
          // Small pill showing FG service status
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: fgRunning
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: fgRunning
                      ? Colors.green.withValues(alpha: 0.5)
                      : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    fgRunning ? Icons.cloud_done : Icons.cloud_off,
                    color: fgRunning ? Colors.greenAccent : Colors.white38,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    fgRunning ? 'BG' : 'FG',
                    style: TextStyle(
                      color: fgRunning ? Colors.greenAccent : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          if (kIsWeb) const _WebPreviewBanner(),
          // Detection status card
          _buildStatusCard(),
          const SizedBox(height: 16),

          // Metric grid: Speed + Linear G
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: _speedKmh.toStringAsFixed(1),
                  unit: 'km/h',
                  color: speedMet
                      ? const Color(0xFF4FC3F7)
                      : Colors.white54,
                  subtext: speedMet ? '🟢 Armed' : '⚪ Below threshold',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.vibration,
                  label: 'Linear G',
                  value: _linearG.toStringAsFixed(2),
                  unit: 'g',
                  color: gMet ? Colors.orange : Colors.white54,
                  subtext: gMet ? '⚡ Spike!' : 'Normal',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Metric grid: Gyro + Tilt Rate
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.rotate_90_degrees_cw,
                  label: 'Gyroscope',
                  value: _angularVelocity.toStringAsFixed(2),
                  unit: 'rad/s',
                  color: gyroMet ? Colors.pinkAccent : Colors.white54,
                  subtext: gyroMet ? '🌪️ Spike!' : 'Stable',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.screen_rotation,
                  label: 'Tilt Rate',
                  value: _tiltRate.toStringAsFixed(0),
                  unit: '°/s',
                  color: _tiltRate >= _thresholds.tiltThresholdDegPerSec
                      ? Colors.amberAccent
                      : Colors.white54,
                  subtext: _thresholds.useTiltSignal
                      ? (_tiltRate >= _thresholds.tiltThresholdDegPerSec
                          ? '🚨 Roll!'
                          : 'Stable')
                      : 'Disabled',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildConditionsCard(speedMet, gMet, gyroMet, tiltMet),

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
                        ? (_fgStarted
                            ? 'Crash detection is running (BG)'
                            : 'Crash detection is running')
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

  Widget _buildConditionsCard(
      bool speedMet, bool gMet, bool gyroMet, bool tiltMet) {
    // 2-of-N majority (speed-gated): if speed is met, require 2 of (g, gyro, tilt).
    // If speed is not met, the detector won't fire regardless.
    int metCount = 0;
    if (gMet) metCount++;
    if (gyroMet) metCount++;
    if (tiltMet) metCount++;
    final triggerMet = speedMet && metCount >= 2;
    final armed = speedMet;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: triggerMet
              ? Colors.red.withValues(alpha: 0.6)
              : armed
                  ? Colors.amber.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Conditions',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              Text(
                'confirm ≥ ${_thresholds.confirmationMs} ms',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _conditionRow('Speed', speedMet),
          _conditionRow('Linear G', gMet),
          _conditionRow('Gyro', gyroMet),
          if (_thresholds.useTiltSignal) _conditionRow('Tilt', tiltMet),
          const SizedBox(height: 6),
          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                triggerMet ? Icons.warning : Icons.check_circle_outline,
                color: triggerMet ? Colors.red : Colors.green,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                triggerMet
                    ? 'CRASH!'
                    : armed
                        ? 'Armed ($metCount/2)'
                        : 'Safe',
                style: TextStyle(
                  color: triggerMet ? Colors.red : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_thresholds.adaptiveThresholds)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'ADAPTIVE',
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
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

/// Banner shown when the app is running on Chrome/web. Sensors, location, and
/// the foreground service are mobile-only, so the UI is for layout preview
/// only. The simulate-crash button still works for testing the alert flow.
class _WebPreviewBanner extends StatelessWidget {
  const _WebPreviewBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Web preview � no live sensors. Run on Android for full detection.',
              style: TextStyle(color: Colors.amber, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
