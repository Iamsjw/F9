import '../../../core/app_export.dart';

class AssignmentsTab extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  final VoidCallback? onDataChanged;

  const AssignmentsTab({
    super.key,
    this.refreshNotifier,
    this.onDataChanged,
  });

  @override
  State<AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends State<AssignmentsTab> {
  List<AssignmentModel> _assignments = [];
  List<UserModel> _teachers = [];
  List<ClassModel> _classes = [];
  List<SubjectModel> _subjects = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onExternalRefresh);
    _loadData();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData(showSpinner: false);
    }
  }

  Future<void> _loadData({bool showSpinner = true}) async {
    if (showSpinner && _assignments.isEmpty) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isRefreshing = true);
    }
    try {
      final results = await Future.wait([
        SupabaseService.getTeacherAssignments(''), // get all
        SupabaseService.listUsers(role: 'teacher'),
        SupabaseService.getClasses(),
        SupabaseService.getSubjects(),
      ]);
      if (mounted) {
        setState(() {
          _assignments = results[0] as List<AssignmentModel>;
          _teachers = results[1] as List<UserModel>;
          _classes = results[2] as List<ClassModel>;
          _subjects = results[3] as List<SubjectModel>;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _showAssignDialog() async {
    String? selectedTeacherId;
    String? selectedClassId;
    String? selectedSubjectId;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Assign Teacher',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Teacher dropdown
                _buildDropdown(
                  label: 'Teacher',
                  value: selectedTeacherId,
                  items: _teachers
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedTeacherId = v),
                ),
                const SizedBox(height: 12),
                // Class dropdown
                _buildDropdown(
                  label: 'Class',
                  value: selectedClassId,
                  items: _classes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedClassId = v),
                ),
                const SizedBox(height: 12),
                // Subject dropdown
                _buildDropdown(
                  label: 'Subject',
                  value: selectedSubjectId,
                  items: _subjects
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedSubjectId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textMuted,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (selectedTeacherId == null ||
                    selectedClassId == null ||
                    selectedSubjectId == null) {
                  return;
                }
                final messenger = ScaffoldMessenger.of(context); // ignore: use_build_context_synchronously
                final result = await SupabaseService.assignTeacherToClass(
                  teacherId: selectedTeacherId!,
                  classId: selectedClassId!,
                  subjectId: selectedSubjectId!,
                );
                if (result != null && mounted) {
                  // ignore: use_build_context_synchronously
                  Navigator.pop(
                    ctx, // ignore: use_build_context_synchronously
                    true,
                  );
                } else if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to assign teacher. Check Supabase logs.',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13),
                      ),
                      backgroundColor: AppTheme.error,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                'Assign',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadData();
      widget.onDataChanged?.call();
    }
  }

  Future<void> _showDeleteAssignmentDialog(
    AssignmentModel assignment,
  ) async {
    final teacherName = _teachers
        .where((t) => t.id == assignment.teacherId)
        .firstOrNull
        ?.name ?? 'Unknown';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Remove Assignment',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Remove $teacherName from ${assignment.className} - ${assignment.subjectName}?',
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
              ),
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
              'Remove',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // ignore: use_build_context_synchronously
      final messenger = ScaffoldMessenger.of(context);
      final success = await SupabaseService.removeTeacherAssignment(
        assignment.id,
      );
      if (success && mounted) {
        _loadData();
        widget.onDataChanged?.call();
      } else if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to remove assignment. Check Supabase logs.',
              style: GoogleFonts.plusJakartaSans(fontSize: 13),
            ),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
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
            child: DropdownButton<String>(
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    return Column(
      children: [
        if (_isRefreshing)
          const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            color: AppTheme.primary,
            minHeight: 2,
          ),
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Expanded(
                child: Text(
                  'Assignments',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withAlpha(100),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showAssignDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            'Assign Teacher',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
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
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
            onRefresh: () => _loadData(showSpinner: false),
            child: _assignments.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Center(
                        child: EmptyStateWidget(
                          icon: Icons.assignment_outlined,
                          title: 'No Assignments Yet',
                          description:
                              'Assign teachers to classes and subjects to enable session creation.',
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _assignments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final a = _assignments[index];
                      return Container(
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
                                    a.className ?? 'Unknown Class',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${a.subjectName ?? "Unknown Subject"} · ${_teachers.firstWhere((t) => t.id == a.teacherId, orElse: () => const UserModel(id: "", name: "Unknown", email: "", role: "teacher")).name}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outlined,
                                color: AppTheme.error,
                                size: 18,
                              ),
                              tooltip: 'Remove Assignment',
                              onPressed: () =>
                                  _showDeleteAssignmentDialog(a),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
