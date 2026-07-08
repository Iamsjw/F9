import '../../../core/app_export.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../services/csv_export_service.dart';

enum ReportViewMode {
  classWise,
  subjectWise,
  studentWise,
  combinedClassWise,
}

class ReportsTab extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;

  const ReportsTab({
    super.key,
    this.refreshNotifier,
  });

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  ReportViewMode _selectedMode = ReportViewMode.classWise;

  List<ClassModel> _classes = [];
  List<UserModel> _students = [];
  List<SubjectModel> _subjects = [];

  // Filter Selections
  String? _selectedClassId;
  List<String> _selectedCombinedClassIds = [];
  String? _selectedStudentId;
  String? _selectedSubjectId;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = true;
  bool _isGenerating = false;
  Map<String, dynamic>? _reportData;
  List<AttendanceModel> _studentIndividualHistory = [];

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onExternalRefresh);
    _loadInitialData();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadInitialData(showSpinner: false);
    }
  }

  Future<void> _loadInitialData({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
    try {
      final results = await Future.wait([
        SupabaseService.getClasses(),
        SupabaseService.getSubjects(),
        SupabaseService.listUsers(role: 'student'),
      ]);
      if (mounted) {
        setState(() {
          _classes = results[0] as List<ClassModel>;
          _subjects = results[1] as List<SubjectModel>;
          _students = results[2] as List<UserModel>;
          if (_classes.isNotEmpty) {
            _selectedClassId = _classes.first.id;
            _selectedCombinedClassIds = _classes.map((c) => c.id).toList();
          }
          _isLoading = false;
        });
        if (_selectedClassId != null) {
          _loadReport();
        }
      }
    } catch (e) {
      debugPrint('[ReportsTab] Failed to load initial data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReport() async {
    if (_selectedMode == ReportViewMode.classWise && _selectedClassId == null) return;
    if (_selectedMode == ReportViewMode.subjectWise && _selectedClassId == null) return;
    if (_selectedMode == ReportViewMode.combinedClassWise && _selectedCombinedClassIds.isEmpty) return;
    if (_selectedMode == ReportViewMode.studentWise && _selectedStudentId == null) return;

    setState(() {
      _isGenerating = true;
      _reportData = null;
      _studentIndividualHistory = [];
    });

    try {
      if (_selectedMode == ReportViewMode.studentWise) {
        if (_selectedStudentId != null) {
          final history = await SupabaseService.getStudentAttendanceReport(_selectedStudentId!);
          if (mounted) {
            setState(() {
              _studentIndividualHistory = history;
              _isGenerating = false;
            });
          }
        }
        return;
      }

      List<Map<String, dynamic>> records = [];
      if (_selectedMode == ReportViewMode.combinedClassWise) {
        records = await SupabaseService.getCombinedClassesAttendanceReport(
          _selectedCombinedClassIds,
          studentId: _selectedStudentId,
          subjectIds: _selectedSubjectId != null ? [_selectedSubjectId!] : null,
          startDate: _startDate,
          endDate: _endDate,
        );
      } else {
        records = await SupabaseService.getClassAttendanceReport(
          _selectedClassId!,
          studentId: _selectedStudentId,
          subjectIds: _selectedSubjectId != null ? [_selectedSubjectId!] : null,
          startDate: _startDate,
          endDate: _endDate,
        );
      }

      if (mounted) {
        setState(() {
          _reportData = {'records': records, 'total': records.length};
          _isGenerating = false;
        });
      }
    } catch (e) {
      debugPrint('[ReportsTab] Report generation error: $e');
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _downloadReportCsv() {
    final records = _reportData?['records'] as List? ?? [];
    if (records.isEmpty) return;

    String className = 'Report';
    if (_selectedMode == ReportViewMode.classWise || _selectedMode == ReportViewMode.subjectWise) {
      className = _classes.firstWhere((c) => c.id == _selectedClassId, orElse: () => ClassModel(id: '', name: 'Class')).name;
    } else if (_selectedMode == ReportViewMode.combinedClassWise) {
      className = 'Combined_Classes';
    }

    CsvExportService.downloadAdminReportCsv(
      context: context,
      className: className,
      records: records,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _classes.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header & Mode Switcher ──────────────────────────────────────
        Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assessment_rounded, color: AppTheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Master Attendance & Analytics',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildModeChip('Class-Wise', ReportViewMode.classWise, Icons.meeting_room_outlined),
                    const SizedBox(width: 8),
                    _buildModeChip('Subject-Wise', ReportViewMode.subjectWise, Icons.book_outlined),
                    const SizedBox(width: 8),
                    _buildModeChip('Student-Wise', ReportViewMode.studentWise, Icons.person_search_outlined),
                    const SizedBox(width: 8),
                    _buildModeChip('Combined Class-Wise', ReportViewMode.combinedClassWise, Icons.groups_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Filters Section ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_selectedMode == ReportViewMode.classWise) ...[
                Row(
                  children: [
                    Expanded(child: _buildClassDropdown()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSubjectDropdown(optional: true)),
                  ],
                ),
              ] else if (_selectedMode == ReportViewMode.subjectWise) ...[
                Row(
                  children: [
                    Expanded(child: _buildClassDropdown()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSubjectDropdown(optional: false)),
                  ],
                ),
              ] else if (_selectedMode == ReportViewMode.studentWise) ...[
                Row(
                  children: [
                    Expanded(child: _buildClassDropdown(onChangedCustom: (classId) {
                      setState(() {
                        _selectedClassId = classId;
                        _selectedStudentId = null;
                      });
                    })),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStudentDropdown()),
                  ],
                ),
              ] else if (_selectedMode == ReportViewMode.combinedClassWise) ...[
                _buildCombinedClassSelector(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildSubjectDropdown(optional: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildDateRangeSelector()),
                  ],
                ),
              ],

              if (_selectedMode != ReportViewMode.combinedClassWise) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildDateRangeSelector()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.analytics_rounded, color: Colors.white, size: 18),
                          label: Text(
                            'Generate Report',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: _isGenerating ? null : _loadReport,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
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
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.analytics_rounded, color: Colors.white, size: 18),
                    label: Text(
                      'Generate Combined Master Report',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: _isGenerating ? null : _loadReport,
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Report View Content ──────────────────────────────────────────
        if (_isGenerating)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.primary),
                  SizedBox(height: 12),
                  Text('Analyzing attendance data...', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ],
              ),
            ),
          )
        else if (_selectedMode == ReportViewMode.studentWise)
          Expanded(child: _buildStudentWiseView())
        else if (_reportData != null)
          Expanded(child: _buildMainReportView())
        else
          Expanded(
            child: Center(
              child: EmptyStateWidget(
                icon: Icons.insights_rounded,
                title: 'Select Options & Generate',
                description: 'Choose your desired Master Attendance mode and click Generate Report.',
              ),
            ),
          ),
      ],
    );
  }

  // ── Mode Switcher Chip Widget ──────────────────────────────────────────
  Widget _buildModeChip(String label, ReportViewMode mode, IconData icon) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMode = mode;
          _reportData = null;
          _studentIndividualHistory = [];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.backgroundVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.shadowLight,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dropdown Controls ──────────────────────────────────────────────────
  Widget _buildClassDropdown({Function(String?)? onChangedCustom}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Class', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedClassId,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textPrimary),
              items: _classes.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name))).toList(),
              onChanged: (val) {
                if (onChangedCustom != null) {
                  onChangedCustom(val);
                } else {
                  setState(() {
                    _selectedClassId = val;
                    _selectedStudentId = null;
                    _reportData = null;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectDropdown({required bool optional}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(optional ? 'Select Subject (Optional)' : 'Select Subject', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedSubjectId,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textPrimary),
              items: [
                if (optional) const DropdownMenuItem<String?>(value: null, child: Text('All Subjects')),
                ..._subjects.map((s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name))),
              ],
              onChanged: (val) => setState(() => _selectedSubjectId = val),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentDropdown() {
    final filteredStudents = _selectedClassId == null
        ? _students
        : _students.where((s) => s.classId == _selectedClassId).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Student', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedStudentId,
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textPrimary),
              hint: const Text('Choose a student...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              items: filteredStudents.map((s) {
                final rollStr = s.rollNo != null && s.rollNo!.isNotEmpty ? ' (${s.rollNo})' : '';
                return DropdownMenuItem<String?>(value: s.id, child: Text('${s.name}$rollStr'));
              }).toList(),
              onChanged: (val) => setState(() => _selectedStudentId = val),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCombinedClassSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Classes for Combined Report', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _classes.map((cls) {
            final isSelected = _selectedCombinedClassIds.contains(cls.id);
            return FilterChip(
              selected: isSelected,
              label: Text(cls.name, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppTheme.textSecondary)),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCombinedClassIds.add(cls.id);
                  } else {
                    _selectedCombinedClassIds.remove(cls.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateRangeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date Range (Optional)', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
            ),
            child: Row(
              children: [
                Icon(Icons.date_range, size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _startDate != null && _endDate != null
                        ? '${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}'
                        : 'Select dates...',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: _startDate != null ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_startDate != null)
                  GestureDetector(
                    onTap: () => setState(() {
                      _startDate = null;
                      _endDate = null;
                    }),
                    child: Icon(Icons.close, size: 14, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  // ── Main Master Report View (Class-wise, Subject-wise, Combined) ─────────
  Widget _buildMainReportView() {
    final records = _reportData?['records'] as List? ?? [];
    final total = records.length;

    if (total == 0) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.bar_chart_outlined,
          title: 'No Records Found',
          description: 'Try adjusting your filters or date range.',
        ),
      );
    }

    // Grouping & Analytics Calculations
    final presentCount = records.where((r) => r['status'] == 'present').length;
    final absentCount = records.where((r) => r['status'] == 'absent').length;
    final revokedCount = records.where((r) => r['status'] == 'revoked').length;
    final overallRate = total == 0 ? 0.0 : (presentCount / total) * 100;

    // Student Defaulter Calculation (< 75%)
    final studentStatsMap = <String, Map<String, dynamic>>{};
    for (final r in records) {
      final sId = r['student_id'] as String;
      final sName = r['users']?['name'] as String? ?? 'Unknown';
      final rollNo = r['users']?['roll_no'] as String? ?? '';
      if (!studentStatsMap.containsKey(sId)) {
        studentStatsMap[sId] = {'name': sName, 'roll_no': rollNo, 'present': 0, 'total': 0};
      }
      studentStatsMap[sId]!['total'] = (studentStatsMap[sId]!['total'] as int) + 1;
      if (r['status'] == 'present') {
        studentStatsMap[sId]!['present'] = (studentStatsMap[sId]!['present'] as int) + 1;
      }
    }

    final defaultersList = studentStatsMap.values.where((st) {
      final t = st['total'] as int;
      final p = st['present'] as int;
      final rate = t == 0 ? 0.0 : (p / t) * 100;
      return rate < 75.0;
    }).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // ── KPI Summary Header ─────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildKpiCard('Total Entries', '$total', Icons.assignment_outlined, AppTheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard('Present Rate', '${overallRate.toStringAsFixed(1)}%', Icons.check_circle_outline, AppTheme.success),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard('Defaulters (<75%)', '${defaultersList.length}', Icons.warning_amber_rounded, AppTheme.error),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Action Buttons ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Attendance Analysis',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
                  label: Text('Export CSV', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                  onPressed: _downloadReportCsv,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Defaulters Watchlist Banner ────────────────────────────
            if (defaultersList.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.errorSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.error.withAlpha(50)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Defaulters Watchlist (< 75% Attendance)',
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.error),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.error, borderRadius: BorderRadius.circular(6)),
                          child: Text('${defaultersList.length} Students', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: defaultersList.take(8).map((df) {
                        final p = df['present'] as int;
                        final t = df['total'] as int;
                        final rate = t == 0 ? 0.0 : (p / t) * 100;
                        return Chip(
                          backgroundColor: AppTheme.surfaceVariant,
                          avatar: CircleAvatar(backgroundColor: AppTheme.error, child: Text(df['name'][0], style: const TextStyle(fontSize: 10, color: Colors.white))),
                          label: Text('${df['name']} (${rate.toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary)),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Pie Chart Visual Breakdown ─────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Overall Status Distribution', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: PieChart(
                            PieChartData(
                              sections: [
                                PieChartSectionData(value: presentCount.toDouble(), title: 'Present', color: AppTheme.success, radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                PieChartSectionData(value: absentCount.toDouble(), title: 'Absent', color: AppTheme.error, radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                if (revokedCount > 0)
                                  PieChartSectionData(value: revokedCount.toDouble(), title: 'Revoked', color: AppTheme.warning, radius: 50, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                              centerSpaceRadius: 28,
                              sectionsSpace: 2,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LegendItem(color: AppTheme.success, label: 'Present', value: '$presentCount'),
                              const SizedBox(height: 8),
                              _LegendItem(color: AppTheme.error, label: 'Absent', value: '$absentCount'),
                              if (revokedCount > 0) ...[
                                const SizedBox(height: 8),
                                _LegendItem(color: AppTheme.warning, label: 'Revoked', value: '$revokedCount'),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Recent Attendance Records Table Preview ────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Attendance Log Preview (Most Recent)', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: records.length > 10 ? 10 : records.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.shadowLight.withAlpha(15)),
                itemBuilder: (ctx, idx) {
                  final r = records[idx];
                  final name = r['users']?['name'] ?? 'Unknown';
                  final subject = r['sessions']?['subjects']?['name'] ?? 'Unknown';
                  final status = r['status'] ?? 'absent';
                  final isP = status == 'present';

                  return ListTile(
                    dense: true,
                    title: Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: Text(subject, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isP ? AppTheme.successSoft : AppTheme.errorSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isP ? 'PRESENT' : 'ABSENT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isP ? AppTheme.success : AppTheme.error),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Student-Wise 360° Profile View ─────────────────────────────────────
  Widget _buildStudentWiseView() {
    if (_selectedStudentId == null) {
      return Center(
        child: EmptyStateWidget(
          icon: Icons.person_search_rounded,
          title: 'Select a Student',
          description: 'Choose a student from the dropdown above to view their 360° Master Attendance transcript.',
        ),
      );
    }

    final history = _studentIndividualHistory;
    final totalLectures = history.length;
    final presentCount = history.where((h) => h.status == 'present').length;
    final rate = totalLectures == 0 ? 0.0 : (presentCount / totalLectures) * 100;

    final selectedStudent = _students.firstWhere((s) => s.id == _selectedStudentId, orElse: () => UserModel(id: '', email: '', name: 'Student', role: 'student'));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Student Profile Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primary,
                    child: Text(selectedStudent.name.isNotEmpty ? selectedStudent.name[0] : 'S', style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedStudent.name, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        Text('Roll No: ${selectedStudent.rollNo ?? 'N/A'} • ${selectedStudent.email}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: rate >= 75 ? AppTheme.successSoft : AppTheme.errorSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${rate.toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: rate >= 75 ? AppTheme.success : AppTheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // History Log List
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Attendance Log History', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No attendance history recorded yet.', style: TextStyle(color: AppTheme.textMuted)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.shadowLight.withAlpha(25)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.shadowLight.withAlpha(15)),
                  itemBuilder: (ctx, idx) {
                    final h = history[idx];
                    final isP = h.status == 'present';
                    final dtStr = _formatDate(h.timestamp);

                    return ListTile(
                      dense: true,
                      leading: Icon(isP ? Icons.check_circle : Icons.cancel, color: isP ? AppTheme.success : AppTheme.error, size: 20),
                      title: Text('Session ID: ${h.sessionId.substring(0, 8)}...', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      subtitle: Text(dtStr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      trailing: Text(h.status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isP ? AppTheme.success : AppTheme.error)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helper KPI Card Widget ─────────────────────────────────────────────
  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
      ],
    );
  }
}
