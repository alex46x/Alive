import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/sensor_data.dart';
import 'screens/home_screen.dart';
import 'services/foreground_task_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait (no-op on web, harmless if it throws)
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  // Load persisted settings (thresholds + emergency number) before the UI
  // starts so the first frame is correct.
  final settings = SettingsService();
  final thresholds = await settings.load();

  // Foreground service init - request POST_NOTIFICATIONS up front (Android 13+).
  // The plugin is mobile-only; on web we skip it entirely so the UI still
  // loads for visual debugging. `fg` is then null and the home screen hides
  // the start/stop controls.
  ForegroundTaskService? fg;
  if (!kIsWeb) {
    fg = ForegroundTaskService();
    await fg.init();
    await fg.requestNotificationPermission();
  }

  runApp(CrashDetectorApp(thresholds: thresholds, settings: settings, fg: fg));
}

class CrashDetectorApp extends StatefulWidget {
  final DetectionThresholds thresholds;
  final SettingsService settings;
  final ForegroundTaskService? fg;
  const CrashDetectorApp({
    super.key,
    required this.thresholds,
    required this.settings,
    required this.fg,
  });

  @override
  State<CrashDetectorApp> createState() => _CrashDetectorAppState();
}

class _CrashDetectorAppState extends State<CrashDetectorApp> {
  bool _permissionsGranted = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Crash detection needs:
    //  - Location (always or when-in-use) for speed
    //  - Phone to dial emergency contact (ACTION_DIAL is the safer path, but
    //    we still ask so the platform intent can complete cleanly)
    //  - SMS to send the automatic location message
    //  - Notifications (Android 13+) for the foreground service
    // On web, none of these permissions are meaningful, but we still want
    // the home screen to render so the UI can be previewed in Chrome. Treat
    // web as "permissions are whatever they are" and proceed.
    if (kIsWeb) {
      setState(() {
        _permissionsGranted = true;
        _checking = false;
      });
      return;
    }

    final results = await [
      Permission.locationWhenInUse,
      Permission.phone,
      Permission.sms,
      Permission.notification,
    ].request();

    // Background location is requested separately; on Android 11+ the user has
    // to go to Settings to grant "Allow all the time". We don't block on it.
    await Permission.locationAlways.request();

    final locationOk = (results[Permission.locationWhenInUse]?.isGranted ?? false) ||
        (results[Permission.locationWhenInUse]?.isLimited ?? false);

    setState(() {
      _permissionsGranted = locationOk;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crash Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF3D00),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F1A),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: _checking
          ? const _SplashScreen()
          : _permissionsGranted
              ? HomeScreen(
                  initialThresholds: widget.thresholds,
                  settings: widget.settings,
                  fg: widget.fg,
                )
              : const _PermissionDeniedScreen(),
    );
  }
}

/// Splash shown while requesting permissions
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F0F1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.car_crash, color: Color(0xFFFF3D00), size: 72),
            SizedBox(height: 16),
            Text(
              'Crash Detector',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'TEST VERSION',
              style: TextStyle(
                color: Color(0xFFFF3D00),
                fontSize: 11,
                letterSpacing: 3,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 40),
            CircularProgressIndicator(
              color: Color(0xFFFF3D00),
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Requesting permissions...',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when location permission is denied
class _PermissionDeniedScreen extends StatelessWidget {
  const _PermissionDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_off, color: Colors.redAccent, size: 72),
              const SizedBox(height: 20),
              const Text(
                'Permissions Required',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Crash detection needs:\n'
                '• Location — to track your speed\n'
                '• Phone — to dial your emergency contact\n'
                '• SMS — to send automatic location alerts\n'
                '• Notifications — for the background service',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open App Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3D00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
