import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class BleRadarWidget extends StatefulWidget {
  final bool isScanning;
  final bool showRadarAnimation;
  final ValueChanged<bool>? onToggleRadar;
  final String label;

  const BleRadarWidget({
    super.key,
    required this.isScanning,
    this.showRadarAnimation = true,
    this.onToggleRadar,
    this.label = 'BLE Scan Active',
  });

  @override
  State<BleRadarWidget> createState() => _BleRadarWidgetState();
}

class _BleRadarWidgetState extends State<BleRadarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    if (widget.isScanning && widget.showRadarAnimation) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant BleRadarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && widget.showRadarAnimation) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showRadarAnimation) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
            if (widget.onToggleRadar != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => widget.onToggleRadar!(true),
                child: Icon(
                  Icons.radar_rounded,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 90,
          height: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Concentric Pulsing Radar Rings
              if (widget.isScanning)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final progress = _controller.value;
                    return CustomPaint(
                      size: const Size(90, 90),
                      painter: _RadarPainter(
                        progress: progress,
                        color: AppTheme.primaryCyan,
                      ),
                    );
                  },
                ),
              // Center Pulse Core Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryCyan.withValues(alpha: 0.2),
                  border: Border.all(
                    color: AppTheme.primaryCyan,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryCyan.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bluetooth_searching_rounded,
                  color: AppTheme.primaryCyan,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryCyan,
              ),
            ),
            if (widget.onToggleRadar != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => widget.onToggleRadar!(false),
                child: Tooltip(
                  message: 'Disable Radar Animation',
                  child: Icon(
                    Icons.visibility_off_outlined,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + (i * 0.333)) % 1.0;
      final radius = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0) * 0.5;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
