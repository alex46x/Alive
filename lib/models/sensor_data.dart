// Models for sensor data and crash events

class SensorSnapshot {
  final double gForce;
  final double angularVelocity;
  final double speedKmh;
  final DateTime timestamp;

  SensorSnapshot({
    required this.gForce,
    required this.angularVelocity,
    required this.speedKmh,
    required this.timestamp,
  });
}

class CrashEvent {
  final DateTime timestamp;
  final double speedBefore;
  final double speedAfter;
  final double peakGForce;
  final double peakAngularVelocity;

  CrashEvent({
    required this.timestamp,
    required this.speedBefore,
    required this.speedAfter,
    required this.peakGForce,
    required this.peakAngularVelocity,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class DetectionThresholds {
  double minSpeedKmh;        // Must be moving above this to arm detection
  double speedDropKmh;       // Speed must drop by this amount
  double gForceThreshold;    // G-force spike threshold (in g)
  double gyroThreshold;      // Angular velocity threshold (rad/s)

  DetectionThresholds({
    this.minSpeedKmh = 30.0,
    this.speedDropKmh = 25.0,
    this.gForceThreshold = 2.5,
    this.gyroThreshold = 3.0,
  });

  DetectionThresholds copyWith({
    double? minSpeedKmh,
    double? speedDropKmh,
    double? gForceThreshold,
    double? gyroThreshold,
  }) {
    return DetectionThresholds(
      minSpeedKmh: minSpeedKmh ?? this.minSpeedKmh,
      speedDropKmh: speedDropKmh ?? this.speedDropKmh,
      gForceThreshold: gForceThreshold ?? this.gForceThreshold,
      gyroThreshold: gyroThreshold ?? this.gyroThreshold,
    );
  }
}
