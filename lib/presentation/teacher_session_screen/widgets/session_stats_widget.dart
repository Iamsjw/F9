import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/attendance_model.dart';
import '../../../models/session_model.dart';
import '../../../theme/app_theme.dart';

class SessionStatsWidget extends StatelessWidget {
  final List<AttendanceModel> attendance;
  final SessionModel session;
  final int totalClassStudents;

  const SessionStatsWidget({
    super.key,
    required this.attendance,
    required this.session,
    required this.totalClassStudents,
  });

  int get _presentCount => attendance.where((a) => a.isPresent).length;
  int get _revokedCount => attendance.where((a) => a.isRevoked).length;
  int get _absentCount {
    final presentOrRevoked = _presentCount + _revokedCount;
    final diff = totalClassStudents - presentOrRevoked;
    return diff > 0 ? diff : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.glassMorphism(
        borderRadius: BorderRadius.circular(16),
        opacity: 0.05,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface.withAlpha(13),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.shadowLight.withAlpha(25),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _StatTile(
                  value: _presentCount.toString(),
                  label: 'Present',
                  color: AppTheme.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
                _Divider(),
                _StatTile(
                  value: _absentCount.toString(),
                  label: 'Absent',
                  color: AppTheme.error,
                  icon: Icons.cancel_outlined,
                ),
                _Divider(),
                _StatTile(
                  value: totalClassStudents.toString(),
                  label: 'Total Students',
                  color: AppTheme.primary,
                  icon: Icons.people_outline_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatTile({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: AppTheme.shadowLight.withAlpha(25),
    );
  }
}
