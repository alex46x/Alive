import 'dart:async';
import '../models/sensor_data.dart';
import 'location_service.dart';
import 'sensor_service.dart';

enum DetectionState { idle, armed, verifying, crashed }

/// State machine + decision logic for crash detection.
///
/// **Why the 2-stage ("impact-then-verify") decision matters**
///
/// In the previous version, every 500 ms we asked:
///   "is `speedMet && gMet && gyroMet` all true *right now*?"
/// The G and gyro signals spike the millisecond of impact. The speed-drop
/// signal can't — GPS is 1 Hz, has its own smoothing, and gets LPF'd in
/// `LocationService`. By the time the speed-drop actually shows up on the
/// next GPS sample, the G/gyro spike is long gone. So the "all at once" rule
/// fires late (or not at all) and the user can get out of the car before the
/// alert does anything.
///
/// New decision:
///   **Stage 1 — Impact (instant).** If a single sample crosses the
///   "hard impact" G or gyro threshold, we open a 3-second **verification
///   window** and capture the GPS speed at that moment as `speedAtImpact`.
///   This costs us ~0 ms of latency; it fires the same 500 ms tick the
///   spike is observed.
///
///   **Stage 2 — Verify (over the next N seconds).** During the window we
///   watch the *current* GPS speed. As soon as
///   `speedAtImpact - currentSpeed >= speedDropKmh`, we fire the crash. If
///   the window expires without confirmation, the candidate is discarded.
///
/// We also keep the legacy "all signals met" path as a fast path, for the
/// (rare) case where GPS happens to land a slow sample at the exact tick of
/// the spike. That path uses the existing `confirmationMs` hold timer so it
/// doesn't false-fire on a single sample.
class CrashDetectorService {
  final LocationService locationService;
  final SensorService sensorService;

  DetectionThresholds thresholds;

  // === State ===
  DetectionState _state = DetectionState.idle;
  DetectionState get state => _state;

  final List<_SpeedRecord> _speedHistory = [];
  DateTime? _armedAt;
  DateTime? _conditionsMetSince; // for the "all met" confirmation timer

  // 2-stage verification state
  DateTime? _impactAt;        // when the hard-impact spike was observed
  double? _speedAtImpact;     // GPS speed at the moment of impact
  double _peakGAtImpact = 0;  // peak G captured during the impact tick
  double _peakGyroAtImpact = 0;
  double _peakTiltAtImpact = 0;

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

