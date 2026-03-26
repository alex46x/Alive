import 'dart:async';
import 'package:flutter/material.dart';
import '../services/alert_service.dart';
import '../models/sensor_data.dart';

class CrashAlertScreen extends StatefulWidget {
  final CrashEvent event;
  final AlertService alertService;
  final VoidCallback onDismissed;

  const CrashAlertScreen({
    super.key,
    required this.event,
    required this.alertService,
    required this.onDismissed,
  });

  @override
  State<CrashAlertScreen> createState() => _CrashAlertScreenState();
}

class _CrashAlertScreenState extends State<CrashAlertScreen>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 30;
  int _remaining = _totalSeconds;
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start alarm
    widget.alertService.startAlert();

    // Countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _countdownTimer?.cancel();
    widget.alertService.stopAlert();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF8B0000), Color(0xFFCC0000), Color(0xFFFF1A1A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // Pulsing warning icon
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    size: 70,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // Title
              const Text(
                '⚠️ POSSIBLE ACCIDENT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'DETECTED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),

              const SizedBox(height: 24),

              // Event details
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _detailRow('🕐 Time', widget.event.formattedTime),
                    _detailRow('🚗 Speed Before',
                        '${widget.event.speedBefore.toStringAsFixed(1)} km/h'),
                    _detailRow('⛔ Speed After',
                        '${widget.event.speedAfter.toStringAsFixed(1)} km/h'),
                    _detailRow('💥 Peak G-Force',
                        '${widget.event.peakGForce.toStringAsFixed(2)} g'),
                    _detailRow('🌀 Angular Vel.',
                        '${widget.event.peakAngularVelocity.toStringAsFixed(2)} rad/s'),
                  ],
                ),
              ),

              const Spacer(),

              // Countdown
              Text(
                'Auto-dismissing in $_remaining seconds',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                ),
              ),

              const SizedBox(height: 12),

              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _remaining / _totalSeconds,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Cancel button
              GestureDetector(
                onTap: _dismiss,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(60),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '✋  I\'M OKAY — CANCEL ALERT',
                      style: TextStyle(
                        color: Color(0xFFCC0000),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
