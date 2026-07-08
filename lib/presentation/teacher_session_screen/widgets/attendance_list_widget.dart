import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/attendance_model.dart';
import '../../../models/user_model.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../theme/app_theme.dart';

class AttendanceListWidget extends StatelessWidget {
  final List<UserModel> classStudents;
  final List<AttendanceModel> attendance;
  final void Function(String studentId, bool isPresent) onToggleAttendance;
  final void Function(AttendanceModel) onRevokeAttendance;
  final bool isSessionActive;

  const AttendanceListWidget({
    super.key,
    required this.classStudents,
    required this.attendance,
    required this.onToggleAttendance,
    required this.onRevokeAttendance,
    required this.isSessionActive,
  });

  @override
  Widget build(BuildContext context) {
    final attendanceMap = <String, AttendanceModel>{
      for (final a in attendance) a.studentId: a
    };

    final sortedStudents = List<UserModel>.from(classStudents)
      ..sort((a, b) {
        final attA = attendanceMap[a.id];
        final attB = attendanceMap[b.id];
        final isPresentA = attA?.isPresent ?? false;
        final isPresentB = attB?.isPresent ?? false;

        // 1. Present students float to the top
        if (isPresentA && !isPresentB) return -1;
        if (!isPresentA && isPresentB) return 1;

        // 2. If both are present, newest check-in comes first
        if (isPresentA && isPresentB) {
          final timeA = attA?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          final timeB = attB?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
          return timeB.compareTo(timeA);
        }

        // 3. Both absent: sort by roll number or name
        if (a.rollNo != null && b.rollNo != null) {
          return a.rollNo!.toLowerCase().compareTo(b.rollNo!.toLowerCase());
        } else if (a.rollNo != null) {
          return -1;
        } else if (b.rollNo != null) {
          return 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    final presentCount = attendance.where((a) => a.isPresent).length;

    return Container(
      decoration: AppTheme.glassMorphism(
        borderRadius: BorderRadius.circular(20),
        opacity: 0.05,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface.withAlpha(13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.shadowLight.withAlpha(25),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Class Attendance',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) {
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.2),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          key: ValueKey(presentCount),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$presentCount / ${classStudents.length} present',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppTheme.shadowLight.withAlpha(13),
                ),
                if (classStudents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: EmptyStateWidget(
                      icon: Icons.how_to_reg_outlined,
                      title: 'No Students Enrolled',
                      description:
                          'There are no students enrolled in this class yet.',
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: sortedStudents.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 1,
                      color: AppTheme.shadowLight.withAlpha(10),
                      indent: 20,
                      endIndent: 20,
                    ),
                    itemBuilder: (context, index) {
                      final student = sortedStudents[index];
                      // O(1) constant-time record lookup for high-density 100-200 student lists
                      final record = attendanceMap[student.id];

                      return RepaintBoundary(
                        key: ValueKey(student.id),
                        child: _AttendanceRow(
                          student: student,
                          record: record,
                          index: index,
                          onToggle: (isPresent) =>
                              onToggleAttendance(student.id, isPresent),
                          isSessionActive: isSessionActive,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttendanceRow extends StatefulWidget {
  final UserModel student;
  final AttendanceModel? record;
  final int index;
  final void Function(bool) onToggle;
  final bool isSessionActive;

  const _AttendanceRow({
    super.key,
    required this.student,
    required this.record,
    required this.index,
    required this.onToggle,
    required this.isSessionActive,
  });

  @override
  State<_AttendanceRow> createState() => _AttendanceRowState();
}

class _AttendanceRowState extends State<_AttendanceRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late bool _isPresent;

  @override
  void initState() {
    super.initState();
    _isPresent = widget.record?.isPresent ?? false;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: widget.index * 40), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(covariant _AttendanceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _isPresent = widget.record?.isPresent ?? false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().toUtc().difference(time.toUtc());
    final seconds = diff.inSeconds;
    if (seconds <= 5) return 'Just now';
    if (seconds < 60) return '${seconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final isPresent = _isPresent;
    final isRevoked = widget.record?.isRevoked ?? false;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPresent
                      ? AppTheme.successSoft
                      : isRevoked
                          ? AppTheme.errorSoft
                          : AppTheme.shadowLight.withAlpha(15),
                  border: Border.all(
                    color: isPresent
                        ? AppTheme.success.withAlpha(77)
                        : isRevoked
                            ? AppTheme.error.withAlpha(77)
                            : AppTheme.shadowLight.withAlpha(25),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    _initials(widget.student.name),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isPresent
                          ? AppTheme.success
                          : isRevoked
                              ? AppTheme.error
                              : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Student info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          widget.student.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (widget.student.rollNo != null && widget.student.rollNo!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.student.rollNo!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          ),
                        if (widget.student.className != null && widget.student.className!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.student.className!,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPresent
                          ? 'Checked in ${_timeAgo(widget.record!.timestamp)}'
                          : isRevoked
                              ? 'Revoked'
                              : 'Absent',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: isPresent
                            ? AppTheme.success
                            : isRevoked
                                ? AppTheme.error
                                : AppTheme.textMuted,
                        fontWeight: isPresent || isRevoked
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Present/Absent Toggle Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isPresent ? 'Present' : 'Absent',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPresent ? AppTheme.success : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch.adaptive(
                    value: isPresent,
                    activeColor: AppTheme.success,
                    activeTrackColor: AppTheme.successSoft,
                    inactiveThumbColor: AppTheme.textMuted,
                    inactiveTrackColor: AppTheme.shadowLight.withAlpha(25),
                    onChanged: widget.isSessionActive
                        ? (val) {
                            HapticFeedback.lightImpact();
                            setState(() => _isPresent = val);
                            widget.onToggle(val);
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
