import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  final StreamController<double> _speedController =
      StreamController<double>.broadcast();

  Stream<double> get speedStream => _speedController.stream;

  StreamSubscription<Position>? _positionSubscription;
  double _currentSpeedKmh = 0.0;
  double _previousSpeedKmh = 0.0;
  Position? _previousPosition;
  DateTime? _previousTime;

  double get currentSpeedKmh => _currentSpeedKmh;
  double get previousSpeedKmh => _previousSpeedKmh;
  Position? get currentPosition => _previousPosition;

  /// Start GPS streaming
  Future<void> start() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(milliseconds: 1000),
      forceLocationManager: false,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      
      // 1. Filter out highly inaccurate GPS points (e.g. indoors/bad signal)
      if (position.accuracy > 20.0) {
        debugPrint('Ignored inaccurate GPS point: ${position.accuracy}m');
        return;
      }

      _previousSpeedKmh = _currentSpeedKmh;

      double rawSpeed = position.speed;
      
      // 2. Manual calculation fallback with stricter jitter threshold
      if (rawSpeed <= 0 && _previousPosition != null && _previousTime != null) {
        final now = DateTime.now();
        final timeDiffSeconds = now.difference(_previousTime!).inMilliseconds / 1000.0;
        
        if (timeDiffSeconds > 0) {
          final distanceMeters = Geolocator.distanceBetween(
            _previousPosition!.latitude,
            _previousPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          
          // Ignore tiny positional jitter (< 3 meters) to prevent fake speeds while standing still
          if (distanceMeters > 3.0) { 
            rawSpeed = distanceMeters / timeDiffSeconds;
            debugPrint('Calculated manual speed: $rawSpeed m/s');
          } else {
            rawSpeed = 0.0; // Snap to 0 if we didn't move far enough
          }
        }
      }

      // Convert m/s -> km/h
      double newSpeedKmh = (rawSpeed < 0 ? 0 : rawSpeed) * 3.6;

      // 3. Low-pass filter to smooth out erratic jumps (fake speed spikes)
      // Blend 70% of the new speed with 30% of the old speed to smooth it
      if (newSpeedKmh > 0 && _currentSpeedKmh > 0) {
        _currentSpeedKmh = (_currentSpeedKmh * 0.3) + (newSpeedKmh * 0.7);
      } else {
        _currentSpeedKmh = newSpeedKmh;
      }

      debugPrint('Final Smoothed Speed: $_currentSpeedKmh km/h (Raw was $newSpeedKmh)');

      _speedController.add(_currentSpeedKmh);
      
      _previousPosition = position;
      _previousTime = DateTime.now();
    });
  }

  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void dispose() {
    stop();
    _speedController.close();
  }
}
