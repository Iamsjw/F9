import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_export.dart';
import '../../services/supabase_service.dart';

class CompletedClassesTimetableScreen extends StatefulWidget {
  const CompletedClassesTimetableScreen({super.key});

  @override
  State<CompletedClassesTimetableScreen> createState() =>
      _CompletedClassesTimetableScreenState();
}

class _CompletedClassesTimetableScreenState
    extends State<CompletedClassesTimetableScreen> {
  UserModel? _currentUser;
  DateTime _selectedDate = DateTime.now();
  List<SessionModel> _completedSessions = [];
  bool _isLoadingUser = true;
  bool _isLoadingData = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserAndData();
  }

  Future<void> _loadUserAndData() async {
    setState(() {
      _isLoadingUser = true;
      _errorMessage = null;
    });

    try {
      _currentUser = await SupabaseService.getCurrentUserProfile();
      if (_currentUser == null) {
        throw Exception('User profile not found. Please log in again.');
      }
      await _fetchCompletedSessions();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  Future<void> _fetchCompletedSessions() async {
    if (_currentUser == null) return;
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    try {
      List<SessionModel> sessions = [];
      if (_currentUser!.isTeacher) {
        sessions = await SupabaseService.getCompletedSessionsForTeacher(
          _currentUser!.id,
          _selectedDate,
        );
      } else {
        final classId = _currentUser!.classId;
        if (classId != null && classId.isNotEmpty) {
          sessions = await SupabaseService.getCompletedSessionsForStudent(
            classId,
            _selectedDate,
          );
        }
      }
      if (mounted) {
        setState(() {
          _completedSessions = sessions;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load timetable: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
      }
    }
  }

  void _adjustDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _fetchCompletedSessions();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          dialogTheme: const DialogThemeData(
            backgroundColor: AppTheme.surfaceVariant,
            surfaceTintColor: Colors.transparent,
          ),
          datePickerTheme: const DatePickerThemeData(
            backgroundColor: AppTheme.surfaceVariant,
            surfaceTintColor: Colors.transparent,
            headerBackgroundColor: AppTheme.surfaceVariant,
          ),
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppTheme.primaryCyan,
            surface: AppTheme.surfaceVariant,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchCompletedSessions();
    }
  }

  String _formatFullDate(DateTime date) {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    if (date.year == today.year &&
        date.month == today.month &&
        date.day == today.day) {
      return 'Today';
    } else if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }

    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatSessionTime(DateTime start, DateTime? end, String? lectureTime) {
    if (lectureTime != null && lectureTime.isNotEmpty && lectureTime != 'Custom') {
      return lectureTime;
    }
    
    // Fallback: format start & end time
    final startMin = start.minute.toString().padLeft(2, '0');
    final startHour = start.hour > 12 ? start.hour - 12 : (start.hour == 0 ? 12 : start.hour);
    final startPeriod = start.hour >= 12 ? 'PM' : 'AM';

    if (end == null) {
      return '$startHour:$startMin $startPeriod';
    }

    final endMin = end.minute.toString().padLeft(2, '0');
    final endHour = end.hour > 12 ? end.hour - 12 : (end.hour == 0 ? 12 : end.hour);
    final endPeriod = end.hour >= 12 ? 'PM' : 'AM';

    return '$startHour:$startMin $startPeriod - $endHour:$endMin $endPeriod';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: _isLoadingUser
                ? _buildLoadingState()
                : _errorMessage != null
                    ? _buildErrorState()
                    : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(color: AppTheme.background),
        ),
        Positioned(
          top: -150,
          right: -150,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primaryCyan.withAlpha(38),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -150,
          left: -150,
          child: Container(
            width: 450,
            height: 450,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primaryBlue.withAlpha(25),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppTheme.primaryCyan,
        strokeWidth: 2.5,
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadUserAndData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryCyan,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        _buildDatePickerRow(),
        Expanded(
          child: _isLoadingData
              ? _buildDataLoadingState()
              : _completedSessions.isEmpty
                  ? _buildEmptyState()
                  : _buildTimetableTable(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.shadowLight.withAlpha(25),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.surface.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.shadowLight.withAlpha(15),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.arrow_back_rounded,
                color: AppTheme.textPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Timetable',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Completed Lectures History',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryCyan.withAlpha(25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primaryCyan.withAlpha(50),
                width: 1,
              ),
            ),
            child: Text(
              _currentUser!.isTeacher ? 'Teacher View' : 'Student View',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryCyan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withAlpha(5),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.shadowLight.withAlpha(15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous day button
          IconButton(
            onPressed: () => _adjustDate(-1),
            icon: Icon(
              Icons.chevron_left_rounded,
              color: AppTheme.textPrimary,
              size: 24,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface.withAlpha(15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Center Date Display Card
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.shadowLight.withAlpha(25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      color: AppTheme.primaryCyan,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _formatFullDate(_selectedDate),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Next day button
          IconButton(
            onPressed: () => _adjustDate(1),
            icon: Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textPrimary,
              size: 24,
            ),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface.withAlpha(15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppTheme.primaryCyan,
        strokeWidth: 2.0,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surface.withAlpha(15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.shadowLight.withAlpha(25),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.event_busy_rounded,
                color: AppTheme.textMuted,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Completed Lectures',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No ended attendance sessions found for this day.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableTable() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withAlpha(13),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.shadowLight.withAlpha(25),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              // Table Header row
              Container(
                color: AppTheme.surface.withAlpha(25),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'TIME',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 7,
                      child: Text(
                        'LECTURE DETAILS',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Table Body rows
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _completedSessions.length,
                separatorBuilder: (context, index) => Divider(
                  color: AppTheme.shadowLight.withAlpha(15),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final session = _completedSessions[index];
                  final isCombined = session.classIds != null && session.classIds!.length > 1;

                  // Render single row
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Time Column
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatSessionTime(
                                  session.startTime,
                                  session.endTime,
                                  session.lectureTime,
                                ),
                                style: GoogleFonts.shareTechMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primaryCyan,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ended',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right: Lecture details Column
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.subjectName ?? 'Unknown Lecture',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.class_rounded,
                                    size: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      session.className ?? 'Unknown Class',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (isCombined) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryCyan.withAlpha(20),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: AppTheme.primaryCyan.withAlpha(50),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    'COMBINED CLASS',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryCyan,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                              if (!_currentUser!.isTeacher && session.teacherName != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.person_rounded,
                                      size: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'By ${session.teacherName}',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
