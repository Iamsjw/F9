import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassShimmerWidget extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const GlassShimmerWidget({
    super.key,
    this.width = double.infinity,
    this.height = 80,
    this.borderRadius = 16,
  });

  @override
  State<GlassShimmerWidget> createState() => _GlassShimmerWidgetState();
}

class _GlassShimmerWidgetState extends State<GlassShimmerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _shimmerAnim = Tween<double>(begin: 0.04, end: 0.12).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: _shimmerAnim.value),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: AppTheme.shadowLight.withValues(alpha: _shimmerAnim.value * 1.5),
              width: 1,
            ),
          ),
        );
      },
    );
  }
}
