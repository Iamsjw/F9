import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_export.dart';
import '../../routes/app_routes.dart';
import '../../services/ble_service.dart';
import '../../services/csv_export_service.dart';
import './widgets/attendance_list_widget.dart';
import './widgets/ble_broadcast_indicator_widget.dart';
import './widgets/session_code_display_widget.dart';
import './widgets/session_config_widget.dart';
import './widgets/session_stats_widget.dart';
import './widgets/teacher_reports_tab.dart';
import './widgets/session_report_screen.dart';
import '../../widgets/ble_radar_widget.dart';
import '../../widgets/system_setup_disclaimer.dart';

class TeacherSessionScreen extends StatefulWidget {
  const TeacherSessionScreen({super.key});

  @override
  State<TeacherSessionScreen> createState() => _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends State<TeacherSessionScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // TODO: Replace with Riverpod SessionNotifier for production

  UserModel? _currentUser;
  SessionModel? _activeSession;
  List<AttendanceModel> _attendance = [];
  List<UserModel> _classStudents = [];
  List<AssignmentModel> _assignments = [];
  List<ClassModel> _classes = [];
  List<SubjectModel> _subjects = [];

  // Session config
  List<String> _selectedClassIds = [];
  String? _selectedSubjectId;
  String? _lectureTimeSlot;
  String? _customLectureTimeSlot = '';
  int _durationSeconds = 60;
  String _securityLevel = 'LOW';
  int _rssiThreshold = -95;

  bool _isLoading = true;
  bool _isStartingSession = false;
  bool _isEndingSession = false;
  String? _errorMessage;
  bool _permissionsGranted = false;
  bool _bluetoothOn = false;
  bool _locationServicesEnabled = true;

  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  RealtimeChannel? _realtimeChannel;
  Timer? _attendancePollTimer;  // fallback poll every 10s

  // Re-take session (code-only mode)
  bool _isCodeOnlyMode = false;
  Timer? _codeOnlyTimer;
  int _codeOnlyRemainingSeconds = 0;
  String? _previousSecurityLevel;

  // Reports view toggle
  bool _showReports = false;
  bool _showRadarAnimation = false;