  // Window for speed drop and sensor peaks (kept in sync with stage 2)
  static const Duration _decisionWindow = Duration(seconds: 4);

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
    _resetAll();
  }

  void triggerSimulation() {
    _simulateCrash = true;
  }

  void startMonitoring() {
    // 500 ms polling matches the GPS update cadence (1 Hz) and is light
    // enough to run inside a foreground service.
    _checkTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _evaluate();
    });
  }

  void stopMonitoring() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _resetAll();
  }

  void _resetAll() {
    _state = DetectionState.idle;
    _armedAt = null;
    _conditionsMetSince = null;
    _impactAt = null;
    _speedAtImpact = null;
    _speedHistory.clear();
  }

  void _evaluate() {
    if (!_enabled) return;

    // Handle simulation trigger (works even when not yet armed)
    if (_simulateCrash) {
      _simulateCrash = false;
      _fireCrash(
        speedBefore: 60.0,
        speedAfter: 0.0,
        gForce: 4.0,
        angularVelocity: 5.0,
        tiltRate: 120.0,
        latitude: locationService.currentPosition?.latitude ?? 23.8103,
        longitude: locationService.currentPosition?.longitude ?? 90.4125,
      );
      return;
    }

    // Cooldown check
    if (_lastCrashTime != null) {
      final elapsed = DateTime.now().difference(_lastCrashTime!).inSeconds;
      if (elapsed < _cooldownSeconds) return;
    }

    final now = DateTime.now();
    final currentSpeed = locationService.currentSpeedKmh;
    final peakG = sensorService.peakLinearG(_decisionWindow);
    final peakGyro = sensorService.peakAngularRad(_decisionWindow);
    final peakTilt = sensorService.peakTiltDeg(_decisionWindow);

    // Maintain speed history window for the legacy "all met" path
    _speedHistory.add(_SpeedRecord(time: now, speed: currentSpeed));
    _speedHistory.removeWhere(
      (r) => now.difference(r.time) > _decisionWindow,
    );

    // ============================================================
    //  STATE: verifying — a hard impact was seen; wait for GPS to
    //  confirm a corresponding speed-drop.
    // ============================================================
    if (_state == DetectionState.verifying) {
      final windowMs = thresholds.verificationWindowMs;
      final inWindow = _impactAt != null &&
          now.difference(_impactAt!).inMilliseconds <= windowMs;

      if (!inWindow) {
        // Window expired without a confirming speed drop. Cancel.
        _state = DetectionState.armed;
        _impactAt = null;
        _speedAtImpact = null;
        return;
      }

      final speedAtImpact = _speedAtImpact ?? currentSpeed;
      final drop = speedAtImpact - currentSpeed;
      if (drop >= thresholds.speedDropKmh) {
        final pos = locationService.currentPosition;
        _fireCrash(
          speedBefore: speedAtImpact,
          speedAfter: currentSpeed,
          gForce: _peakGAtImpact,
          angularVelocity: _peakGyroAtImpact,
          tiltRate: _peakTiltAtImpact,
          latitude: pos?.latitude ?? 0.0,
          longitude: pos?.longitude ?? 0.0,
        );
        return;
      }

      // Still waiting for the GPS sample to land; do nothing this tick.
      return;
    }

    // ============================================================
    //  STATE: idle → arm if moving fast enough
    // ============================================================
    if (_state == DetectionState.idle) {
      if (currentSpeed >= thresholds.minSpeedKmh) {
        _state = DetectionState.armed;
        _armedAt = now;
      }
      return;
    }

    // ============================================================
    //  STATE: armed — watch for either stage-1 impact or legacy
    //  "all signals met" path.
    // ============================================================
    if (_state == DetectionState.armed) {
      // Disarm if user has been too slow for too long (parked)
      if (_armedAt != null) {
        final armedFor = now.difference(_armedAt!);
        if (armedFor > const Duration(seconds: 10) &&
            currentSpeed < thresholds.minSpeedKmh) {
          _state = DetectionState.idle;
          _speedHistory.clear();
          _conditionsMetSince = null;
          return;
        }
      }

      // ---- Stage 1: instant impact detection ----
      // Use the strict "hard impact" thresholds; they should be set higher
      // than the soft `gForceThreshold` / `gyroThreshold` so road bumps and
      // potholes don't open windows. When one fires, we transition to
      // `verifying` and let GPS catch up over the next few seconds.
      final hardGMet = peakG >= thresholds.hardImpactG;
      final hardGyroMet = peakGyro >= thresholds.hardImpactGyro;
      if (hardGMet || hardGyroMet) {
        _state = DetectionState.verifying;
        _impactAt = now;
        // Capture the GPS speed *right now* as the baseline. If GPS is
        // reporting the pre-impact speed, that's fine — within the
        // verification window it will report the post-impact speed and the
        // drop will be measured against this baseline.
        _speedAtImpact = currentSpeed;
        _peakGAtImpact = peakG;
        _peakGyroAtImpact = peakGyro;
        _peakTiltAtImpact = peakTilt;
        // No need to wait for the next tick — check verification this tick.
        // Recurse once to see if the drop is already observable.
        _evaluate();
        return;
      }

      // ---- Stage 1b: legacy "all met" path (fast path) ----
      // This path handles the lucky case where GPS happens to be mid-update
      // at the same tick as the impact. The confirmation timer prevents
      // a single sample from firing.
      final peakRecentSpeed = _speedHistory.isEmpty
          ? currentSpeed
          : _speedHistory
              .map((r) => r.speed)
              .reduce((a, b) => a > b ? a : b);
      final speedDrop = peakRecentSpeed - currentSpeed;
      final effectiveG = _effectiveGThreshold(currentSpeed);
      final gMet = peakG >= effectiveG;
      final gyroMet = peakGyro >= thresholds.gyroThreshold;
      final tiltMet = thresholds.useTiltSignal &&
          peakTilt >= thresholds.tiltThresholdDegPerSec;
      final speedMet = speedDrop >= thresholds.speedDropKmh;
      // 2-of-3 when tilt signal is on (speed + at least two of {G, gyro, tilt}),
      // otherwise the strict 2-of-2 (speed + G + gyro all met).
      final allMet = thresholds.useTiltSignal
          ? (speedMet &&
              ((gMet && gyroMet) || (gMet && tiltMet) || (gyroMet && tiltMet)))
          : (speedMet && gMet && gyroMet);

      if (allMet) {
        _conditionsMetSince ??= now;
        final held = now.difference(_conditionsMetSince!).inMilliseconds;
        if (held >= thresholds.confirmationMs) {
          final pos = locationService.currentPosition;
          _fireCrash(
            speedBefore: peakRecentSpeed,
            speedAfter: currentSpeed,
            gForce: peakG,
            angularVelocity: peakGyro,
            tiltRate: peakTilt,
            latitude: pos?.latitude ?? 0.0,
            longitude: pos?.longitude ?? 0.0,
          );
          return;
        }
      } else {
        _conditionsMetSince = null;
      }
    }
  }

  /// Adaptive G threshold: at higher speeds we expect harder deceleration, so
  /// we lower the bar a bit. At 30 km/h we require 100% of `gForceThreshold`;
  /// at 100+ km/h we only require 70%.
  double _effectiveGThreshold(double speedKmh) {
    if (!thresholds.adaptiveThresholds) return thresholds.gForceThreshold;
    final t = ((speedKmh - 30) / 70).clamp(0.0, 1.0); // 0 at 30, 1 at 100+
    return thresholds.gForceThreshold * (1.0 - 0.3 * t);
  }

  void _fireCrash({
    required double speedBefore,
    required double speedAfter,
    required double gForce,
    required double angularVelocity,
    required double tiltRate,
    required double latitude,
    required double longitude,
  }) {
    _state = DetectionState.crashed;
    _lastCrashTime = DateTime.now();

    final event = CrashEvent(
      timestamp: DateTime.now(),
      speedBefore: speedBefore,
      speedAfter: speedAfter,
      peakGForce: gForce,
      peakAngularVelocity: angularVelocity,
      peakTiltRate: tiltRate,
      latitude: latitude,
      longitude: longitude,
    );

    onCrashDetected?.call(event);
  }

  void resetAfterAlert() {
    _resetAll();
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
