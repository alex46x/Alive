import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  final StreamController<double> _speedController =
      StreamController<double>.broadcast();

  Stream<double> get speedStream => _speedController.stream;

  StreamSubscription<Position>? _positionSubscription;
  double _currentSpeedKmh = 0.0;
  double _previousSpeedKmh = 0.0;

  double get currentSpeedKmh => _currentSpeedKmh;
  double get previousSpeedKmh => _previousSpeedKmh;

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
      _previousSpeedKmh = _currentSpeedKmh;

      // GPS gives speed in m/s → convert to km/h
      _currentSpeedKmh =
          (position.speed < 0 ? 0 : position.speed) * 3.6;

      _speedController.add(_currentSpeedKmh);
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
