import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:math';

/// Background-isolate task handler that mirrors the 2-stage
/// "impact-then-verify" decision from [CrashDetectorService].
///
/// **Stage 1 (instant):** A hard G or gyro spike opens a verification window
/// and captures the GPS speed at that moment.
///
/// **Stage 2 (over the next N seconds):** Watch the current GPS speed; fire
/// as soon as `speedAtImpact - currentSpeed >= speedDropKmh`.
///
/// The legacy "all signals met" path is kept as a fast-path for the rare case
/// where GPS aligns with the impact tick.
class CrashDetectorTaskHandler extends TaskHandler {
  // === Config (set on start) ===
  double minSpeedKmh = 30.0;
  double speedDropKmh = 20.0;
  double gForceThreshold = 2.5;
  double gyroThreshold = 3.0;
  bool adaptiveThresholds = true;
  String emergencyNumber = '';
  // 2-stage thresholds
  double hardImpactG = 4.0;
  double hardImpactGyro = 6.0;
  int verificationWindowMs = 3000;

  // === State ===
  StreamSubscription<Position>? _posSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _checkTimer;

  // Detection state machine
  _DetState _state = _DetState.idle;
  DateTime? _armedAt;
  DateTime? _conditionsMetSince; // legacy "all met" confirmation timer

  // 2-stage verification state
  DateTime? _impactAt;
  double? _speedAtImpact;
  double _peakGAtImpact = 0;
  double _peakGyroAtImpact = 0;

  bool _crashed = false;
  DateTime? _lastCrash;
  final List<_SpeedRecord> _speedHistory = [];
  static const Duration _window = Duration(seconds: 4);
  static const Duration _cooldown = Duration(seconds: 15);

  // LPF gravity vector for linear-accel extraction
  static const double _lpfAlpha = 0.1;
  static const double _gravity = 9.80665;
  double _gx = 0, _gy = 0, _gz = -1;
  // Peaks in the decision window
  double _peakG = 0;
  double _peakGyro = 0;
  DateTime? _lastSampleTime;

  double _lastSpeedKmh = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Best-effort: try to keep the screen on while running.
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    // Apply config passed via FlutterForegroundTask.saveData(key, value)
    final cfg = await FlutterForegroundTask.getAllData();
    minSpeedKmh = (cfg['minSpeedKmh'] as num?)?.toDouble() ?? minSpeedKmh;
    speedDropKmh = (cfg['speedDropKmh'] as num?)?.toDouble() ?? speedDropKmh;
    gForceThreshold =
        (cfg['gForceThreshold'] as num?)?.toDouble() ?? gForceThreshold;
    gyroThreshold =
        (cfg['gyroThreshold'] as num?)?.toDouble() ?? gyroThreshold;
    adaptiveThresholds =
        cfg['adaptiveThresholds'] as bool? ?? adaptiveThresholds;
    emergencyNumber = cfg['emergencyNumber'] as String? ?? emergencyNumber;
    hardImpactG = (cfg['hardImpactG'] as num?)?.toDouble() ?? hardImpactG;
    hardImpactGyro =
        (cfg['hardImpactGyro'] as num?)?.toDouble() ?? hardImpactGyro;
    verificationWindowMs =
        (cfg['verificationWindowMs'] as num?)?.toInt() ?? verificationWindowMs;

