import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const CrashDetectorApp());
}

class CrashDetectorApp extends StatefulWidget {
  const CrashDetectorApp({super.key});

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
    final locationStatus = await Permission.locationWhenInUse.request();
    await Permission.locationAlways.request();

    setState(() {
      _permissionsGranted = locationStatus.isGranted;
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
              ? const HomeScreen()
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
                'Location Permission Required',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Crash detection needs GPS access to monitor your speed and detect sudden stops.',
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
