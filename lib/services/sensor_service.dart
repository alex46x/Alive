import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

/// Single sample in the rolling window. Kept lightweight on purpose because we
/// keep several seconds of data for the detector to query.
class _Sample {
  final DateTime time;
  final double linearG;       // |accel - gravity|, in g
  final double angularRad;    // |gyro| in rad/s
  final double tiltRateDeg;   // gravity-vector rotation rate in deg/s
  const _Sample(this.time, this.linearG, this.angularRad, this.tiltRateDeg);
}

/// Streams + rolling window of accelerometer / gyroscope readings.
///
/// Key changes from the v1 service:
///   * Reports **linear** G (gravity removed) instead of raw |a|, so braking
///     and gentle road imperfections don't show as 1g baseline shifts.
///   * Keeps a 5-second ring buffer; the detector queries this buffer to get
///     peaks over the **same** window it uses for speed drop.
///   * Computes a tilt rate (deg/s) from the gravity vector rotation; the
///     detector can use it for rollover detection.
class SensorService {
  static const double _gravity = 9.80665;
  static const Duration _samplePeriod = Duration(milliseconds: 50);
  static const Duration _bufferWindow = Duration(seconds: 5);

  final StreamController<double> _linearGController =
      StreamController<double>.broadcast();
  final StreamController<double> _gyroController =
      StreamController<double>.broadcast();
  final StreamController<double> _tiltController =
      StreamController<double>.broadcast();

  Stream<double> get linearGStream => _linearGController.stream;
  Stream<double> get gyroStream => _gyroController.stream;
  Stream<double> get tiltStream => _tiltController.stream;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  // Latest values (for live UI tiles)
  double _currentLinearG = 0.0;
  double _currentAngularRad = 0.0;
  double _currentTiltRateDeg = 0.0;

  double get currentLinearG => _currentLinearG;
  double get currentAngularVelocity => _currentAngularRad;
  double get currentTiltRateDeg => _currentTiltRateDeg;

  // Sliding window of samples
  final Queue<_Sample> _window = Queue<_Sample>();

  // Gravity LPF state (alpha chosen for ~0.5s time constant at 20Hz)
  static const double _lpfAlpha = 0.1;
  double _gx = 0, _gy = 0, _gz = -1; // unit gravity vector (start at -Z)
  DateTime? _lastGyroTime;

  void start() {
    _accelSub = accelerometerEventStream(samplingPeriod: _samplePeriod)
        .listen((AccelerometerEvent e) => _onAccel(e));
    _gyroSub = gyroscopeEventStream(samplingPeriod: _samplePeriod)
        .listen((GyroscopeEvent e) => _onGyro(e));
  }

  void _onAccel(AccelerometerEvent e) {
    // Normalize and LPF the gravity vector, then subtract from raw accel to
    // get linear acceleration. This is the standard "gravity compensation"
    // trick used in motion-tracking.
    final rawG = _normalize(e.x, e.y, e.z);
    _gx = _lpfAlpha * rawG.$1 + (1 - _lpfAlpha) * _gx;
    _gy = _lpfAlpha * rawG.$2 + (1 - _lpfAlpha) * _gy;
    _gz = _lpfAlpha * rawG.$3 + (1 - _lpfAlpha) * _gz;

    // Linear acceleration in m/s^2 = raw minus the gravity vector magnitude
    // projected onto the raw direction. Simpler: just subtract 1g from the
    // magnitude, since at rest the phone is roughly aligned to gravity.
    final rawMag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final linearAccelMs2 = (rawMag - _gravity).abs();
    final linearG = linearAccelMs2 / _gravity;

    _currentLinearG = linearG;
    _linearGController.add(linearG);

    _addSample(linearG, _currentAngularRad, _currentTiltRateDeg);
  }

  void _onGyro(GyroscopeEvent e) {
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _currentAngularRad = mag;
    _gyroController.add(mag);

    // Tilt rate: integrate the gravity cross-product between successive gyro
    // samples. A simpler, robust approximation is the magnitude of the gyro
    // perpendicular to the current gravity vector.
    final now = DateTime.now();
    if (_lastGyroTime != null) {
      final dt = now.difference(_lastGyroTime!).inMicroseconds / 1e6;
      if (dt > 0) {
        // Component of gyro that is perpendicular to gravity vector.
        // (g_unit cross omega) magnitude is the tilt rate in rad/s.
        final gx = _gx, gy = _gy, gz = _gz;
        final ox = e.x, oy = e.y, oz = e.z;
        final cx = gy * oz - gz * oy;
        final cy = gz * ox - gx * oz;
        final cz = gx * oy - gy * ox;
        final tiltRad = sqrt(cx * cx + cy * cy + cz * cz);
        _currentTiltRateDeg = tiltRad * (180.0 / pi);
        _tiltController.add(_currentTiltRateDeg);
      }
    }
    _lastGyroTime = now;

    _addSample(_currentLinearG, _currentAngularRad, _currentTiltRateDeg);
  }

  void _addSample(double g, double ang, double tilt) {
    final now = DateTime.now();
    _window.add(_Sample(now, g, ang, tilt));
    // Trim to window
    while (_window.isNotEmpty &&
        now.difference(_window.first.time) > _bufferWindow) {
      _window.removeFirst();
    }
  }

  /// Peak linear G in the last [window] duration (defaults to the full buffer).
  double peakLinearG([Duration window = _bufferWindow]) {
    return _peak((s) => s.linearG, window);
  }

  /// Peak angular velocity in the last [window] duration, in rad/s.
  double peakAngularRad([Duration window = _bufferWindow]) {
    return _peak((s) => s.angularRad, window);
  }

  /// Peak tilt rate in the last [window] duration, in deg/s.
  double peakTiltDeg([Duration window = _bufferWindow]) {
    return _peak((s) => s.tiltRateDeg, window);
  }

  double _peak(double Function(_Sample) pick, Duration window) {
    final cutoff = DateTime.now().subtract(window);
    double best = 0;
    for (final s in _window) {
      if (s.time.isBefore(cutoff)) continue;
      final v = pick(s);
      if (v > best) best = v;
    }
    return best;
  }

  // Unit vector helper. Returns (x,y,z) scaled to magnitude 1. Handles the
  // degenerate near-zero case gracefully.
  (double, double, double) _normalize(double x, double y, double z) {
    final m = sqrt(x * x + y * y + z * z);
    if (m < 1e-6) return (0, 0, -1);
    return (x / m, y / m, z / m);
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
  }

  void dispose() {
    stop();
    _linearGController.close();
    _gyroController.close();
    _tiltController.close();
  }
}
