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

  double _previousSpeedKmh = 0.0;
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

    // === STATE MACHINE ===

    // IDLE → ARMED: User must be going fast enough
    if (_state == DetectionState.idle) {
      if (currentSpeed >= thresholds.minSpeedKmh) {
        _state = DetectionState.armed;
        _armedAt = DateTime.now();
        _previousSpeedKmh = currentSpeed;
      }
      return;
    }

    // ARMED: Monitor for crash conditions
    if (_state == DetectionState.armed) {
      // Disarm if speed drops to 0 slowly (normal stop) - check elapsed time
      // We only keep armed for 10 seconds after arming
      if (_armedAt != null) {
        final elapsed = DateTime.now().difference(_armedAt!).inSeconds;
        if (elapsed > 10 && currentSpeed < thresholds.minSpeedKmh) {
          _state = DetectionState.idle;
          _previousSpeedKmh = 0;
          return;
        }
      }

      final speedDrop = _previousSpeedKmh - currentSpeed;
      final gForceExceeded = gForce >= thresholds.gForceThreshold;
      final gyroExceeded = angularVelocity >= thresholds.gyroThreshold;
      final speedDropExceeded = speedDrop >= thresholds.speedDropKmh;

      // All three conditions must be met simultaneously
      if (speedDropExceeded && gForceExceeded && gyroExceeded) {
        _fireCrash(
          speedBefore: _previousSpeedKmh,
          speedAfter: currentSpeed,
          gForce: gForce,
          angularVelocity: angularVelocity,
        );
        return;
      }

      // Keep rolling speed window
      _previousSpeedKmh = currentSpeed;
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
    _previousSpeedKmh = 0;
    _armedAt = null;
  }

  void dispose() {
    stopMonitoring();
  }
}
