import 'dart:async';
import '../models/sensor_data.dart';
import 'location_service.dart';
import 'sensor_service.dart';

enum DetectionState { idle, armed, crashed }

class CrashDetectorService {
  final LocationService locationService;
  final SensorService sensorService;

  DetectionThresholds thresholds;

  // State
  DetectionState _state = DetectionState.idle;
  DetectionState get state => _state;

  final List<_SpeedRecord> _speedHistory = [];
  DateTime? _armedAt;

  // Crash event callback
  Function(CrashEvent event)? onCrashDetected;

  // Cooldown: prevent double-firing
  DateTime? _lastCrashTime;
  static const _cooldownSeconds = 15;

  // Manual simulation flag
  bool _simulateCrash = false;

  Timer? _checkTimer;
  bool _enabled = true;

  bool get isEnabled => _enabled;

  CrashDetectorService({
    required this.locationService,
    required this.sensorService,
    DetectionThresholds? thresholds,
  }) : thresholds = thresholds ?? DetectionThresholds();

  void enable() {
    _enabled = true;
  }

  void disable() {
    _enabled = false;
    _state = DetectionState.idle;
  }

  void triggerSimulation() {
    _simulateCrash = true;
  }

  void startMonitoring() {
    // Poll at 500ms intervals for fusion logic
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _evaluate();
    });
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _state = DetectionState.idle;
  }

  void _evaluate() {
    if (!_enabled) return;

    // Handle simulation trigger
    if (_simulateCrash) {
      _simulateCrash = false;
      _fireCrash(
        speedBefore: 60.0,
        speedAfter: 0.0,
        gForce: 4.0,
        angularVelocity: 5.0,
      );
      return;
    }

    // Cooldown check
    if (_lastCrashTime != null) {
      final elapsed = DateTime.now().difference(_lastCrashTime!).inSeconds;
      if (elapsed < _cooldownSeconds) return;
    }

    final currentSpeed = locationService.currentSpeedKmh;
    final gForce = sensorService.peakGForce;
    final angularVelocity = sensorService.peakAngularVelocity;

    // Maintain speed history window (keep past 4 seconds of data)
    final now = DateTime.now();
    _speedHistory.add(_SpeedRecord(time: now, speed: currentSpeed));
    _speedHistory.removeWhere((r) => now.difference(r.time).inSeconds > 4);

    // === STATE MACHINE ===

    if (_state == DetectionState.idle) {
      if (currentSpeed >= thresholds.minSpeedKmh) {
        _state = DetectionState.armed;
        _armedAt = now;
      }
      return;
    }

    if (_state == DetectionState.armed) {
      if (_armedAt != null) {
        final elapsed = now.difference(_armedAt!).inSeconds;
        if (elapsed > 10 && currentSpeed < thresholds.minSpeedKmh) {
          _state = DetectionState.idle;
          _speedHistory.clear();
          return;
        }
      }

      // Calculate speed drop from the peak speed within the last 3 seconds
      double peakRecentSpeed = currentSpeed;
      if (_speedHistory.isNotEmpty) {
        peakRecentSpeed = _speedHistory.map((r) => r.speed).reduce((a, b) => a > b ? a : b);
      }

      final speedDrop = peakRecentSpeed - currentSpeed;
      final gForceExceeded = gForce >= thresholds.gForceThreshold;
      final gyroExceeded = angularVelocity >= thresholds.gyroThreshold;
      final speedDropExceeded = speedDrop >= thresholds.speedDropKmh;

      if (speedDropExceeded && gForceExceeded && gyroExceeded) {
        _fireCrash(
          speedBefore: peakRecentSpeed,
          speedAfter: currentSpeed,
          gForce: gForce,
          angularVelocity: angularVelocity,
        );
        return;
      }
    }
  }

  void _fireCrash({
    required double speedBefore,
    required double speedAfter,
    required double gForce,
    required double angularVelocity,
  }) {
    _state = DetectionState.crashed;
    _lastCrashTime = DateTime.now();

    final event = CrashEvent(
      timestamp: DateTime.now(),
      speedBefore: speedBefore,
      speedAfter: speedAfter,
      peakGForce: gForce,
      peakAngularVelocity: angularVelocity,
    );

    onCrashDetected?.call(event);
  }

  void resetAfterAlert() {
    _state = DetectionState.idle;
    _speedHistory.clear();
    _armedAt = null;
  }

  void dispose() {
    stopMonitoring();
  }
}

class _SpeedRecord {
  final DateTime time;
  final double speed;
  _SpeedRecord({required this.time, required this.speed});
}