    _startSensors();
    _startGps();
    _checkTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _evaluate());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat update to the notification.
    final stateLabel = _state == _DetState.verifying
        ? 'VERIFYING'
        : _state == _DetState.armed
            ? 'ARMED'
            : 'monitoring';
    FlutterForegroundTask.updateService(
      notificationTitle: 'Crash Detector — $stateLabel',
      notificationText:
          'Speed: ${_lastSpeedKmh.toStringAsFixed(0)} km/h  •  Peak G: ${_peakG.toStringAsFixed(1)}',
    );
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data['minSpeedKmh'] != null) {
        minSpeedKmh = (data['minSpeedKmh'] as num).toDouble();
      }
      if (data['speedDropKmh'] != null) {
        speedDropKmh = (data['speedDropKmh'] as num).toDouble();
      }
      if (data['gForceThreshold'] != null) {
        gForceThreshold = (data['gForceThreshold'] as num).toDouble();
      }
      if (data['gyroThreshold'] != null) {
        gyroThreshold = (data['gyroThreshold'] as num).toDouble();
      }
      if (data['adaptiveThresholds'] is bool) {
        adaptiveThresholds = data['adaptiveThresholds'] as bool;
      }
      if (data['emergencyNumber'] is String) {
        emergencyNumber = data['emergencyNumber'] as String;
      }
      if (data['hardImpactG'] != null) {
        hardImpactG = (data['hardImpactG'] as num).toDouble();
      }
      if (data['hardImpactGyro'] != null) {
        hardImpactGyro = (data['hardImpactGyro'] as num).toDouble();
      }
      if (data['verificationWindowMs'] != null) {
        verificationWindowMs = (data['verificationWindowMs'] as num).toInt();
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _posSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _checkTimer?.cancel();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  // === Sensor streams ===

  void _startSensors() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((e) {
      // LPF gravity vector
      final m = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (m > 1e-6) {
        _gx = _lpfAlpha * (e.x / m) + (1 - _lpfAlpha) * _gx;
        _gy = _lpfAlpha * (e.y / m) + (1 - _lpfAlpha) * _gy;
        _gz = _lpfAlpha * (e.z / m) + (1 - _lpfAlpha) * _gz;
      }
      final linearG = ((m - _gravity).abs()) / _gravity;
      if (linearG > _peakG) _peakG = linearG;
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((e) {
      final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (mag > _peakGyro) _peakGyro = mag;
    });
  }

  void _startGps() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 1000),
        forceLocationManager: false,
      ),
    ).listen((p) {
      if (p.accuracy > 20) return;
      final kmh = (p.speed < 0 ? 0 : p.speed) * 3.6;
      _lastSpeedKmh = kmh;
      final now = DateTime.now();
      _speedHistory.add(_SpeedRecord(now, kmh));
      _speedHistory.removeWhere((r) => now.difference(r.time) > _window);
    });
  }

  // === Decision logic (mirrors CrashDetectorService._evaluate) ===

  void _evaluate() {
    if (_crashed) return;
    if (_lastCrash != null &&
        DateTime.now().difference(_lastCrash!) < _cooldown) {
      return;
    }

    final now = DateTime.now();
    // Reset peaks if the window has elapsed without a fresh sample.
    if (_lastSampleTime == null ||
        now.difference(_lastSampleTime!) > _window) {
      _peakG = 0;
      _peakGyro = 0;
    }
    _lastSampleTime = now;

    if (_speedHistory.isEmpty) return;

    // ============================================================
    //  STATE: verifying — a hard impact was seen; wait for GPS to
    //  confirm a corresponding speed-drop.
    // ============================================================
    if (_state == _DetState.verifying) {
      final inWindow = _impactAt != null &&
          now.difference(_impactAt!).inMilliseconds <= verificationWindowMs;

      if (!inWindow) {
        // Window expired without a confirming speed drop. Cancel.
        _state = _DetState.armed;
        _impactAt = null;
        _speedAtImpact = null;
        return;
      }

      final speedAtImpact = _speedAtImpact ?? _lastSpeedKmh;
      final drop = speedAtImpact - _lastSpeedKmh;
      if (drop >= speedDropKmh) {
        _fireCrash(
          speedBefore: speedAtImpact,
          speedAfter: _lastSpeedKmh,
          peakG: _peakGAtImpact,
          peakGyro: _peakGyroAtImpact,
        );
        return;
      }

      // Still waiting for the GPS sample to land; do nothing this tick.
      return;
    }

    // ============================================================
    //  STATE: idle → arm if moving fast enough
    // ============================================================
    if (_state == _DetState.idle) {
      if (_lastSpeedKmh >= minSpeedKmh) {
        _state = _DetState.armed;
        _armedAt = now;
      }
      return;
    }

    // ============================================================
    //  STATE: armed — watch for either stage-1 impact or legacy
    //  "all signals met" path.
    // ============================================================
    if (_state == _DetState.armed) {
      // Disarm if user has been too slow for too long (parked)
      if (_armedAt != null) {
        final armedFor = now.difference(_armedAt!);
        if (armedFor > const Duration(seconds: 10) &&
            _lastSpeedKmh < minSpeedKmh) {
          _state = _DetState.idle;
          _speedHistory.clear();
          _conditionsMetSince = null;
          return;
        }
      }

      // ---- Stage 1: instant impact detection ----
      final hardGMet = _peakG >= hardImpactG;
      final hardGyroMet = _peakGyro >= hardImpactGyro;
      if (hardGMet || hardGyroMet) {
        _state = _DetState.verifying;
        _impactAt = now;
        _speedAtImpact = _lastSpeedKmh;
        _peakGAtImpact = _peakG;
        _peakGyroAtImpact = _peakGyro;
        // Recurse once to see if the drop is already observable.
        _evaluate();
        return;
      }

      // ---- Stage 1b: legacy "all met" path (fast path) ----
      final peakSpeed =
          _speedHistory.map((r) => r.speed).reduce((a, b) => a > b ? a : b);
      final speedDrop = peakSpeed - _lastSpeedKmh;
      final effectiveG = _effectiveG(_lastSpeedKmh);
      final gMet = _peakG >= effectiveG;
      final gyroMet = _peakGyro >= gyroThreshold;
      final speedMet = speedDrop >= speedDropKmh;
      final allMet = speedMet && gMet && gyroMet;

      if (allMet) {
        _conditionsMetSince ??= now;
        final held = now.difference(_conditionsMetSince!).inMilliseconds;
        if (held >= 200) {
          // 200 ms confirmation hold (mirrors default confirmationMs)
          _fireCrash(
            speedBefore: peakSpeed,
            speedAfter: _lastSpeedKmh,
            peakG: _peakG,
            peakGyro: _peakGyro,
          );
          return;
        }
      } else {
        _conditionsMetSince = null;
      }
    }
  }

  double _effectiveG(double kmh) {
    if (!adaptiveThresholds) return gForceThreshold;
    final t = ((kmh - 30) / 70).clamp(0.0, 1.0);
    return gForceThreshold * (1.0 - 0.3 * t);
  }

  void _fireCrash({
    required double speedBefore,
    required double speedAfter,
    required double peakG,
    required double peakGyro,
  }) {
    _crashed = true;
    _state = _DetState.crashed;
    _lastCrash = DateTime.now();
    // Send crash event to UI isolate
    FlutterForegroundTask.sendDataToMain({
      'event': 'crash',
      'speedBefore': speedBefore,
      'speedAfter': speedAfter,
      'peakG': peakG,
      'peakGyro': peakGyro,
      'latitude': 0.0, // location not tracked here to keep task lean
      'longitude': 0.0,
    });
  }
}

/// Minimal detection state enum for the background isolate.
enum _DetState { idle, armed, verifying, crashed }

class _SpeedRecord {
  final DateTime time;
  final double speed;
  _SpeedRecord(this.time, this.speed);
}
