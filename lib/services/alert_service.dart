import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AlertService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAlerting = false;

  bool get isAlerting => _isAlerting;

  Future<void> startAlert() async {
    if (_isAlerting) return;
    _isAlerting = true;

    // Keep screen on
    await WakelockPlus.enable();

    // Play alarm sound on loop
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.setVolume(1.0);
    try {
      await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
    } catch (e) {
      // Sound file might not exist in simulator; ignore
    }

    // Start strong vibration pattern
    _startVibration();
  }

  void _startVibration() async {
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Repeating pattern: 500ms on, 300ms off (custom amplitude)
      bool? hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude == true) {
        Vibration.vibrate(
          pattern: [0, 800, 300, 800, 300, 800, 300, 800],
          intensities: [0, 255, 0, 255, 0, 255, 0, 255],
          repeat: 0, // repeat from index 0
        );
      } else {
        Vibration.vibrate(
          pattern: [0, 800, 300, 800, 300, 800],
          repeat: 0,
        );
      }
    }
  }

  Future<void> stopAlert() async {
    if (!_isAlerting) return;
    _isAlerting = false;

    await _audioPlayer.stop();
    Vibration.cancel();
    await WakelockPlus.disable();
  }

  void dispose() {
    stopAlert();
    _audioPlayer.dispose();
  }
}
