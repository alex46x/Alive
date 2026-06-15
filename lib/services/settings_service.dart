import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_data.dart';

/// Persists user-configurable thresholds and emergency number across app
/// launches. Wraps `shared_preferences` so the rest of the app does not have
/// to know about the storage backend.
class SettingsService {
  static const _kMinSpeed = 'min_speed_kmh';
  static const _kSpeedDrop = 'speed_drop_kmh';
  static const _kGForce = 'g_force_threshold';
  static const _kGyro = 'gyro_threshold';
  static const _kTilt = 'tilt_threshold_dps';
  static const _kConfirmationMs = 'confirmation_ms';
  static const _kAdaptive = 'adaptive_thresholds';
  static const _kUseTilt = 'use_tilt_signal';
  static const _kEmergency = 'emergency_number';
  static const _kHardImpactG = 'hard_impact_g';
  static const _kHardImpactGyro = 'hard_impact_gyro';
  static const _kVerificationWindowMs = 'verification_window_ms';

  Future<DetectionThresholds> load() async {
    final p = await SharedPreferences.getInstance();
    return DetectionThresholds(
      minSpeedKmh: p.getDouble(_kMinSpeed) ?? 30.0,
      speedDropKmh: p.getDouble(_kSpeedDrop) ?? 20.0,
      gForceThreshold: p.getDouble(_kGForce) ?? 2.5,
      gyroThreshold: p.getDouble(_kGyro) ?? 3.0,
      tiltThresholdDegPerSec: p.getDouble(_kTilt) ?? 90.0,
      confirmationMs: p.getInt(_kConfirmationMs) ?? 200,
      adaptiveThresholds: p.getBool(_kAdaptive) ?? true,
      useTiltSignal: p.getBool(_kUseTilt) ?? false,
      emergencyNumber: p.getString(_kEmergency) ?? '',
      hardImpactG: p.getDouble(_kHardImpactG) ?? 4.0,
      hardImpactGyro: p.getDouble(_kHardImpactGyro) ?? 6.0,
      verificationWindowMs: p.getInt(_kVerificationWindowMs) ?? 3000,
    );
  }

  Future<void> save(DetectionThresholds t) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kMinSpeed, t.minSpeedKmh);
    await p.setDouble(_kSpeedDrop, t.speedDropKmh);
    await p.setDouble(_kGForce, t.gForceThreshold);
    await p.setDouble(_kGyro, t.gyroThreshold);
    await p.setDouble(_kTilt, t.tiltThresholdDegPerSec);
    await p.setInt(_kConfirmationMs, t.confirmationMs);
    await p.setBool(_kAdaptive, t.adaptiveThresholds);
    await p.setBool(_kUseTilt, t.useTiltSignal);
    await p.setString(_kEmergency, t.emergencyNumber);
    await p.setDouble(_kHardImpactG, t.hardImpactG);
    await p.setDouble(_kHardImpactGyro, t.hardImpactGyro);
    await p.setInt(_kVerificationWindowMs, t.verificationWindowMs);
  }
}
