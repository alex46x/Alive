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
  final double peakTiltRate;
  final double latitude;
  final double longitude;

  CrashEvent({
    required this.timestamp,
    required this.speedBefore,
    required this.speedAfter,
    required this.peakGForce,
    required this.peakAngularVelocity,
    required this.peakTiltRate,
    required this.latitude,
    required this.longitude,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class DetectionThresholds {
  double minSpeedKmh;          // Must be moving above this to arm detection
  double speedDropKmh;         // Speed must drop by this amount
  double gForceThreshold;      // G-force spike threshold (in g, linear / net)
  double gyroThreshold;        // Angular velocity threshold (rad/s)
  double tiltThresholdDegPerSec; // Optional roll/pitch rate trigger (deg/s)
  int confirmationMs;          // All conditions must be met for this long
  bool adaptiveThresholds;     // Lower G threshold at higher speeds
  bool useTiltSignal;          // If true, tilt rate counts toward crash
  String emergencyNumber;

  // === 2-stage (impact-then-verify) detection ===
  // Stage 1: a single, immediate spike at or above these "hard impact"
  // thresholds opens a verification window. They should be set a bit higher
  // than the regular gForce/gyro thresholds to filter out road bumps.
  double hardImpactG;          // G level that instantly opens the verify window
  double hardImpactGyro;       // Gyro level that instantly opens the verify window
  // Stage 2: how long to wait for the GPS speed-drop to confirm the impact.
  // GPS is 1Hz and usually lags the impact by 1-2 seconds, so 3s is safe.
  int verificationWindowMs;

  DetectionThresholds({
    this.minSpeedKmh = 30.0,
    this.speedDropKmh = 20.0,
    this.gForceThreshold = 2.5,
    this.gyroThreshold = 3.0,
    this.tiltThresholdDegPerSec = 90.0,
    this.confirmationMs = 200,
    this.adaptiveThresholds = true,
    this.useTiltSignal = false,
    this.emergencyNumber = '',
    this.hardImpactG = 4.0,
    this.hardImpactGyro = 6.0,
    this.verificationWindowMs = 3000,
  });

  DetectionThresholds copyWith({
    double? minSpeedKmh,
    double? speedDropKmh,
    double? gForceThreshold,
    double? gyroThreshold,
    double? tiltThresholdDegPerSec,
    int? confirmationMs,
    bool? adaptiveThresholds,
    bool? useTiltSignal,
    String? emergencyNumber,
    double? hardImpactG,
    double? hardImpactGyro,
    int? verificationWindowMs,
  }) {
    return DetectionThresholds(
      minSpeedKmh: minSpeedKmh ?? this.minSpeedKmh,
      speedDropKmh: speedDropKmh ?? this.speedDropKmh,
      gForceThreshold: gForceThreshold ?? this.gForceThreshold,
      gyroThreshold: gyroThreshold ?? this.gyroThreshold,
      tiltThresholdDegPerSec:
          tiltThresholdDegPerSec ?? this.tiltThresholdDegPerSec,
      confirmationMs: confirmationMs ?? this.confirmationMs,
      adaptiveThresholds: adaptiveThresholds ?? this.adaptiveThresholds,
      useTiltSignal: useTiltSignal ?? this.useTiltSignal,
      emergencyNumber: emergencyNumber ?? this.emergencyNumber,
      hardImpactG: hardImpactG ?? this.hardImpactG,
      hardImpactGyro: hardImpactGyro ?? this.hardImpactGyro,
      verificationWindowMs: verificationWindowMs ?? this.verificationWindowMs,
    );
  }
}