  late AnimationController _pulseController;
  late AnimationController _entranceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _entranceFade;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _loadInitialData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSystemStatus();
    }
  }

  Future<void> _refreshSystemStatus() async {
    final permissions = await BleService.hasPermissions();
    final btOn = await BleService.isBluetoothOn();
    final gpsOn = await BleService.isLocationEnabled();
    if (mounted) {
      setState(() {
        _permissionsGranted = permissions;
        _bluetoothOn = btOn;
        _locationServicesEnabled = gpsOn;
      });
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _currentUser = await SupabaseService.getCurrentUserProfile();
      if (_currentUser == null || _currentUser!.role != 'teacher') {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.signUpLoginScreen,
            (_) => false,
          );
        }
        return;
      }

      final results = await Future.wait([
        SupabaseService.getTeacherAssignments(_currentUser!.id),
        SupabaseService.getClasses(),
        SupabaseService.getSubjects(),
        SupabaseService.getActiveSessionForTeacher(_currentUser!.id),
        BleService.hasPermissions(),
        BleService.isBluetoothOn(),
        BleService.isLocationEnabled(),
      ]);

      _assignments = results[0] as List<AssignmentModel>;
      _classes = results[1] as List<ClassModel>;
      _subjects = results[2] as List<SubjectModel>;
      final existingSession = results[3] as SessionModel?;
      _permissionsGranted = results[4] as bool;
      _bluetoothOn = results[5] as bool;
      _locationServicesEnabled = results[6] as bool;

      if (existingSession != null) {
        _activeSession = existingSession;
        _selectedClassIds = existingSession.classIds ?? [existingSession.classId];
        _selectedSubjectId = existingSession.subjectId;
        _securityLevel = existingSession.securityLevel;
        _rssiThreshold = existingSession.rssiThreshold;
        
        if (existingSession.endTime == null) {
          await SupabaseService.endSession(existingSession.id);
          _activeSession = null;
        } else {
          _durationSeconds = existingSession.endTime!
              .toUtc()
              .difference(existingSession.startTime.toUtc())
              .inSeconds;
          
          await _loadSessionAttendance(existingSession.id);
          await _loadClassStudents(existingSession.classIds ?? [existingSession.classId]);
          _startCountdown(existingSession);
          _subscribeToAttendance(existingSession.id);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _entranceController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load data. Pull to refresh.';
        });
      }
    }
  }

  Future<void> _loadSessionAttendance(String sessionId) async {
    final records = await SupabaseService.getSessionAttendance(sessionId);
    if (mounted) setState(() => _attendance = records);
  }

  Future<void> _loadClassStudents(List<String> classIds) async {
    try {
      final students = await SupabaseService.getStudentsByClasses(classIds);
      if (mounted) {
        setState(() {
          _classStudents = students;
        });
      }
    } catch (e) {
      debugPrint('[Session] Failed to load class students: $e');
    }
  }

  Future<void> _toggleAttendance(String studentId, bool isPresent) async {
    if (_activeSession == null) return;

    // Snapshot current attendance list for instant rollback on failure
    final previousAttendance = List<AttendanceModel>.from(_attendance);

    // 1. Optimistic UI Update: Instantly mutate local state for flawless UI toggle
    setState(() {
      final existingIndex = _attendance.indexWhere((a) => a.studentId == studentId);
      if (isPresent) {
        final studentModel = _classStudents.firstWhere(
          (s) => s.id == studentId,
          orElse: () => UserModel(id: studentId, email: '', name: 'Student', role: 'student'),
        );
        final newRecord = AttendanceModel(
          id: existingIndex != -1
              ? _attendance[existingIndex].id
              : 'temp_${DateTime.now().millisecondsSinceEpoch}',
          sessionId: _activeSession!.id,
          studentId: studentId,
          timestamp: DateTime.now(),
          status: 'present',
          studentName: studentModel.name,
          studentEmail: studentModel.email,
        );
        if (existingIndex != -1) {
          _attendance[existingIndex] = newRecord;
        } else {
          _attendance.add(newRecord);
        }
      } else {
        if (existingIndex != -1) {
          _attendance.removeAt(existingIndex);
        }
      }
    });

    // 2. Perform database update asynchronously in background
    final success = await SupabaseService.setAttendanceStatus(
      studentId: studentId,
      sessionId: _activeSession!.id,
      status: isPresent ? 'present' : 'absent',
    );

    if (success) {
      // Log action asynchronously
      SupabaseService.client.from('attendance_logs').insert({
        'action': isPresent ? 'marked' : 'revoked',
        'performed_by': _currentUser!.id,
        'student_id': studentId,
        'session_id': _activeSession!.id,
        'timestamp': DateTime.now().toIso8601String(),
      }).catchError((e) => debugPrint('[Session] Log error: $e'));
    } else {
      // Revert local state if network write failed
      if (mounted) {
        setState(() {
          _attendance = previousAttendance;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update attendance status.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.errorSoft,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _subscribeToAttendance(String sessionId) {
    debugPrint('[Session] Subscribing to attendance for session: $sessionId');
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = SupabaseService.subscribeToSessionAttendance(sessionId, (
      records,
    ) {
      debugPrint(
        '[Session] Received ${records.length} attendance records via Realtime',
      );
      if (mounted) {
        setState(() {
          _attendance = records.map((e) => AttendanceModel.fromMap(e)).toList();
          debugPrint('[Session] UI updated with ${_attendance.length} records');
        });
      }
    });
    // Fallback: poll every 10s in case realtime events are missed
    _attendancePollTimer?.cancel();
    _attendancePollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_activeSession != null) {
        _loadSessionAttendance(_activeSession!.id);
      } else {
        _attendancePollTimer?.cancel();
      }
    });
  }

  void _startCountdown(SessionModel session) {
    _countdownTimer?.cancel();
    // Use client-side duration to avoid timezone issues with end_time
    if (session.endTime != null) {
      _remainingSeconds = session.endTime!
          .toUtc()
          .difference(DateTime.now().toUtc())
          .inSeconds;
    } else {
      _remainingSeconds = _durationSeconds;
    }
    debugPrint(
      '[Session] Countdown started: remaining=$_remainingSeconds, '
      'duration=$_durationSeconds, endTime=${session.endTime}',
    );
    if (_remainingSeconds <= 0) {
      _handleSessionExpired();
      return;
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remainingSeconds--);
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _handleSessionExpired();
      }
    });
  }

  String _formatSessionClassName(SessionModel session) {
    final ids = session.classIds ?? [session.classId];
    final names = _classes
        .where((c) => ids.contains(c.id))
        .map((c) => c.name)
        .toList();
    if (names.isNotEmpty) {
      return names.join(' + ');
    }
    return _classes
        .firstWhere(
          (c) => c.id == session.classId,
          orElse: () => ClassModel(id: '', name: 'Unknown'),
        )
        .name;
  }

  Future<void> _handleSessionExpired() async {
    if (_activeSession == null) return;

    final session = _activeSession!;
    final className = _formatSessionClassName(session);
    final subjectModel = _subjects.firstWhere(
      (s) => s.id == session.subjectId,
      orElse: () => SubjectModel(id: '', name: 'Unknown'),
    );
    final subjectName = subjectModel.name;

    await SupabaseService.endSession(session.id);
    await BleService.stopAdvertising();
    _countdownTimer?.cancel();
    _codeOnlyTimer?.cancel();
    _realtimeChannel?.unsubscribe();

    if (!mounted) return;

    // Navigate to session report screen on time expiry
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionReportScreen(
          session: session,
          className: className,
          subjectName: subjectName,
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _activeSession = null;
        _attendance = [];
        _remainingSeconds = 0;
        _isEndingSession = false;
        _isCodeOnlyMode = false;
        _codeOnlyRemainingSeconds = 0;
      });
    }
  }

  Future<void> _enableCodeOnlyMode() async {
    if (_activeSession == null) return;
    final confirmed = await _showConfirmDialog(
      title: 'Enable Code-Only Mode',
      message:
          'This will temporarily lower security to LOW so students without Bluetooth can mark attendance using only the session code. '
          'The code will be displayed prominently. Code-only mode lasts 2 minutes.',
      confirmLabel: 'Enable',
    );
    if (!confirmed) return;

    setState(() {
      _previousSecurityLevel = _activeSession!.securityLevel;
      _isCodeOnlyMode = true;
      _codeOnlyRemainingSeconds = 120; // 2 minutes
    });

    await SupabaseService.updateSessionSecurityLevel(_activeSession!.id, 'LOW');

    _codeOnlyTimer?.cancel();
    _codeOnlyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _codeOnlyRemainingSeconds--);
      if (_codeOnlyRemainingSeconds <= 0) {
        _disableCodeOnlyMode(auto: true);
      }
    });
  }

  Future<void> _disableCodeOnlyMode({bool auto = false}) async {
    _codeOnlyTimer?.cancel();
    if (_activeSession != null && _previousSecurityLevel != null) {
      await SupabaseService.updateSessionSecurityLevel(
        _activeSession!.id,
        _previousSecurityLevel!,
      );
    }
    if (mounted) {
      setState(() {
        _isCodeOnlyMode = false;
        _codeOnlyRemainingSeconds = 0;
      });
      if (auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Code-only mode expired. Security restored to $_previousSecurityLevel.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.surfaceVariant,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _startSession() async {
    if (_selectedClassIds.isEmpty || _selectedSubjectId == null) {
      setState(() => _errorMessage = 'Select at least one class and a subject first.');
      return;
    }
    setState(() {
      _isStartingSession = true;
      _errorMessage = null;
    });

    try {
      // Request BLE permissions
      final permissionsGranted = await BleService.requestPermissions();
      if (!permissionsGranted) {
        debugPrint('[Session] BLE permissions not granted');
      }

      // Generate 6-digit code
      final code = (100000 + Random().nextInt(900000)).toString();

      final actualLectureTime = _lectureTimeSlot == 'Custom'
          ? (_customLectureTimeSlot != null && _customLectureTimeSlot!.isNotEmpty
              ? _customLectureTimeSlot
              : 'Custom')
          : _lectureTimeSlot;

      final session = await SupabaseService.createSession(
        teacherId: _currentUser!.id,
        classId: _selectedClassIds.first,
        subjectId: _selectedSubjectId!,
        code: code,
        securityLevel: _securityLevel,
        rssiThreshold: _rssiThreshold,
        durationSeconds: _durationSeconds,
        lectureTime: actualLectureTime,
        classIds: _selectedClassIds,
      );

      if (session != null) {
        // Start BLE advertising if permissions granted
        var bleAdvertising = false;
        if (permissionsGranted) {
          bleAdvertising = await BleService.startAdvertising(session.id);
        }

        // Warn user if BLE failed but HIGH security was selected
        if (!bleAdvertising && _securityLevel == 'HIGH' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'BLE advertising could not start. Check Bluetooth is on and permissions are granted.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: AppTheme.surfaceVariant,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        setState(() {
          _activeSession = session;
          _attendance = [];
        });
        await _loadClassStudents(session.classIds ?? [session.classId]);
        _startCountdown(session);
        _subscribeToAttendance(session.id);
      } else {
        setState(() => _errorMessage = 'Failed to create session.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error starting session: $e');
    } finally {
      if (mounted) setState(() => _isStartingSession = false);
    }
  }

  Future<void> _endSession() async {
    if (_activeSession == null) return;
    final confirm = await _showConfirmDialog(
      title: 'End Session',
      message:
          'Are you sure you want to end this session? No more attendance can be marked.',
      confirmLabel: 'End Session',
      isDangerous: true,
    );
    if (!confirm) return;

    setState(() => _isEndingSession = true);

    // Capture current session before ending
    final session = _activeSession!;

    final className = _formatSessionClassName(session);
    final subjectModel = _subjects.firstWhere(
      (s) => s.id == session.subjectId,
      orElse: () => SubjectModel(id: '', name: 'Unknown'),
    );
    final subjectName = subjectModel.name;

    await SupabaseService.endSession(session.id);
    await BleService.stopAdvertising();
    _countdownTimer?.cancel();
    _codeOnlyTimer?.cancel();
    _realtimeChannel?.unsubscribe();

    if (!mounted) return;

    // Navigate to session report screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionReportScreen(
          session: session,
          className: className,
          subjectName: subjectName,
        ),
      ),
    );

    // After returning from report, clear the session state
    if (mounted) {
      setState(() {
        _activeSession = null;
        _attendance = [];
        _remainingSeconds = 0;
        _isEndingSession = false;
        _isCodeOnlyMode = false;
        _codeOnlyRemainingSeconds = 0;
      });
    }
  }

  Future<void> _revokeAttendance(AttendanceModel record) async {
    // Check undo window: session active OR within 5 min of marking
    final isWithinUndoWindow =
        _activeSession != null ||
        DateTime.now().difference(record.timestamp).inMinutes < 5;

    if (!isWithinUndoWindow) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Undo window expired (5 min after marking)',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.surfaceVariant,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _UndoAttendanceDialog(
        studentName: record.studentName ?? 'Student',
        reasonController: reasonController,
      ),
    );

    if (confirmed == true) {
      final success = await SupabaseService.revokeAttendance(
        attendanceId: record.id,
        teacherId: _currentUser!.id,
        studentId: record.studentId,
        sessionId: record.sessionId,
        reason: reasonController.text.trim(),
      );
      if (success) {
        await _loadSessionAttendance(_activeSession!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Attendance revoked for ${record.studentName ?? "student"}',
                style: GoogleFonts.plusJakartaSans(fontSize: 13),
              ),
              backgroundColor: AppTheme.surfaceVariant,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    }
    reasonController.dispose();
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        isDangerous: isDangerous,
      ),
    );
    return result ?? false;
  }

  Future<void> _signOut() async {
    final confirm = await _showConfirmDialog(
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      isDangerous: true,
    );
    if (!confirm) return;
    await SupabaseService.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.signUpLoginScreen,
        (_) => false,
      );
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _entranceController.dispose();
    _countdownTimer?.cancel();
    _codeOnlyTimer?.cancel();
    _attendancePollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    BleService.dispose();
    super.dispose();
  }

  Future<void> _showExitConfirmationDialog() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.exit_to_app_rounded,
                color: AppTheme.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Exit Application',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to exit UpasthitiX?',
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
              style: GoogleFonts.plusJakartaSans(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
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
              'Exit App',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_showReports) {
            setState(() => _showReports = false);
            return;
          }
          await _showExitConfirmationDialog();
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          bottomNavigationBar: (_activeSession != null && !_showReports)
              ? Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    MediaQuery.of(context).padding.bottom > 0
                        ? MediaQuery.of(context).padding.bottom + 8
                        : 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withAlpha(240),
                    border: Border(
                      top: BorderSide(
                        color: AppTheme.shadowLight.withAlpha(25),
                        width: 1,
                      ),
                    ),
                  ),
                  child: _buildEndSessionButton(),
                )
              : null,
          body: Stack(
            children: [
              _buildBackground(),
              SafeArea(
                child: _isLoading
                    ? _buildLoadingState()
                    : _showReports
                    ? TeacherReportsTab(
                        onBack: () {
                          setState(() {
                            _showReports = false;
                          });
                        },
                      )
                    : FadeTransition(
                        opacity: _entranceFade,
                        child: isTablet
                            ? _buildTabletLayout()
                            : _buildPhoneLayout(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: AppTheme.background,
          ),
        ),
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primaryCyan.withAlpha(31),
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
            width: 500,
            height: 500,
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
        color: AppTheme.primary,
        strokeWidth: 2.5,
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surfaceVariant,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_errorMessage != null) _buildErrorBanner(),
                if (_activeSession != null) ...[
                  BleBroadcastIndicatorWidget(
                    pulseAnimation: _pulseAnimation,
                    sessionId: _activeSession!.id,
                    isAdvertising: BleService.isAdvertising,
                  ),
                  const SizedBox(height: 16),
                  SessionCodeDisplayWidget(
                    code: _activeSession!.code,
                    remainingSeconds: _remainingSeconds,
                    totalSeconds: _durationSeconds,
                    formatDuration: _formatDuration,
                    securityLevel: _activeSession!.securityLevel,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: BleRadarWidget(
                      isScanning: _activeSession != null,
                      showRadarAnimation: _showRadarAnimation,
                      onToggleRadar: (val) =>
                          setState(() => _showRadarAnimation = val),
                      label: 'BLE Advertising Active',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SessionStatsWidget(
                    attendance: _attendance,
                    session: _activeSession!,
                    totalClassStudents: _classStudents.length,
                  ),
                  const SizedBox(height: 12),
                  _buildDownloadButton(),
                  const SizedBox(height: 16),
                  _buildRetakeSessionButton(),
                  const SizedBox(height: 16),
                  if (_isCodeOnlyMode) ...[
                    _buildCodeOnlyBanner(),
                    const SizedBox(height: 16),
                  ],
                  AttendanceListWidget(
                    attendance: _attendance,
                    classStudents: _classStudents,
                    onToggleAttendance: _toggleAttendance,
                    onRevokeAttendance: _revokeAttendance,
                    isSessionActive: _activeSession != null,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  SessionConfigWidget(
                    classes: _classes,
                    subjects: _subjects,
                    assignments: _assignments,
                    selectedClassIds: _selectedClassIds,
                    selectedSubjectId: _selectedSubjectId,
                    lectureTime: _lectureTimeSlot,
                    customLectureTime: _customLectureTimeSlot ?? '',
                    durationSeconds: _durationSeconds,
                    securityLevel: _securityLevel,
                    rssiThreshold: _rssiThreshold,
                    onClassesChanged: (ids) =>
                        setState(() => _selectedClassIds = ids),
                    onSubjectChanged: (id) =>
                        setState(() => _selectedSubjectId = id),
                    onLectureTimeChanged: (t) =>
                        setState(() => _lectureTimeSlot = t),
                    onCustomLectureTimeChanged: (t) =>
                        setState(() => _customLectureTimeSlot = t),
                    onDurationChanged: (d) =>
                        setState(() => _durationSeconds = d),
                    onSecurityLevelChanged: (s) =>
                        setState(() => _securityLevel = s),
                    onRssiThresholdChanged: (r) =>
                        setState(() => _rssiThreshold = r),
                  ),
                  const SizedBox(height: 20),
                  _buildStartSessionButton(),
                ],
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        // Left: Config or session info
        Expanded(
          flex: 4,
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 10, 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_errorMessage != null) _buildErrorBanner(),
                    if (_activeSession != null) ...[
                      BleBroadcastIndicatorWidget(
                        pulseAnimation: _pulseAnimation,
                        sessionId: _activeSession!.id,
                        isAdvertising: BleService.isAdvertising,
                      ),
                      const SizedBox(height: 16),
                      SessionCodeDisplayWidget(
                        code: _activeSession!.code,
                        remainingSeconds: _remainingSeconds,
                        totalSeconds: _durationSeconds,
                        formatDuration: _formatDuration,
                        securityLevel: _activeSession!.securityLevel,
                      ),
                      const SizedBox(height: 16),
                      SessionStatsWidget(
                        attendance: _attendance,
                        session: _activeSession!,
                        totalClassStudents: _classStudents.length,
                      ),
                      const SizedBox(height: 12),
                      _buildDownloadButton(),
                      const SizedBox(height: 16),
                      _buildRetakeSessionButton(),
                      const SizedBox(height: 16),
                      if (_isCodeOnlyMode) ...[
                        _buildCodeOnlyBanner(),
                        const SizedBox(height: 16),
                      ],
                      _buildEndSessionButton(),
                    ] else ...[
                      SessionConfigWidget(
                        classes: _classes,
                        subjects: _subjects,
                        assignments: _assignments,
                        selectedClassIds: _selectedClassIds,
                        selectedSubjectId: _selectedSubjectId,
                        lectureTime: _lectureTimeSlot,
                        customLectureTime: _customLectureTimeSlot ?? '',
                        durationSeconds: _durationSeconds,
                        securityLevel: _securityLevel,
                        rssiThreshold: _rssiThreshold,
                        onClassesChanged: (ids) =>
                            setState(() => _selectedClassIds = ids),
                        onSubjectChanged: (id) =>
                            setState(() => _selectedSubjectId = id),
                        onLectureTimeChanged: (t) =>
                            setState(() => _lectureTimeSlot = t),
                        onCustomLectureTimeChanged: (t) =>
                            setState(() => _customLectureTimeSlot = t),
                        onDurationChanged: (d) =>
                            setState(() => _durationSeconds = d),
                        onSecurityLevelChanged: (s) =>
                            setState(() => _securityLevel = s),
                        onRssiThresholdChanged: (r) =>
                            setState(() => _rssiThreshold = r),
                      ),
                      if (!_permissionsGranted || !_bluetoothOn || !_locationServicesEnabled) ...[
                        const SizedBox(height: 16),
                        SystemSetupDisclaimer(
                          permissionsGranted: _permissionsGranted,
                          bluetoothOn: _bluetoothOn,
                          locationServicesEnabled: _locationServicesEnabled,
                          onRefresh: _refreshSystemStatus,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _buildStartSessionButton(),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
        // Right: Attendance list
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                if (_activeSession != null)
                  Expanded(
                    child: AttendanceListWidget(
                      attendance: _attendance,
                      classStudents: _classStudents,
                      onToggleAttendance: _toggleAttendance,
                      onRevokeAttendance: _revokeAttendance,
                      isSessionActive: _activeSession != null,
                    ),
                  )
                else
                  Expanded(
                    child: Center(
                      child: EmptyStateWidget(
                        icon: Icons.people_outline_rounded,
                        title: 'No Active Session',
                        description:
                            'Configure and start a session to see attendance here in real-time.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      floating: true,
      backgroundColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.shadowLight.withAlpha(25),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.shadowLight.withAlpha(25),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'UpasthitiX',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (_currentUser != null)
                Text(
                  _currentUser!.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (_activeSession != null)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.success,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        IconButton(
          onPressed: () {
            Navigator.pushNamed(context, AppRoutes.completedClassesTimetableScreen);
          },
          icon: Icon(
            Icons.calendar_month_rounded,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          tooltip: 'Timetable',
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _showReports = !_showReports;
            });
          },
          icon: Icon(
            _showReports ? Icons.sensors_rounded : Icons.bar_chart_rounded,
            color: _showReports ? AppTheme.primary : AppTheme.textSecondary,
            size: 22,
          ),
          tooltip: _showReports ? 'Session' : 'Reports',
        ),
        IconButton(
          onPressed: _signOut,
          icon: Icon(
            Icons.power_settings_new_rounded,
            color: AppTheme.error.withAlpha(240),
            size: 20,
          ),
          tooltip: 'Sign Out',
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.errorSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.error,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildStartSessionButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(102),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isStartingSession ? null : _startSession,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isStartingSession
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_circle_outline_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Start Attendance Session',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewTimetableCard() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppTheme.surface.withAlpha(15),
        border: Border.all(
          color: AppTheme.shadowLight.withAlpha(25),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.completedClassesTimetableScreen);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: AppTheme.primaryCyan,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View Completed Classes',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Daily timetable of ended sessions',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRetakeSessionButton() {
    if (_isCodeOnlyMode) return const SizedBox.shrink();
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.warningSoft,
        border: Border.all(color: AppTheme.warning.withAlpha(77), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _enableCodeOnlyMode,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: AppTheme.warning, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Re-take Session (Code-Only)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    if (_activeSession == null) return const SizedBox.shrink();
    final className = _formatSessionClassName(_activeSession!);
    final subjectModel = _subjects.firstWhere(
      (s) => s.id == _activeSession!.subjectId,
      orElse: () => SubjectModel(id: '', name: 'Unknown'),
    );
    final subjectName = subjectModel.name;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(77),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await CsvExportService.downloadCsv(
              context: context,
              subjectName: subjectName,
              className: className,
              session: _activeSession!,
              attendance: _attendance,
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Download CSV',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeOnlyBanner() {
    final minutes = _codeOnlyRemainingSeconds ~/ 60;
    final seconds = _codeOnlyRemainingSeconds % 60;
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppTheme.warning.withAlpha(26),
            AppTheme.warning.withAlpha(13),
          ],
        ),
        border: Border.all(color: AppTheme.warning.withAlpha(77), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(38),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: AppTheme.warning,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Code-Only Mode Active',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
              ),
              Text(
                timeStr,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.warning,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Session Code (share with students):',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _activeSession?.code ?? '------',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppTheme.warning,
                letterSpacing: 6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Students can now mark attendance using only the code. Security reverts to $_previousSecurityLevel in $timeStr.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _disableCodeOnlyMode(),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.warning,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  'END NOW',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEndSessionButton() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFB91C1C), // Vibrant crimson red
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB91C1C).withAlpha(80),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isEndingSession ? null : _endSession,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white10,
          child: Center(
            child: _isEndingSession
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.stop_circle_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'End Session',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Dialogs ──────────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isDangerous;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDangerous
                          ? AppTheme.error
                          : AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      confirmLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoAttendanceDialog extends StatelessWidget {
  final String studentName;
  final TextEditingController reasonController;

  const _UndoAttendanceDialog({
    required this.studentName,
    required this.reasonController,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.undo_rounded,
                    color: AppTheme.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Revoke Attendance',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        studentName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Reason (optional)',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.textMuted,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            GlassFormFieldWidget(
              label: 'Reason for revocation',
              controller: reasonController,
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      'Revoke',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
