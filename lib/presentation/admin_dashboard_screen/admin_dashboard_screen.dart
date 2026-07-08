import 'dart:ui';
import 'package:flutter/services.dart';

import '../../core/app_export.dart';
import '../../routes/app_routes.dart';
import './widgets/teachers_tab.dart';
import './widgets/classes_tab.dart';
import './widgets/subjects_tab.dart';
import './widgets/assignments_tab.dart';
import './widgets/reports_tab.dart';
import '../../services/csv_export_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _bgAnimationController;
  UserModel? _currentUser;

  final _tabs = const [
    _TabItem('Teachers', Icons.people_outline_rounded),
    _TabItem('Classes', Icons.meeting_room_outlined),
    _TabItem('Subjects', Icons.menu_book_rounded),
    _TabItem('Assignments', Icons.assignment_outlined),
    _TabItem('Reports', Icons.analytics_outlined),
  ];

  final ValueNotifier<int> _dataRevisionNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Continuous 12-second background bubble floating animation
    _bgAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _loadUser();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _dataRevisionNotifier.value++;
    }
  }

  void _notifyDataChanged() {
    _dataRevisionNotifier.value++;
  }

  Future<void> _loadUser() async {
    final user = await SupabaseService.getCurrentUserProfile();
    if (!mounted) return;
    if (user == null || user.role != 'admin') {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.signUpLoginScreen,
        (_) => false,
      );
      return;
    }
    setState(() => _currentUser = user);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant.withAlpha(240),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.error.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.logout_rounded, color: AppTheme.error, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Sign Out',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to exit the Admin Dashboard?',
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
              style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
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

  Future<void> _showCleanDataDialog() async {
    final option = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warning.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_sweep_rounded,
                color: AppTheme.warning,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Clean Application Data',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select an option to clean application data for new students & teachers:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.primary.withAlpha(50)),
              ),
              tileColor: AppTheme.primary.withAlpha(15),
              leading: Icon(Icons.backup_rounded, color: AppTheme.primary),
              title: Text(
                'Export Backup First',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
              subtitle: Text(
                'Download a complete JSON database backup before purging.',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textMuted),
              ),
              onTap: () {
                Navigator.pop(ctx, null);
                CsvExportService.downloadFullBackupJson(context);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.shadowLight.withAlpha(30)),
              ),
              tileColor: AppTheme.surface,
              leading: Icon(Icons.history_toggle_off_rounded, color: AppTheme.warning),
              title: Text(
                'Sessions & Attendance Only',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                'Clears past sessions & attendance logs while keeping users intact.',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textMuted),
              ),
              onTap: () => Navigator.pop(ctx, 'sessions_only'),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppTheme.error.withAlpha(50)),
              ),
              tileColor: AppTheme.surface,
              leading: Icon(Icons.person_remove_rounded, color: AppTheme.error),
              title: Text(
                'Full Reset (New Data Feed)',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              subtitle: Text(
                'Wipes sessions, attendance, assignments, and non-admin users (students & teachers).',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textMuted),
              ),
              onTap: () => Navigator.pop(ctx, 'full_reset'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );

    if (option == null) return;

    final isFullReset = option == 'full_reset';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm ${isFullReset ? "Full Data Reset" : "Purge Sessions"}',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          isFullReset
              ? 'WARNING: This will permanently delete ALL non-admin users (students & teachers), assignments, sessions, and attendance history so you can feed fresh CSV data! Are you sure?'
              : 'Are you sure you want to delete ALL attendance sessions and history logs?',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Yes, Purge Data',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await SupabaseService.purgeSystemData(purgeUsers: isFullReset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (isFullReset
                      ? 'System data reset completed. Ready for new student/teacher feeding.'
                      : 'Session & attendance history purged successfully.')
                  : 'Failed to purge data. Please try again.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: success ? AppTheme.surfaceVariant : AppTheme.errorSoft,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _bgAnimationController.dispose();
    _dataRevisionNotifier.dispose();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _showExitConfirmationDialog();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            // ── Dynamic Animated Moving Orbs & Ambient Blur Layer ─────────────
            _buildAnimatedGlassBackground(),

            SafeArea(
              child: Column(
                children: [
                  _buildFrostedAppBar(),
                  const SizedBox(height: 8),
                  _buildFrostedTabBar(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        TeachersTab(
                          refreshNotifier: _dataRevisionNotifier,
                          onDataChanged: _notifyDataChanged,
                        ),
                        ClassesTab(
                          refreshNotifier: _dataRevisionNotifier,
                          onDataChanged: _notifyDataChanged,
                        ),
                        SubjectsTab(
                          refreshNotifier: _dataRevisionNotifier,
                          onDataChanged: _notifyDataChanged,
                        ),
                        AssignmentsTab(
                          refreshNotifier: _dataRevisionNotifier,
                          onDataChanged: _notifyDataChanged,
                        ),
                        ReportsTab(
                          refreshNotifier: _dataRevisionNotifier,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Professional Ambient Glass Background ─────────────────────────────────
  Widget _buildAnimatedGlassBackground() {
    return Stack(
      children: [
        // Dark Onyx Base
        Positioned.fill(
          child: Container(color: AppTheme.background),
        ),

        // Ambient Orb 1: Deep Indigo / Purple Glow (Top Right)
        Positioned(
          right: -80,
          top: -60,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF6366F1).withAlpha(120),
                  const Color(0xFF4F46E5).withAlpha(40),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Ambient Orb 2: Deep Blue Glow (Bottom Left)
        Positioned(
          left: -100,
          bottom: 40,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF2563EB).withAlpha(110),
                  const Color(0xFF1D4ED8).withAlpha(35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        // Heavy Ambient Blur Layer
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
            child: Container(
              color: Colors.black.withAlpha(50),
            ),
          ),
        ),
      ],
    );
  }

  // ── Frosted Glass App Bar Widget ──────────────────────────────────────────
  Widget _buildFrostedAppBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant.withAlpha(180),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.shadowLight,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                // Clean Logo
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
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            'UpasthitiX',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withAlpha(35),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.success.withAlpha(90),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ONLINE',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _currentUser?.name ?? 'Admin Dashboard',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Cache Refresh Icon
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      onPressed: () {
                        SupabaseService.clearCache();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'System cache refreshed',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12),
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: AppTheme.surfaceVariant,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.sync_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Refresh Cache',
                    ),

                    // Admin Utilities Menu (Backup, Restore, Purge Data)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'More Admin Tools',
                      color: AppTheme.surfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: AppTheme.shadowLight.withAlpha(40),
                        ),
                      ),
                      onSelected: (value) {
                        if (value == 'export') {
                          CsvExportService.downloadFullBackupJson(context);
                        } else if (value == 'restore') {
                          CsvExportService.showRestoreBackupDialog(
                            context,
                            onRestored: () => setState(() {}),
                          );
                        } else if (value == 'clean') {
                          _showCleanDataDialog();
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(
                                Icons.backup_rounded,
                                color: AppTheme.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Export Backup',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'restore',
                          child: Row(
                            children: [
                              Icon(
                                Icons.restore_page_rounded,
                                color: AppTheme.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Restore Backup',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'clean',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_sweep_rounded,
                                color: AppTheme.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Clean Data',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Sign Out
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      onPressed: _signOut,
                      icon: Icon(
                        Icons.power_settings_new_rounded,
                        color: AppTheme.error.withAlpha(240),
                        size: 20,
                      ),
                      tooltip: 'Sign Out',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Frosted Glass Segmented Tab Bar ──────────────────────────────────────
  Widget _buildFrostedTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withAlpha(40),
                width: 1.2,
              ),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              physics: const BouncingScrollPhysics(),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withAlpha(120),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textSecondary,
              labelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              tabs: _tabs
                  .map((t) => Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.icon, size: 14),
                            const SizedBox(width: 5),
                            Text(t.label),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem(this.label, this.icon);
}
