// Smoke tests for the crash detector data model.
//
// The full app needs platform channels (location, sensors, foreground service,
// shared_preferences) so a full widget test would require extensive mocking.
// These tests cover the parts that run in pure Dart: the thresholds model
// (defaults, copyWith, and the emergencyNumber fix from the Phase 1+2 upgrade).

import 'package:flutter_test/flutter_test.dart';
import 'package:crash_detector/models/sensor_data.dart';

void main() {
  group('DetectionThresholds', () {
    test('default constructor exposes all Phase 1+2 fields', () {
      final t = DetectionThresholds();
      expect(t.minSpeedKmh, 30.0);
      expect(t.speedDropKmh, 20.0);
      expect(t.gForceThreshold, 2.5);
      expect(t.gyroThreshold, 3.0);
      // New fields
      expect(t.tiltThresholdDegPerSec, 90.0);
      expect(t.confirmationMs, 200);
      expect(t.adaptiveThresholds, isTrue);
      expect(t.useTiltSignal, isFalse);
    });

    test('copyWith carries emergencyNumber through (regression for bug fix)', () {
      final original = DetectionThresholds(emergencyNumber: '+8801700000000');
      final copy = original.copyWith(gForceThreshold: 3.0);
      // The user changed the G threshold; the emergency number must survive.
      expect(copy.emergencyNumber, '+8801700000000');
      expect(copy.gForceThreshold, 3.0);
      // Untouched fields keep their previous values.
      expect(copy.minSpeedKmh, original.minSpeedKmh);
    });

    test('copyWith overrides all fields when given', () {
      final t = DetectionThresholds().copyWith(
        minSpeedKmh: 50,
        speedDropKmh: 25,
        gForceThreshold: 4.0,
        gyroThreshold: 5.0,
        tiltThresholdDegPerSec: 120,
        confirmationMs: 500,
        adaptiveThresholds: false,
        useTiltSignal: true,
        emergencyNumber: '911',
      );
      expect(t.minSpeedKmh, 50);
      expect(t.speedDropKmh, 25);
      expect(t.gForceThreshold, 4.0);
      expect(t.gyroThreshold, 5.0);
      expect(t.tiltThresholdDegPerSec, 120);
      expect(t.confirmationMs, 500);
      expect(t.adaptiveThresholds, isFalse);
      expect(t.useTiltSignal, isTrue);
      expect(t.emergencyNumber, '911');
    });
  });

  group('CrashEvent', () {
    test('records peak tilt rate from Phase 1+2 upgrade', () {
      final ev = CrashEvent(
        timestamp: DateTime(2026, 1, 1),
        speedBefore: 60,
        speedAfter: 5,
        peakGForce: 3.2,
        peakAngularVelocity: 4.5,
        peakTiltRate: 180.0,
        latitude: 23.81,
        longitude: 90.41,
      );
      expect(ev.peakTiltRate, 180.0);
      expect(ev.formattedTime, isNotEmpty);
    });
  });
}
