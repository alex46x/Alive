import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/sensor_data.dart';
import 'crash_detector_task_handler.dart';

/// Thin wrapper around `flutter_foreground_task` so the rest of the app
/// can `init()`, `start()`, `update()`, and `stop()` without touching the
/// plugin API directly.
class ForegroundTaskService {
  static const _channelId = 'crash_detector_fg';
  static const _channelName = 'Crash Detector Background';
  static const _channelDesc = 'Keeps crash detection running while driving';

  // Crash events coming back from the background isolate. Stream so the UI
  // can subscribe with `listen()` instead of holding a callback reference.
  final _dataController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  /// Initialize the plugin. Call once at app startup.
  Future<void> init() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDesc,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    // Listen for data from the background isolate
    FlutterForegroundTask.addTaskDataCallback(_onData);
  }

  void _onData(Object data) {
    if (data is Map) {
      _dataController.add(Map<String, dynamic>.from(data));
    }
  }

  /// Request the runtime permission for the foreground service notification
  /// (Android 13+). Returns true if granted.
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Start the foreground service with the given thresholds.
  Future<void> start(DetectionThresholds t) async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.saveData(key: 'minSpeedKmh', value: t.minSpeedKmh);
    await FlutterForegroundTask.saveData(
        key: 'speedDropKmh', value: t.speedDropKmh);
    await FlutterForegroundTask.saveData(
        key: 'gForceThreshold', value: t.gForceThreshold);
    await FlutterForegroundTask.saveData(
        key: 'gyroThreshold', value: t.gyroThreshold);
    await FlutterForegroundTask.saveData(
        key: 'adaptiveThresholds', value: t.adaptiveThresholds);
    await FlutterForegroundTask.saveData(
        key: 'emergencyNumber', value: t.emergencyNumber);
    await FlutterForegroundTask.saveData(
        key: 'hardImpactG', value: t.hardImpactG);
    await FlutterForegroundTask.saveData(
        key: 'hardImpactGyro', value: t.hardImpactGyro);
    await FlutterForegroundTask.saveData(
        key: 'verificationWindowMs', value: t.verificationWindowMs);

    await FlutterForegroundTask.startService(
      notificationTitle: 'Crash Detector — monitoring',
      notificationText: 'Detection engine running',
      callback: startCallback,
    );
  }

  /// Push updated thresholds to the running task.
  Future<void> updateThresholds(DetectionThresholds t) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    FlutterForegroundTask.sendDataToTask({
      'minSpeedKmh': t.minSpeedKmh,
      'speedDropKmh': t.speedDropKmh,
      'gForceThreshold': t.gForceThreshold,
      'gyroThreshold': t.gyroThreshold,
      'adaptiveThresholds': t.adaptiveThresholds,
      'emergencyNumber': t.emergencyNumber,
      'hardImpactG': t.hardImpactG,
      'hardImpactGyro': t.hardImpactGyro,
      'verificationWindowMs': t.verificationWindowMs,
    });
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  /// Release the broadcast stream - call when the app is being torn down.
  void dispose() {
    _dataController.close();
  }
}

/// Top-level entry point required by `flutter_foreground_task`. Must be a
/// top-level or static function. Hands control to [CrashDetectorTaskHandler].
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CrashDetectorTaskHandler());
}
