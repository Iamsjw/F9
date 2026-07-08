import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/app_export.dart';
import '../../../services/csv_export_service.dart';
import '../../../widgets/glass_shimmer_widget.dart';

class TeacherReportsTab extends StatefulWidget {
  final VoidCallback? onBack;

  const TeacherReportsTab({super.key, this.onBack});

  @override
  State<TeacherReportsTab> createState() => _TeacherReportsTabState();
}

class _TeacherReportsTabState extends State<TeacherReportsTab> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _selectedSession;
  List<Map<String, dynamic>> _sessionAttendance = [];
  bool _isLoading = true;
  bool _isLoadingDetail = false;
  DateTime? _startDate;
  DateTime? _endDate;

  int _activeTab = 0; // 0: History, 1: Class Logs, 2: Grid Reports
  List<ClassModel> _classes = [];
  List<SubjectModel> _subjects = [];
  List<UserModel> _students = [];
  List<AssignmentModel> _assignments = [];
  String? _selectedClassId;
  String? _selectedSubjectId;
  String? _selectedStudentId;
  DateTime? _reportStartDate;
  DateTime? _reportEndDate;
  Map<String, dynamic>? _reportData;
  bool _isReportLoading = false;

  // Grid Report variables
  String? _gridSubjectId;
  List<String> _gridClassIds = [];
  String _gridRangeType = 'Weekly';
  DateTime? _gridStartDate;
  DateTime? _gridEndDate;
  bool _isGridReportLoading = false;
  List<SessionModel> _gridSessions = [];
  List<UserModel> _gridStudents = [];
  List<AttendanceModel> _gridAttendance = [];
  bool _hasGeneratedGrid = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions({bool keepSelection = false}) async {
    setState(() {
      _isLoading = true;
      if (!keepSelection) {
        _selectedSession = null;
        _sessionAttendance = [];
      }
    });
    try {
      final user = await SupabaseService.getCurrentUserProfile();
      if (user == null) return;
      
      final results = await Future.wait([
        SupabaseService.getTeacherSessionsWithStats(user.id),
        SupabaseService.getTeacherAssignments(user.id),
        SupabaseService.getClasses(),
      ]);
      
      final sessionsData = results[0] as List<Map<String, dynamic>>;
      final assignmentsData = results[1] as List<AssignmentModel>;
      final allClasses = results[2] as List<ClassModel>;
      
      final uniqueClasses = <String, ClassModel>{};
      for (final c in allClasses) {
        uniqueClasses[c.id] = c;
      }
      for (final a in assignmentsData) {
        if (a.classId.isNotEmpty && a.className != null) {
          uniqueClasses[a.classId] = ClassModel(id: a.classId, name: a.className!);
        }
      }

      if (mounted) {
        setState(() {
          _sessions = sessionsData;
          _assignments = assignmentsData;
          _classes = uniqueClasses.values.toList();
          _isLoading = false;
          if (keepSelection && _selectedSession != null) {
            final sessionId = _selectedSession!['id'] as String;
            final updatedSession = _sessions.firstWhere(
              (s) => s['id'] == sessionId,
              orElse: () => _selectedSession!,
            );
            _selectedSession = updatedSession;
          }
        });
      }
    } catch (e) {
      debugPrint('[TeacherReports] Failed to load sessions: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onClassChanged(String? classId) {
    setState(() {
      _selectedClassId = classId;
      _selectedSubjectId = null;
      _selectedStudentId = null;
      _reportData = null;
      _students = [];
      
      if (classId != null) {
        final classAssignments = _assignments.where((a) => a.classId == classId);
        final uniqueSubjects = <String, SubjectModel>{};
        for (final a in classAssignments) {
          if (a.subjectId.isNotEmpty && a.subjectName != null) {
            uniqueSubjects[a.subjectId] = SubjectModel(id: a.subjectId, name: a.subjectName!);
          }
        }
        _subjects = uniqueSubjects.values.toList();
      } else {
        _subjects = [];
      }
    });
    if (classId != null) {
      _loadStudents();
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedClassId == null) {
      setState(() => _students = []);
      return;
    }
    try {
      final allStudents = await SupabaseService.listUsers(role: 'student');
      if (mounted) {
        setState(() {
          _students = allStudents
              .where((s) => s.classId == _selectedClassId)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('[TeacherReports] Failed to load students: $e');
    }
  }

  Future<void> _loadReport() async {
    if (_selectedClassId == null) return;
    setState(() => _isReportLoading = true);
    try {
      final allowedSubjectIds = _assignments
          .where((a) => a.classId == _selectedClassId)
          .map((a) => a.subjectId)
          .toList();

      final data = await SupabaseService.getClassAttendanceReport(
        _selectedClassId!,
        studentId: _selectedStudentId,
        subjectIds: _selectedSubjectId != null
            ? [_selectedSubjectId!]
            : allowedSubjectIds,
        startDate: _reportStartDate,
        endDate: _reportEndDate,
      );
      
      if (mounted) {
        setState(() {
          _reportData = {'records': data, 'total': data.length};
          _isReportLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isReportLoading = false);
    }
  }

  Future<void> _pickReportDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _reportStartDate != null && _reportEndDate != null
          ? DateTimeRange(start: _reportStartDate!, end: _reportEndDate!)
          : null,
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
            primary: AppTheme.primary,
            surface: AppTheme.surfaceVariant,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _reportStartDate = picked.start;
        _reportEndDate = picked.end;
      });
    }
  }

  Future<void> _loadSessionDetail(Map<String, dynamic> session) async {
    setState(() {
      _isLoadingDetail = true;
      _selectedSession = session;
    });
    try {
      final records = await SupabaseService.getSessionAttendanceForReport(
        session['id'] as String,
      );
      if (mounted) {
        setState(() {
          _sessionAttendance = records;
          _isLoadingDetail = false;
        });
      }
    } catch (e) {
      debugPrint('[TeacherReports] Failed to load detail: $e');
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  Future<void> _toggleAttendance(String studentId, bool isPresent) async {
    if (_selectedSession == null) return;
    final sessionId = _selectedSession!['id'] as String;
    final success = await SupabaseService.setAttendanceStatus(
      studentId: studentId,
      sessionId: sessionId,
      status: isPresent ? 'present' : 'absent',
    );
    if (success) {
      await _loadSessionDetail(_selectedSession!);
      await _loadSessions(keepSelection: true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update attendance status.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: AppTheme.errorSoft,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _getSessionClassName(Map<String, dynamic> session) {
    List<String> ids = [];
    final rawClassIds = session['class_ids'];
    if (rawClassIds != null) {
      if (rawClassIds is List) {
        ids = rawClassIds.map((e) => e.toString()).toList();
      } else if (rawClassIds is String) {
        try {
          final List list = jsonDecode(rawClassIds);
          ids = list.map((e) => e.toString()).toList();
        } catch (_) {}
      }
    }
    if (ids.isEmpty && session['class_id'] != null) {
      ids = [session['class_id'].toString()];
    }

    if (ids.isNotEmpty && _classes.isNotEmpty) {
      final names = _classes
          .where((c) => ids.contains(c.id))
          .map((c) => c.name)
          .toList();
      if (names.isNotEmpty) {
        return names.join(' + ');
      }
    }

    return (session['classes'] as Map?)?['name'] ?? 'Unknown';
  }

  Future<void> _downloadSessionCsv(Map<String, dynamic> session) async {
    try {
      final records = await SupabaseService.getSessionAttendanceForReport(
        session['id'] as String,
      );
      final sessionCopy = Map<String, dynamic>.from(session);
      sessionCopy['classes'] = {'name': _getSessionClassName(session)};
      if (mounted) {
        await CsvExportService.downloadCsvFromMap(
          context: context,
          sessionData: sessionCopy,
          attendanceData: records,
        );
      }
    } catch (e) {
      debugPrint('[TeacherReports] Failed to download CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to download CSV: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
            ),
            backgroundColor: AppTheme.errorSoft,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmAndDeleteSession(String sessionId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppTheme.error, size: 22),
            const SizedBox(width: 10),
            Text(
              'Delete Session',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "$title"? All attendance records for this session will be permanently removed.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await SupabaseService.deleteSession(sessionId);
      if (success && mounted) {
        if (_selectedSession != null && _selectedSession!['id'] == sessionId) {
          setState(() {
            _selectedSession = null;
            _sessionAttendance = [];
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session deleted successfully',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.surfaceVariant,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadSessions();
      }
    }
  }

  List<Map<String, dynamic>> get _filteredSessions {
    var list = _sessions;
    if (_startDate != null) {
      list = list.where((s) {
        final ts = DateTime.parse(s['start_time'] as String);
        return !ts.isBefore(_startDate!);
      }).toList();
    }
    if (_endDate != null) {
      final end = _endDate!.add(const Duration(days: 1));
      list = list.where((s) {
        final ts = DateTime.parse(s['start_time'] as String);
        return !ts.isAfter(end);
      }).toList();
    }
    return list;
  }

  String _formatDate(String? iso) {
    if (iso == null) return '--';
    final d = DateTime.parse(iso);
    return '${d.day}/${d.month}/${d.year}';
  }

  String _formatTime(String? iso) {
    if (iso == null) return '--';
    final d = DateTime.parse(iso);
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: List.generate(
            4,
            (index) => const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: GlassShimmerWidget(height: 85, borderRadius: 16),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_selectedSession != null) {
          setState(() {
            _selectedSession = null;
            _sessionAttendance = [];
          });
        } else if (_activeTab != 0) {
          setState(() {
            _activeTab = 0;
          });
        } else {
          widget.onBack?.call();
        }
      },
      child: Column(
        children: [
          _buildHeader(),
          if (_selectedSession != null) ...[
            _buildDetailView(),
          ] else ...[
            _buildTabBar(),
            if (_activeTab == 0) ...[
              _buildDateFilter(),
              const SizedBox(height: 12),
              Expanded(child: _buildSessionsList()),
            ] else if (_activeTab == 1) ...[
              _buildClassReportFilters(),
              if (_isReportLoading)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: List.generate(
                        3,
                        (index) => const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: GlassShimmerWidget(height: 70, borderRadius: 12),
                        ),
                      ),
                    ),
                  ),
                )
              else if (_reportData != null)
                Expanded(child: _buildClassReportView()),
            ] else ...[
              _buildGridReportFilters(),
              if (_isGridReportLoading)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: List.generate(
                        3,
                        (index) => const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: GlassShimmerWidget(height: 70, borderRadius: 12),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Expanded(child: _buildGridReportPreviewSection()),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final totalSessions = _sessions.length;
    var totalPresent = 0;
    var totalAttendance = 0;
    for (final s in _sessions) {
      totalPresent += (s['present_count'] as int? ?? 0);
      totalAttendance += (s['total_count'] as int? ?? 0);
    }
    final rate = totalAttendance == 0
        ? 0.0
        : totalPresent / totalAttendance * 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.shadowLight.withAlpha(15),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.shadowLight.withAlpha(25),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
            ),
          Text(
            'My Sessions',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          if (_selectedSession == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$totalSessions Sessions',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          const SizedBox(width: 8),
          if (_selectedSession == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: rate >= 75
                    ? AppTheme.successSoft
                    : rate >= 50
                    ? AppTheme.warningSoft
                    : AppTheme.errorSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${rate.toStringAsFixed(0)}% Present',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: rate >= 75
                      ? AppTheme.success
                      : rate >= 50
                      ? AppTheme.warning
                      : AppTheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _startDate != null
                        ? AppTheme.primary.withAlpha(77)
                        : AppTheme.shadowLight.withAlpha(25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.date_range,
                      size: 16,
                      color: _startDate != null
                          ? AppTheme.primary
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _startDate != null && _endDate != null
                            ? '${_formatDate(_startDate!.toIso8601String())} - ${_formatDate(_endDate!.toIso8601String())}'
                            : 'Date Range (Optional)',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: _startDate != null
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_startDate != null)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                        },
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: _loadSessions,
            child: Text(
              'Refresh',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
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
            primary: AppTheme.primary,
            surface: AppTheme.surfaceVariant,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Widget _buildSessionsList() {
    final filtered = _filteredSessions;
    if (filtered.isEmpty) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.history_rounded,
          title: 'No Sessions Found',
          description: _startDate != null
              ? 'Try adjusting the date range filter.'
              : 'Start your first session to see reports here.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final session = filtered[index];
        final present = session['present_count'] as int? ?? 0;
        final total = session['total_count'] as int? ?? 0;
        final rate = total == 0 ? 0.0 : present / total * 100;
        final isActive = session['is_active'] as bool? ?? false;
        final className = _getSessionClassName(session);
        final subjectName = (session['subjects'] as Map?)?['name'] ?? 'Unknown';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? AppTheme.success.withAlpha(77)
                  : AppTheme.shadowLight.withAlpha(25),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _loadSessionDetail(session),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppTheme.successSoft
                                : AppTheme.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isActive
                                ? Icons.sensors_rounded
                                : Icons.check_circle_rounded,
                            color: isActive
                                ? AppTheme.success
                                : AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$subjectName - $className',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${_formatDate(session['start_time'])} at ${_formatTime(session['start_time'])}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.successSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'LIVE',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.success,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatChip(
                          label: 'Present',
                          value: '$present',
                          color: AppTheme.success,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          label: 'Total',
                          value: '$total',
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          label: 'Rate',
                          value: '${rate.toStringAsFixed(0)}%',
                          color: rate >= 75
                              ? AppTheme.success
                              : rate >= 50
                              ? AppTheme.warning
                              : AppTheme.error,
                        ),
                        const Spacer(),
                        // Delete button for this session
                        IconButton(
                          onPressed: () => _confirmAndDeleteSession(
                            session['id'] as String,
                            '$subjectName - $className',
                          ),
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: AppTheme.error,
                            size: 18,
                          ),
                          tooltip: 'Delete Session',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        // Download button for this session
                        IconButton(
                          onPressed: () =>
                              _downloadSessionCsv(session),
                          icon: Icon(
                            Icons.download_rounded,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                          tooltip: 'Download CSV',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailView() {
    if (_selectedSession == null) return const SizedBox.shrink();

    final session = _selectedSession!;
    final className = _getSessionClassName(session);
    final subjectName = (session['subjects'] as Map?)?['name'] ?? 'Unknown';
    final total = _sessionAttendance.isEmpty ? (session['total_count'] as int? ?? 0) : _sessionAttendance.length;
    final present = _sessionAttendance.isEmpty ? (session['present_count'] as int? ?? 0) : _sessionAttendance.where((r) => r['status'] == 'present').length;

    return Expanded(
      child: Column(
        children: [
          // Back button + session info
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedSession = null;
                      _sessionAttendance = [];
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: AppTheme.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$subjectName - $className',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        '${_formatDate(session['start_time'])} | Code: ${session['code']}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Delete button for this session
                IconButton(
                  onPressed: () => _confirmAndDeleteSession(
                    session['id'] as String,
                    '$subjectName - $className',
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.error,
                    size: 20,
                  ),
                  tooltip: 'Delete Session',
                ),
                // Download button for this session
                IconButton(
                  onPressed: () => _downloadSessionCsv(session),
                  icon: Icon(
                    Icons.download_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  tooltip: 'Download CSV',
                ),
              ],
            ),
          ),
          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatChip(
                  label: 'Present',
                  value: '$present',
                  color: AppTheme.success,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Total',
                  value: '$total',
                  color: AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                _StatChip(
                  label: 'Absent',
                  value: '${total - present}',
                  color: AppTheme.error,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Attendance list
          Expanded(
            child: _isLoadingDetail
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _sessionAttendance.isEmpty
                ? Center(
                    child: EmptyStateWidget(
                      icon: Icons.people_outline_rounded,
                      title: 'No Attendance Yet',
                      description:
                          'Students haven\'t marked attendance for this session.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _sessionAttendance.length,
                    itemBuilder: (context, index) {
                      final record = _sessionAttendance[index];
                      final name = record['users']?['name'] ?? 'Unknown';
                      final email = record['users']?['email'] ?? '--';
                      final isPresent = record['status'] == 'present';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.shadowLight.withAlpha(25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPresent
                                    ? AppTheme.successSoft
                                    : AppTheme.errorSoft,
                              ),
                              child: Center(
                                child: Text(
                                  (name as String).isEmpty ? '?' : name[0].toUpperCase(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isPresent
                                        ? AppTheme.success
                                        : AppTheme.error,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    email,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isPresent ? 'Present' : 'Absent',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isPresent
                                        ? AppTheme.success
                                        : AppTheme.error,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Switch.adaptive(
                                  value: isPresent,
                                  activeColor: AppTheme.success,
                                  activeTrackColor: AppTheme.successSoft,
                                  inactiveThumbColor: AppTheme.error,
                                  inactiveTrackColor: AppTheme.errorSoft,
                                  onChanged: (val) => _toggleAttendance(
                                    record['student_id'] as String,
                                    val,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _downloadReportCsv() {
    if (_reportData == null || _selectedClassId == null) return;
    final className = _classes.firstWhere((c) => c.id == _selectedClassId).name;
    final records = _reportData!['records'] as List;
    CsvExportService.downloadAdminReportCsv(
      context: context,
      className: className,
      records: records,
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0x1AFFFFFF),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _activeTab = 0;
                _selectedSession = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 0
                      ? AppTheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'History',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activeTab == 0 ? Colors.white : AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _activeTab = 1;
                _selectedSession = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 1
                      ? AppTheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Class Logs',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activeTab == 1 ? Colors.white : AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _activeTab = 2;
                _selectedSession = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _activeTab == 2
                      ? AppTheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'Grid Report',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _activeTab == 2 ? Colors.white : AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassReportFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Select Class',
                  value: _selectedClassId,
                  items: _classes
                      .map(
                        (c) => DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: _onClassChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Select Subject (Optional)',
                  value: _selectedSubjectId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Subjects'),
                    ),
                    ..._subjects.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedSubjectId = v;
                      _reportData = null;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Select Student (Optional)',
                  value: _selectedStudentId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Students'),
                    ),
                    ..._students.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(s.name),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedStudentId = v;
                      _reportData = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date Range (Optional)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _pickReportDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.shadowLight.withAlpha(25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.date_range,
                              size: 16,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _reportStartDate != null && _reportEndDate != null
                                    ? '${_formatDate(_reportStartDate!.toIso8601String())} - ${_formatDate(_reportEndDate!.toIso8601String())}'
                                    : 'Select dates...',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _reportStartDate != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_reportStartDate != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _reportStartDate = null;
                                    _reportEndDate = null;
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _selectedClassId != null ? _loadReport : null,
              child: Text(
                'Generate Report',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassReportView() {
    final records = _reportData?['records'] as List? ?? [];
    final total = records.length;

    if (total == 0) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.bar_chart_outlined,
          title: 'No Records Found',
          description: 'Try adjusting filters or selecting a different class.',
        ),
      );
    }

    final bySubject = <String, Map<String, dynamic>>{};
    for (final r in records) {
      final subjectName = r['sessions']?['subjects']?['name'] ?? 'Unknown';
      if (!bySubject.containsKey(subjectName)) {
        bySubject[subjectName] = {'present': 0, 'total': 0};
      }
      bySubject[subjectName]!['total']++;
      if (r['status'] == 'present') {
        bySubject[subjectName]!['present']++;
      }
    }

    final presentCount = records.where((r) => r['status'] == 'present').length;
    final absentCount = records.where((r) => r['status'] == 'absent').length;
    final revokedCount = records.where((r) => r['status'] == 'revoked').length;
    final overallRate = total == 0 ? 0.0 : presentCount / total * 100;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.shadowLight.withAlpha(35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Total: $total',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _downloadReportCsv,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'CSV',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: overallRate >= 75
                        ? AppTheme.successSoft
                        : overallRate >= 50
                        ? AppTheme.warningSoft
                        : AppTheme.errorSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${overallRate.toStringAsFixed(0)}% Present',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: overallRate >= 75
                          ? AppTheme.success
                          : overallRate >= 50
                          ? AppTheme.warning
                          : AppTheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (total > 0)
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(
                              value: presentCount.toDouble(),
                              title: 'Present',
                              color: AppTheme.success,
                              radius: 60,
                              titleStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: absentCount.toDouble(),
                              title: 'Absent',
                              color: AppTheme.error,
                              radius: 60,
                              titleStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            PieChartSectionData(
                              value: revokedCount.toDouble(),
                              title: 'Revoked',
                              color: AppTheme.warning,
                              radius: 60,
                              titleStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                          centerSpaceRadius: 30,
                          sectionsSpace: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LegendItem(
                            color: AppTheme.success,
                            label: 'Present',
                            value: '$presentCount',
                          ),
                          const SizedBox(height: 8),
                          _LegendItem(
                            color: AppTheme.error,
                            label: 'Absent',
                            value: '$absentCount',
                          ),
                          const SizedBox(height: 8),
                          _LegendItem(
                            color: AppTheme.warning,
                            label: 'Revoked',
                            value: '$revokedCount',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (bySubject.isNotEmpty)
            SizedBox(
              height: 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: bySubject.values
                            .map((e) => (e['total'] as int).toDouble())
                            .reduce((a, b) => a > b ? a : b) *
                        1.2,
                    barGroups: bySubject.entries.toList().asMap().entries.map((entry) {
                      final index = entry.key;
                      final data = entry.value.value;
                      final totalVal = data['total'] as int;
                      final presentVal = data['present'] as int;
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: totalVal.toDouble(),
                            color: AppTheme.primary.withAlpha(77),
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          BarChartRodData(
                            toY: presentVal.toDouble(),
                            color: AppTheme.success,
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, _) => Text(
                            value.toInt().toString(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, _) {
                            final keys = bySubject.keys.toList();
                            if (value.toInt() >= keys.length) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Transform.rotate(
                                angle: -0.4,
                                child: Text(
                                  keys[value.toInt()],
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 9,
                                    color: AppTheme.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: AppTheme.shadowLight.withAlpha(25),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Breakdown by Subject',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: bySubject.entries.map((entry) {
                final subject = entry.key;
                final data = entry.value;
                final rate = data['total'] == 0
                    ? 0.0
                    : data['present'] / data['total'] * 100;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.shadowLight.withAlpha(25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Present: ${data['present']} / ${data['total']}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: rate >= 75
                              ? AppTheme.successSoft
                              : rate >= 50
                              ? AppTheme.warningSoft
                              : AppTheme.errorSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${rate.toStringAsFixed(0)}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: rate >= 75
                                ? AppTheme.success
                                : rate >= 50
                                ? AppTheme.warning
                                : AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String?>> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF130E26).withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0x33FFFFFF),
              width: 1.0,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              hint: Text(
                'Select $label',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textDisabled,
                ),
              ),
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridReportFilters() {
    final uniqueSubjects = <String, SubjectModel>{};
    for (final a in _assignments) {
      if (a.subjectId.isNotEmpty && a.subjectName != null) {
        uniqueSubjects[a.subjectId] = SubjectModel(id: a.subjectId, name: a.subjectName!);
      }
    }
    final subjectsList = uniqueSubjects.values.toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Subject',
                  value: _gridSubjectId,
                  items: subjectsList
                      .map(
                        (s) => DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _gridSubjectId = v;
                      _hasGeneratedGrid = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  label: 'Date Range Type',
                  value: _gridRangeType,
                  items: ['Daily', 'Weekly', 'Monthly', 'Quarterly', 'Custom']
                      .map(
                        (type) => DropdownMenuItem<String?>(
                          value: type,
                          child: Text(type),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _gridRangeType = v ?? 'Weekly';
                      _hasGeneratedGrid = false;
                    });
                  },
                ),
              ),
            ],
          ),
          if (_gridRangeType == 'Custom') ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom Date Range',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickGridDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.shadowLight.withAlpha(25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _gridStartDate != null && _gridEndDate != null
                                ? '${_gridStartDate!.day}/${_gridStartDate!.month}/${_gridStartDate!.year} - ${_gridEndDate!.day}/${_gridEndDate!.month}/${_gridEndDate!.year}'
                                : 'Select date range...',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: _gridStartDate != null
                                  ? AppTheme.textPrimary
                                  : AppTheme.textDisabled,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Select Classes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (_classes.isEmpty)
            Text(
              'No classes available.',
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.error,
                fontSize: 13,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _classes.map((c) {
                final isSelected = _gridClassIds.contains(c.id);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _gridClassIds.remove(c.id);
                      } else {
                        _gridClassIds.add(c.id);
                      }
                      _hasGeneratedGrid = false;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withAlpha(38)
                          : AppTheme.surface.withAlpha(13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.shadowLight.withAlpha(25),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      c.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _generateGridReportData,
              icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
              label: Text(
                'Generate Grid Report',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridReportPreviewSection() {
    if (!_hasGeneratedGrid) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 48,
              color: AppTheme.textMuted.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              'Select parameters and tap Generate',
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_gridSessions.isEmpty) {
      return Center(
        child: Text(
          'No attendance sessions found for the selected period.',
          style: GoogleFonts.plusJakartaSans(
            color: AppTheme.textMuted,
            fontSize: 14,
          ),
        ),
      );
    }

    final subjectModel = _subjects.firstWhere(
      (s) => s.id == _gridSubjectId,
      orElse: () => SubjectModel(id: '', name: 'Subject'),
    );

    // Group attendance by student ID -> session ID
    final attMap = <String, Map<String, String>>{};
    for (final a in _gridAttendance) {
      if (!attMap.containsKey(a.studentId)) {
        attMap[a.studentId] = {};
      }
      attMap[a.studentId]![a.sessionId] = a.status;
    }

    return Column(
      children: [
        // Summary & Export Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primary.withAlpha(30),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subjectModel.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_gridSessions.length} sessions | ${_gridStudents.length} students',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _downloadGridReportCsv,
                  icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                  label: Text(
                    'Export CSV',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Horizontal/vertical scrollable Table preview
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface.withAlpha(20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.shadowLight.withAlpha(25),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  physics: const BouncingScrollPhysics(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Table(
                      defaultColumnWidth: const FixedColumnWidth(65),
                      columnWidths: {
                        0: const FixedColumnWidth(80), // Roll No
                        1: const FixedColumnWidth(150), // Name
                        _gridSessions.length + 2: const FixedColumnWidth(110), // Attendance %
                      },
                      border: TableBorder.all(
                        color: AppTheme.textMuted.withAlpha(30),
                        width: 1,
                      ),
                      children: [
                        // Row 1: Headers (Roll No, Name, Dates, Summary)
                        TableRow(
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(26),
                          ),
                          children: [
                            _buildTableCell('Roll No', isHeader: true),
                            _buildTableCell('Name', isHeader: true),
                            ..._gridSessions.map((s) {
                              final day = s.startTime.toLocal().day;
                              final month = s.startTime.toLocal().month;
                              return _buildTableCell('$day/$month', isHeader: true);
                            }),
                            _buildTableCell('Attendance %', isHeader: true),
                          ],
                        ),
                        // Row 2: Lecture Time Slots
                        TableRow(
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(12),
                          ),
                          children: [
                            _buildTableCell('', isHeader: true),
                            _buildTableCell('', isHeader: true),
                            ..._gridSessions.map((s) {
                              final slot = s.lectureTime ?? 'Slot';
                              return _buildTableCell(slot, isHeader: true, isTimeSlot: true);
                            }),
                            _buildTableCell('', isHeader: true),
                          ],
                        ),
                        // Student Rows
                        ..._gridStudents.map((student) {
                          int presentCount = 0;
                          final studentAtt = attMap[student.id] ?? {};
                          
                          final List<Widget> cells = [
                            _buildTableCell(student.rollNo ?? '-'),
                            _buildTableCell(student.name, alignLeft: true),
                          ];

                          for (final s in _gridSessions) {
                            final isPresent = studentAtt[s.id] == 'present';
                            if (isPresent) {
                              presentCount++;
                              cells.add(_buildTableCell('P', color: AppTheme.success));
                            } else {
                              cells.add(_buildTableCell('-'));
                            }
                          }

                          final percent = _gridSessions.isEmpty 
                              ? 0.0 
                              : (presentCount / _gridSessions.length) * 100;
                          cells.add(_buildTableCell('$presentCount/${_gridSessions.length} (${percent.toStringAsFixed(0)}%)'));

                          return TableRow(
                            children: cells,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isTimeSlot = false,
    bool alignLeft = false,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: isTimeSlot ? 8 : (isHeader ? 11 : 12),
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isHeader ? AppTheme.textPrimary : AppTheme.textSecondary),
        ),
      ),
    );
  }

  Future<void> _generateGridReportData() async {
    if (_gridSubjectId == null || _gridClassIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select a subject and at least one class.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13),
          ),
          backgroundColor: AppTheme.errorSoft,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isGridReportLoading = true;
      _hasGeneratedGrid = false;
    });

    try {
      final now = DateTime.now();
      DateTime start;
      DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);

      switch (_gridRangeType) {
        case 'Daily':
          start = DateTime(now.year, now.month, now.day);
          break;
        case 'Weekly':
          start = now.subtract(const Duration(days: 7));
          break;
        case 'Monthly':
          start = now.subtract(const Duration(days: 30));
          break;
        case 'Quarterly':
          start = now.subtract(const Duration(days: 90));
          break;
        case 'Custom':
          if (_gridStartDate == null || _gridEndDate == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Select a custom date range first.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                ),
                backgroundColor: AppTheme.errorSoft,
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() => _isGridReportLoading = false);
            return;
          }
          start = _gridStartDate!;
          end = DateTime(_gridEndDate!.year, _gridEndDate!.month, _gridEndDate!.day, 23, 59, 59);
          break;
        default:
          start = now.subtract(const Duration(days: 7));
      }

      final sessions = await SupabaseService.getSessionsForSubjectReport(
        subjectId: _gridSubjectId!,
        classIds: _gridClassIds,
        startDate: start,
        endDate: end,
      );

      if (sessions.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No sessions found for this configuration and date range.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: AppTheme.warning,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() {
          _gridSessions = [];
          _gridStudents = [];
          _gridAttendance = [];
          _isGridReportLoading = false;
          _hasGeneratedGrid = true;
        });
        return;
      }

      final students = await SupabaseService.getStudentsByClasses(_gridClassIds);
      final sessionIds = sessions.map((s) => s.id).toList();
      final attendance = await SupabaseService.getAttendanceForSessions(sessionIds);

      if (mounted) {
        setState(() {
          _gridSessions = sessions;
          _gridStudents = students;
          _gridAttendance = attendance;
          _isGridReportLoading = false;
          _hasGeneratedGrid = true;
        });
      }
    } catch (e) {
      debugPrint('[TeacherReports] Failed to generate grid report: $e');
      if (mounted) {
        setState(() => _isGridReportLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error generating report: $e',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.errorSoft,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickGridDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: _gridStartDate != null && _gridEndDate != null
          ? DateTimeRange(start: _gridStartDate!, end: _gridEndDate!)
          : null,
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
            primary: AppTheme.primary,
            surface: AppTheme.surfaceVariant,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _gridStartDate = picked.start;
        _gridEndDate = picked.end;
        _hasGeneratedGrid = false;
      });
    }
  }

  void _downloadGridReportCsv() {
    if (!_hasGeneratedGrid || _gridSessions.isEmpty) return;
    
    final subjectModel = _subjects.firstWhere(
      (s) => s.id == _gridSubjectId,
      orElse: () => SubjectModel(id: '', name: 'Subject'),
    );
    
    final classNames = _classes
        .where((c) => _gridClassIds.contains(c.id))
        .map((c) => c.name)
        .join('_');

    CsvExportService.downloadGridCsv(
      context: context,
      subjectName: subjectModel.name,
      className: classNames,
      students: _gridStudents,
      sessions: _gridSessions,
      attendance: _gridAttendance,
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(77), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
