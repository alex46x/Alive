import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {
  // Streams
  final StreamController<double> _gForceController =
      StreamController<double>.broadcast();
  final StreamController<double> _gyroController =
      StreamController<double>.broadcast();

  Stream<double> get gForceStream => _gForceController.stream;
  Stream<double> get gyroStream => _gyroController.stream;

  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;

  double _currentGForce = 1.0; // 1g at rest
  double _currentAngularVelocity = 0.0;

  // Rolling peak values (reset every 2 seconds)
  double _peakGForce = 1.0;
  double _peakAngularVelocity = 0.0;
  Timer? _peakResetTimer;

  double get currentGForce => _currentGForce;
  double get currentAngularVelocity => _currentAngularVelocity;
  double get peakGForce => _peakGForce;
  double get peakAngularVelocity => _peakAngularVelocity;

  static const double _gravity = 9.80665;

  void start() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((AccelerometerEvent event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _currentGForce = magnitude / _gravity;

      if (_currentGForce > _peakGForce) {
        _peakGForce = _currentGForce;
      }

      _gForceController.add(_currentGForce);
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((GyroscopeEvent event) {
      _currentAngularVelocity = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      if (_currentAngularVelocity > _peakAngularVelocity) {
        _peakAngularVelocity = _currentAngularVelocity;
      }

      _gyroController.add(_currentAngularVelocity);
    });

    // Reset peaks every 2 seconds (sliding window)
    _peakResetTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _peakGForce = _currentGForce;
      _peakAngularVelocity = _currentAngularVelocity;
    });
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _peakResetTimer?.cancel();
    _peakResetTimer = null;
  }

  void dispose() {
    stop();
    _gForceController.close();
    _gyroController.close();
  }
}
