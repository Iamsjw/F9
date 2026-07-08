import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import '../../core/app_export.dart';
import '../../core/device_helper.dart';
import '../../routes/app_routes.dart';
import '../../services/ble_service.dart';
import '../../widgets/system_setup_disclaimer.dart';
import './widgets/attendance_history_widget.dart';
import './widgets/ble_scan_widget.dart';
import './widgets/code_entry_widget.dart';
import './widgets/rssi_meter_widget.dart';

enum _MarkingState {
  idle,
  enteringCode,
  scanningBle,
  verifying,
  success,
  failed,
}

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // TODO: Replace with Riverpod StudentAttendanceNotifier for production

  UserModel? _currentUser;
  List<AttendanceModel> _attendanceHistory = [];
  SessionModel? _currentSession;

  _MarkingState _markingState = _MarkingState.idle;
  int _currentRssi = -100;
  String? _errorMessage;
  bool _isLoading = true;
  bool _permissionsGranted = false;
  bool _bluetoothOn = false;
  bool _locationServicesEnabled = false;
  bool _bleDialogShown = false;
  bool _showRadarSection = false; // Disabled & hidden by default

  late AnimationController _successController;
  late AnimationController _entranceController;
  late AnimationController _shakeController;
  late Animation<double> _successScale;
  late Animation<double> _entranceFade;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _successScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.easeOutBack),
    );
    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );

    _loadInitialData();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns from Android Settings (e.g., after enabling Bluetooth/Location),
    // re-check status so the UI updates without requiring a manual refresh.
    if (state == AppLifecycleState.resumed) {
      Future.wait([
        BleService.hasPermissions(),
        BleService.isBluetoothOn(),
        BleService.isLocationEnabled(),
      ]).then((results) {
        if (mounted) {
          setState(() {
            _permissionsGranted = results[0];
            _bluetoothOn = results[1];
            _locationServicesEnabled = results[2];
            if (_bluetoothOn) {
              _bleDialogShown = false; // BT is now on, reset flag
            }
          });
        }
      }).catchError((_) {});
    }
  }

  Future<void> _refreshData() async {
    try {
      _currentUser = await SupabaseService.getCurrentUserProfile();
      if (_currentUser == null) return;
      _attendanceHistory = await SupabaseService.getStudentAttendanceHistory(
        _currentUser!.id,
      );
      _permissionsGranted = await BleService.hasPermissions();
      _bluetoothOn = await BleService.isBluetoothOn();
      _locationServicesEnabled = await BleService.isLocationEnabled();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _refreshSystemStatus() async {
    try {
      final permissions = await BleService.hasPermissions();
      final btOn = await BleService.isBluetoothOn();
      final gpsOn = await BleService.isLocationEnabled();
      if (mounted) {
        setState(() {
          _permissionsGranted = permissions;
          _bluetoothOn = btOn;
          _locationServicesEnabled = gpsOn;
          if (_bluetoothOn) {
            _bleDialogShown = false;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _currentUser = await SupabaseService.getCurrentUserProfile();
      if (_currentUser == null || _currentUser!.role != 'student') {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.signUpLoginScreen,
            (_) => false,
          );
        }
        return;
      }

      _attendanceHistory = await SupabaseService.getStudentAttendanceHistory(
        _currentUser!.id,
      );
      _permissionsGranted = await BleService.requestPermissions();
      _bluetoothOn = await BleService.isBluetoothOn();
      _locationServicesEnabled = await BleService.isLocationEnabled();

      if (mounted) {
        setState(() => _isLoading = false);
        _entranceController.forward();

        // Show Bluetooth dialog if off
        if (!_bluetoothOn && !_bleDialogShown) {
          _bleDialogShown = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _showBluetoothDialog();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBluetoothDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.warningSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_disabled_rounded,
                color: AppTheme.warning,
                size: 36,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Bluetooth is Off',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Please turn on Bluetooth to use proximity verification for HIGH security sessions. Without Bluetooth, you may not be able to mark attendance in some sessions.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      _bleDialogShown = false;
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Dismiss',
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
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      _bleDialogShown = false;
                      Navigator.pop(ctx);
                      await BleService.enableBluetooth();
                    },
                    child: Text(
                      'Enable Bluetooth',
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

  Future<void> _submitCode(String code) async {
    if (code.length != 6) return;

    if (SupabaseService.isSessionCodeLockedOut()) {
      final rem = SupabaseService.getRemainingLockoutDuration();
      final mins = rem != null ? (rem.inSeconds / 60).ceil() : 10;
      _setError('Too many invalid attempts. Account locked out for $mins minutes.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _markingState = _MarkingState.verifying;
    });

    try {
      // Find session by code
      final session = await SupabaseService.getActiveSessionByCode(code);

      if (session == null) {
        if (SupabaseService.isSessionCodeLockedOut()) {
          final rem = SupabaseService.getRemainingLockoutDuration();
          final mins = rem != null ? (rem.inSeconds / 60).ceil() : 10;
          _setError('Too many invalid attempts (5 max). Try again in $mins minutes.');
        } else {
          _setError('Invalid or expired session code.');
        }
        return;
      }

      // Check if already marked
      final alreadyMarked = await SupabaseService.hasStudentMarkedAttendance(
        studentId: _currentUser!.id,
        sessionId: session.id,
      );
      if (alreadyMarked) {
        _setError('You have already marked attendance for this session.');
        return;
      }

      _currentSession = session;

      if (session.securityLevel == 'HIGH') {
        // BLE verification required
        setState(() => _markingState = _MarkingState.scanningBle);
        await _performBleVerification(session);
      } else {
        // LOW security — direct mark
        await _markAttendance(session.id);
      }
    } catch (e) {
      _setError('Verification failed. Please try again.');
    }
  }

  Future<void> _performBleVerification(SessionModel session) async {
    if (!_permissionsGranted) {
      _setError('Bluetooth permissions required for HIGH security sessions.');
      return;
    }
    if (!_bluetoothOn) {
      _setError('Please enable Bluetooth to verify proximity.');
      return;
    }
    final gpsOn = await BleService.isLocationEnabled();
    if (!gpsOn) {
      _setError('Please turn on GPS/Location services to verify proximity.');
      return;
    }

    try {
      final result = await BleService.scanForSession(
        sessionId: session.id,
        timeoutSeconds: 15,
        rssiThreshold: session.rssiThreshold,
        onRssiUpdate: (rssi) {
          if (mounted) setState(() => _currentRssi = rssi);
        },
      );

      if (result == null) {
        // BLE scan failed — offer manual fallback
        _offerManualFallback(session);
        return;
      }

      // RSSI tolerance: ±5 dBm
      final adjustedThreshold = session.rssiThreshold - 5;
      if (result.rssi >= adjustedThreshold) {
        await _markAttendance(session.id);
      } else {
        _setError(
          'You are too far from the classroom. Move closer and try again.\nDetected RSSI: ${result.rssi} dBm (Required: ≥ ${session.rssiThreshold} dBm)',
        );
      }
    } catch (e) {
      _offerManualFallback(session);
    }
  }

  void _offerManualFallback(SessionModel session) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _BleFailedDialog(
        onRetry: () {
          Navigator.pop(ctx);
          setState(() => _markingState = _MarkingState.scanningBle);
          _performBleVerification(session);
        },
        onCancel: () {
          Navigator.pop(ctx);
          setState(() => _markingState = _MarkingState.idle);
        },
      ),
    );
  }

  Future<void> _markAttendance(String sessionId) async {
    setState(() => _markingState = _MarkingState.verifying);
    try {
      final deviceId = await DeviceHelper.getUniqueDeviceId();
      final success = await SupabaseService.markAttendance(
        studentId: _currentUser!.id,
        sessionId: sessionId,
        deviceId: deviceId,
      );

      if (success) {
        setState(() {
          _markingState = _MarkingState.success;
        });
        _successController.forward();
        // Reload history
        _attendanceHistory = await SupabaseService.getStudentAttendanceHistory(
          _currentUser!.id,
        );
        if (mounted) setState(() {});

        // Auto-reset after 8 seconds
        Timer(const Duration(seconds: 8), () {
          if (mounted) {
            setState(() {
              _markingState = _MarkingState.idle;
              _currentRssi = -100;
            });
            _successController.reset();
          }
        });
      } else {
        _setError(
          'Failed to mark attendance. Already marked or session expired.',
        );
      }
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').trim();
      _setError(msg.isNotEmpty ? msg : 'Failed to mark attendance.');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _markingState = _MarkingState.failed;
    });
    _shakeController.forward(from: 0);
    Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _markingState = _MarkingState.idle;
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out?',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign Out',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SupabaseService.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.signUpLoginScreen,
        (_) => false,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _successController.dispose();
    _entranceController.dispose();
    _shakeController.dispose();
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
          await _showExitConfirmationDialog();
        },
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(
            children: [
              _buildBackground(),
              SafeArea(
                child: _isLoading
                    ? _buildLoadingState()
                    : RefreshIndicator(
                        onRefresh: _refreshData,
                        color: AppTheme.primary,
                        backgroundColor: AppTheme.surface,
                        child: FadeTransition(
                          opacity: _entranceFade,
                          child: isTablet
                              ? _buildTabletLayout()
                              : _buildPhoneLayout(),
                        ),
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
          left: -100,
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
          right: -150,
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
    return Center(
      child: CircularProgressIndicator(
        color: AppTheme.primaryCyan,
        strokeWidth: 2.5,
      ),
    );
  }

  Widget _buildPhoneLayout() {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        _buildAppBar(),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Success overlay
              if (_markingState == _MarkingState.success)
                _buildSuccessCard()
              else ...[
                _buildMarkAttendanceSection(),
                _buildViewTimetableCard(),
                const SizedBox(height: 24),
                AttendanceHistoryWidget(history: _attendanceHistory),
              ],
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 10, 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_markingState == _MarkingState.success)
                      _buildSuccessCard()
                    else
                      _buildMarkAttendanceSection(),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 20, 20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildViewTimetableCard(),
                const SizedBox(height: 16),
                Expanded(
                  child: AttendanceHistoryWidget(history: _attendanceHistory),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // BLE status indicator
        Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _bluetoothOn
                ? AppTheme.primaryCyan.withAlpha(26)
                : AppTheme.surface.withAlpha(13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bluetooth_rounded,
                size: 14,
                color: _bluetoothOn ? AppTheme.primaryCyan : AppTheme.textMuted,
              ),
              const SizedBox(width: 3),
              Text(
                _bluetoothOn ? 'ON' : 'OFF',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _bluetoothOn
                      ? AppTheme.primaryCyan
                      : AppTheme.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
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

  Widget _buildMarkAttendanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Greeting
        _buildGreetingCard(),
        const SizedBox(height: 16),

        // Live Radar Toggle Option
        _buildRadarToggleCard(),

        // BLE scan state visualizer (Hidden by default unless enabled)
        if (_showRadarSection) ...[
          const SizedBox(height: 16),
          BleScanWidget(
            currentRssi: _currentRssi,
            rssiThreshold: _currentSession?.rssiThreshold ?? -70,
          ),
        ],
        const SizedBox(height: 16),

        // RSSI meter when scanning
        if (_markingState == _MarkingState.scanningBle &&
            _currentRssi > -100) ...[
          RssiMeterWidget(
            rssi: _currentRssi,
            threshold: _currentSession?.rssiThreshold ?? -70,
          ),
          const SizedBox(height: 16),
        ],

        // Error message
        if (_errorMessage != null) _buildErrorCard(),

        // Code entry (shown when idle or failed)
        if (_markingState == _MarkingState.idle ||
            _markingState == _MarkingState.failed ||
            _markingState == _MarkingState.enteringCode) ...[
          CodeEntryWidget(
            onCodeSubmit: _submitCode,
            isLoading: _markingState == _MarkingState.verifying,
            shakeAnimation: _shakeAnim,
            hasError: _markingState == _MarkingState.failed,
          ),
        ],

        if (_markingState == _MarkingState.verifying &&
            _markingState != _MarkingState.scanningBle)
          _buildVerifyingCard(),

        // BLE permission warning
        if (!_permissionsGranted || !_bluetoothOn || !_locationServicesEnabled)
          SystemSetupDisclaimer(
            permissionsGranted: _permissionsGranted,
            bluetoothOn: _bluetoothOn,
            locationServicesEnabled: _locationServicesEnabled,
            onRefresh: _refreshSystemStatus,
          ),
      ],
    );
  }

  Widget _buildRadarToggleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _showRadarSection
                  ? AppTheme.primaryCyan.withAlpha(38)
                  : AppTheme.surface.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.radar_rounded,
              size: 20,
              color: _showRadarSection
                  ? AppTheme.primaryCyan
                  : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live BLE Radar',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  _showRadarSection
                      ? 'Live signal visualizer enabled'
                      : 'Disabled by default',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _showRadarSection,
            activeThumbColor: AppTheme.primaryCyan,
            activeTrackColor: AppTheme.primaryCyan.withAlpha(77),
            inactiveThumbColor: AppTheme.textMuted,
            inactiveTrackColor: AppTheme.surface.withAlpha(50),
            onChanged: (val) {
              HapticFeedback.selectionClick();
              setState(() => _showRadarSection = val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGreetingCard() {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }

    final presentToday = _attendanceHistory
        .where(
          (a) =>
              a.isPresent &&
              a.timestamp.day == DateTime.now().day &&
              a.timestamp.month == DateTime.now().month,
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryCyan.withAlpha(31),
            AppTheme.primaryBlue.withAlpha(20),
          ],
        ),
        border: Border.all(color: AppTheme.primaryCyan.withAlpha(64), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting,',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        _currentUser?.name ?? 'Student',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$presentToday class${presentToday != 1 ? 'es' : ''} attended today',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppTheme.primaryCyan,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryCyan.withAlpha(26),
                    border: Border.all(
                      color: AppTheme.primaryCyan.withAlpha(77),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _currentUser?.name.isNotEmpty == true
                          ? _currentUser!.name[0].toUpperCase()
                          : 'S',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryCyan,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Toggle to instantly restore the legacy success card animation
  static const bool _usePremiumSuccessCard = true;

  Widget _buildSuccessCard() {
    if (_usePremiumSuccessCard) {
      return PremiumSuccessCard(session: _currentSession);
    }
    return _buildLegacySuccessCard();
  }

  Widget _buildLegacySuccessCard() {
    return ScaleTransition(
      scale: _successScale,
      child: Container(
        decoration: AppTheme.glassMorphism(
          borderRadius: BorderRadius.circular(24),
          opacity: 0.10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.successSoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.success.withAlpha(77),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success.withAlpha(34),
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.success,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Attendance Marked!',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _currentSession != null
                        ? 'Session code: ${_currentSession!.code}'
                        : 'Your attendance has been recorded',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Redirecting in 8 seconds...',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyingCard() {
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
            padding: const EdgeInsets.all(20),
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
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Verifying attendance...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.errorSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }


}

// ─── BLE Failed Dialog ───────────────────────────────────────────────────────

class _BleFailedDialog extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _BleFailedDialog({required this.onRetry, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.warningSoft,
              ),
              child: Icon(
                Icons.bluetooth_disabled_rounded,
                color: AppTheme.warning,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'BLE Scan Failed',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Couldn't detect the teacher's device. Make sure you're in the classroom and Bluetooth is enabled.",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: onCancel,
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
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onRetry,
                    child: Text(
                      'Retry Scan',
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

// ─── Premium Success Card ───────────────────────────────────────────────

class PremiumSuccessCard extends StatefulWidget {
  final SessionModel? session;

  const PremiumSuccessCard({super.key, this.session});

  @override
  State<PremiumSuccessCard> createState() => _PremiumSuccessCardState();
}

class _PremiumSuccessCardState extends State<PremiumSuccessCard>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late AnimationController _drawController;
  late AnimationController _textController;

  late Animation<double> _entranceScale;
  late Animation<double> _entranceFade;
  late Animation<double> _drawAnimation;

  // Staggered text reveals
  late Animation<double> _titleAnimation;
  late Animation<double> _badgeAnimation;
  late Animation<double> _receiptAnimation;
  late Animation<double> _footerAnimation;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Expo ease out: extremely smooth entry scale & fade
    _entranceScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Cubic(0.16, 1, 0.3, 1),
      ),
    );

    _entranceFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOut,
      ),
    );

    _drawAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _drawController,
        curve: const Interval(0.1, 0.9, curve: Curves.easeInOutCubic),
      ),
    );

    // Fine-tuned stagger intervals for reveals
    _titleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _badgeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.25, 0.7, curve: Curves.easeOut),
      ),
    );

    _receiptAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );

    _footerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
      ),
    );

    // Stagger sequence trigger
    _entranceController.forward().then((_) {
      _drawController.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          _textController.forward();
        }
      });
    });

    _triggerHapticSequence();
  }

  Future<void> _triggerHapticSequence() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.selectionClick();
    await Future.delayed(const Duration(milliseconds: 320));
    await HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    _drawController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    final hasSession = widget.session != null;
    final subject = widget.session?.subjectName ?? 'Class Attendance';
    final className = widget.session?.className ?? 'General Group';
    final isHighSecurity = widget.session?.securityLevel == 'HIGH';
    final accentColor = isHighSecurity ? AppTheme.primaryCyan : AppTheme.success;

    return FadeTransition(
      opacity: _entranceFade,
      child: ScaleTransition(
        scale: _entranceScale,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xFF0B0D16),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: accentColor.withOpacity(0.04),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Futuristic Glowing Centerpiece
                SizedBox(
                  height: 140,
                  width: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Breathing ambient radial glow behind checkmark
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(140, 140),
                            painter: _BreathingGlowPainter(
                              progress: _pulseController.value,
                              color: accentColor,
                            ),
                          );
                        },
                      ),
                      // Rotating dashed precision telemetry ring
                      RotationTransition(
                        turns: _rotateController,
                        child: CustomPaint(
                          size: const Size(108, 108),
                          painter: _CyberRingPainter(color: accentColor),
                        ),
                      ),
                      // Inner solid circle for checkmark background
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF05060A),
                          border: Border.all(
                            color: accentColor.withOpacity(0.12),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Path-drawn checkmark painter
                      AnimatedBuilder(
                        animation: _drawAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(68, 68),
                            painter: _AnimatedCheckmarkPainter(
                              progress: _drawAnimation.value,
                              color: accentColor,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Title Section (Fade + Slide)
                AnimatedBuilder(
                  animation: _textController,
                  builder: (context, child) {
                    return Column(
                      children: [
                        // Title
                        Transform.translate(
                          offset: Offset(0, 12 * (1.0 - _titleAnimation.value)),
                          child: Opacity(
                            opacity: _titleAnimation.value,
                            child: Text(
                              'ATTENDANCE SECURED',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.0,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Security Badge
                        Transform.translate(
                          offset: Offset(0, 12 * (1.0 - _badgeAnimation.value)),
                          child: Opacity(
                            opacity: _badgeAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: accentColor.withOpacity(0.15),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Pulsing LED dot
                                  _buildPulsingDot(accentColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    isHighSecurity
                                        ? 'SECURE BIOMETRIC / BLE VERIFIED'
                                        : 'SYSTEM VERIFIED',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 3. Receipt container (Fade + Slide)
                        Transform.translate(
                          offset: Offset(0, 12 * (1.0 - _receiptAnimation.value)),
                          child: Opacity(
                            opacity: _receiptAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF08090E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.04),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Mini Receipt Header
                                  Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: accentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'CRYPTOGRAPHIC VALIDATION LOG',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textMuted.withOpacity(0.6),
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _buildReceiptRow(
                                    label: 'SUBJECT',
                                    value: subject,
                                    highlightValue: true,
                                  ),
                                  const Divider(height: 18, color: Color(0x0FFFFFFF)),
                                  _buildReceiptRow(
                                    label: 'CLASSROOM',
                                    value: className,
                                  ),
                                  const Divider(height: 18, color: Color(0x0FFFFFFF)),
                                  _buildReceiptRow(
                                    label: 'TIMESTAMP',
                                    value: timeStr,
                                  ),
                                  if (hasSession) ...[
                                    const Divider(height: 18, color: Color(0x0FFFFFFF)),
                                    _buildReceiptRow(
                                      label: 'TRANSACTION ID',
                                      value: widget.session!.code,
                                      monoFont: true,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 4. Receipt Footer Barcode & Timer (Fade + Slide)
                        Transform.translate(
                          offset: Offset(0, 12 * (1.0 - _footerAnimation.value)),
                          child: Opacity(
                            opacity: _footerAnimation.value,
                            child: Column(
                              children: [
                                // Digital Barcode
                                _buildBarcode(),
                                const SizedBox(height: 12),
                                // Redirect Timer Text
                                Text(
                                  'Returning to dashboard in 8 seconds...',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10.5,
                                    color: AppTheme.textMuted.withOpacity(0.6),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildPulsingDot(Color color) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = 0.5 + 0.5 * math.sin(_pulseController.value * 2 * math.pi);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(opacity),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(opacity * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBarcode() {
    return Container(
      height: 24,
      margin: const EdgeInsets.only(top: 12),
      child: Opacity(
        opacity: 0.18,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(36, (index) {
            final double width = (index % 5 == 0)
                ? 2.2
                : (index % 3 == 0)
                    ? 1.4
                    : 0.7;
            final double margin = (index % 4 == 0) ? 2.0 : 1.0;
            return Container(
              width: width,
              margin: EdgeInsets.only(right: margin),
              color: Colors.white,
            );
          }),
        ),
      ),
    );
  }

  Widget _buildReceiptRow({
    required String label,
    required String value,
    bool highlightValue = false,
    bool monoFont = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted.withOpacity(0.8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoFont
                ? const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: 0.5,
                  )
                : GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: highlightValue ? FontWeight.w700 : FontWeight.w600,
                    color: highlightValue ? AppTheme.primaryCyan : AppTheme.textPrimary,
                  ),
          ),
        ),
      ],
    );
  }
}

// Breathing Radial Ambient Glow Painter
class _BreathingGlowPainter extends CustomPainter {
  final double progress;
  final Color color;

  _BreathingGlowPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) * (1.0 + 0.12 * math.sin(progress * 2 * math.pi));
    final opacity = 0.15 + 0.08 * math.cos(progress * 2 * math.pi);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(opacity),
          color.withOpacity(opacity * 0.35),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BreathingGlowPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

// Precision telemetry dashed outer dashboard ring
class _CyberRingPainter extends CustomPainter {
  final Color color;

  _CyberRingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Draw outer thin solid circle
    final outerPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, outerPaint);

    // 2. Draw segmented inner dashboard ring
    final paint = Paint()
      ..color = color.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const double dashWidth = 8.0;
    const double spaceWidth = 6.0;
    final double perimeter = 2 * math.pi * radius;
    final int dashCount = (perimeter / (dashWidth + spaceWidth)).floor();
    final double sweepAngle = 2 * math.pi / dashCount;

    for (int i = 0; i < dashCount; i++) {
      final double startAngle = i * sweepAngle;
      final double endAngle = startAngle + sweepAngle * (dashWidth / (dashWidth + spaceWidth));

      // Highlight every 4th segment for telemetry look
      paint.color = (i % 4 == 0) ? color.withOpacity(0.65) : color.withOpacity(0.15);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }

    // 3. Draw tiny indicator ticks on the 4 quadrants
    final tickPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 4; i++) {
      final double angle = i * (math.pi / 2);
      canvas.drawLine(
        Offset(center.dx + (radius - 8) * math.cos(angle), center.dy + (radius - 8) * math.sin(angle)),
        Offset(center.dx + (radius + 2) * math.cos(angle), center.dy + (radius + 2) * math.sin(angle)),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CyberRingPainter oldDelegate) => oldDelegate.color != color;
}

// PathMetrics Drawing Animated Checkmark
class _AnimatedCheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _AnimatedCheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // A nice clean custom checkmark path inside size bounds
    path.moveTo(size.width * 0.30, size.height * 0.51);
    path.lineTo(size.width * 0.45, size.height * 0.65);
    path.lineTo(size.width * 0.70, size.height * 0.36);

    final extractPath = Path();
    for (final pathMetric in path.computeMetrics()) {
      final extract = pathMetric.extractPath(0.0, pathMetric.length * progress);
      extractPath.addPath(extract, Offset.zero);
    }

    // Soft glow shadow behind the drawing checkmark
    canvas.drawPath(
      extractPath,
      Paint()
        ..color = color.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(extractPath, paint);
  }

  @override
  bool shouldRepaint(covariant _AnimatedCheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

