import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/attendance_model.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/glass_card_widget.dart';

class SessionConfigWidget extends StatelessWidget {
  final List<ClassModel> classes;
  final List<SubjectModel> subjects;
  final List<AssignmentModel> assignments;
  final List<String> selectedClassIds;
  final String? selectedSubjectId;
  final String? lectureTime;
  final String? customLectureTime;
  final int durationSeconds;
  final String securityLevel;
  final int rssiThreshold;
  final void Function(List<String>) onClassesChanged;
  final void Function(String?) onSubjectChanged;
  final void Function(String?) onLectureTimeChanged;
  final void Function(String) onCustomLectureTimeChanged;
  final void Function(int) onDurationChanged;
  final void Function(String) onSecurityLevelChanged;
  final void Function(int) onRssiThresholdChanged;

  const SessionConfigWidget({
    super.key,
    required this.classes,
    required this.subjects,
    required this.assignments,
    required this.selectedClassIds,
    required this.selectedSubjectId,
    required this.lectureTime,
    required this.customLectureTime,
    required this.durationSeconds,
    required this.securityLevel,
    required this.rssiThreshold,
    required this.onClassesChanged,
    required this.onSubjectChanged,
    required this.onLectureTimeChanged,
    required this.onCustomLectureTimeChanged,
    required this.onDurationChanged,
    required this.onSecurityLevelChanged,
    required this.onRssiThresholdChanged,
  });

  // Filter classes and subjects based on teacher assignments
  List<ClassModel> get _assignedClasses {
    if (assignments.isEmpty) return classes;
    final assignedClassIds = assignments.map((a) => a.classId).toSet();
    return classes.where((c) => assignedClassIds.contains(c.id)).toList();
  }

  List<SubjectModel> get _assignedSubjects {
    if (assignments.isEmpty) return subjects;
    if (selectedClassIds.isEmpty) {
      final assignedSubjectIds = assignments.map((a) => a.subjectId).toSet();
      return subjects.where((s) => assignedSubjectIds.contains(s.id)).toList();
    }
    final selectedSet = selectedClassIds.toSet();
    final assignedSubjectIds = assignments
        .where((a) => selectedSet.contains(a.classId))
        .map((a) => a.subjectId)
        .toSet();
    return subjects.where((s) => assignedSubjectIds.contains(s.id)).toList();
  }

  Color _securityColor(String level) {
    switch (level) {
      case 'HIGH':
        return AppTheme.success;
      case 'LOW':
        return AppTheme.warning;
      default:
        return AppTheme.warning;
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0 && s > 0) return '${m}m ${s}s';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  // Magnet snap calculation for 30s, 1m (60s), 2m (120s), 3m (180s), 4m (240s), 5m (300s)
  int _applyMagnetSnap(double rawValue) {
    final val = rawValue.toInt();
    const magnetPoints = [30, 60, 120, 180, 240, 300];
    const snapDistance = 7; // Within +/-7 seconds, snap like a magnet!

    for (final point in magnetPoints) {
      if ((val - point).abs() <= snapDistance) {
        return point;
      }
    }
    return val;
  }

  Widget _buildDurationSelector(BuildContext context) {
    final presets = [
      {'label': '30s', 'value': 30},
      {'label': '1m', 'value': 60},
      {'label': '2m', 'value': 120},
      {'label': '3m', 'value': 180},
      {'label': '4m', 'value': 240},
      {'label': '5m', 'value': 300},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Duration',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMuted,
                letterSpacing: 0.4,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(38),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatDuration(durationSeconds),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Magnet Duration Preset Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: presets.map((preset) {
              final val = preset['value'] as int;
              final label = preset['label'] as String;
              final isSelected = durationSeconds == val;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onDurationChanged(val),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withAlpha(50)
                          : AppTheme.surface.withAlpha(13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.shadowLight.withAlpha(25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.shadowLight.withAlpha(25),
            thumbColor: AppTheme.primary,
            overlayColor: AppTheme.primary.withAlpha(38),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            valueIndicatorColor: AppTheme.primary,
            valueIndicatorTextStyle: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Slider(
            value: durationSeconds.toDouble(),
            min: 15,
            max: 300,
            divisions: 285,
            label: _formatDuration(durationSeconds),
            onChanged: (v) => onDurationChanged(_applyMagnetSnap(v)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '15s',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
              Text(
                '5m',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClassChipSelector(BuildContext context) {
    final assigned = _assignedClasses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Classes (Select multiple for combined lecture)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        if (assigned.isEmpty)
          Text(
            'No classes assigned to you.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.error,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: assigned.map((c) {
              final isSelected = selectedClassIds.contains(c.id);
              return GestureDetector(
                onTap: () {
                  final newSelection = List<String>.from(selectedClassIds);
                  if (isSelected) {
                    newSelection.remove(c.id);
                  } else {
                    newSelection.add(c.id);
                  }
                  onClassesChanged(newSelection);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primary.withAlpha(38)
                        : AppTheme.surface.withAlpha(13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : AppTheme.shadowLight.withAlpha(25),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        c.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildTimeSlotSelector(BuildContext context) {
    final standardSlots = [
      '08:30 - 09:30',
      '09:30 - 10:30',
      '10:30 - 11:30',
      '11:30 - 12:30',
      '12:30 - 01:30',
      '01:30 - 02:30',
      '02:30 - 03:30',
      '03:30 - 04:30',
      'Custom'
    ];

    final isCustom = lectureTime == 'Custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lecture Time Slot',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF130E26).withAlpha(216),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0x33FFFFFF),
              width: 1.0,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: lectureTime,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Select time slot...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ),
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textMuted,
              ),
              items: standardSlots.map((slot) {
                return DropdownMenuItem<String>(
                  value: slot,
                  child: Text(
                    slot,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onLectureTimeChanged,
            ),
          ),
        ),
        if (isCustom) ...[
          const SizedBox(height: 10),
          TextFormField(
            initialValue: customLectureTime,
            style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Enter Custom Lecture Time (e.g. 10:00 - 11:30)',
              labelStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0x33FFFFFF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
            ),
            onChanged: onCustomLectureTimeChanged,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassCardWidget(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.tune_rounded,
            label: 'Session Configuration',
          ),
          const SizedBox(height: 20),
          _buildClassChipSelector(context),
          const SizedBox(height: 18),
          _buildDropdown(
            label: 'Subject',
            icon: Icons.book_outlined,
            value: selectedSubjectId,
            items: _assignedSubjects
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: onSubjectChanged,
            hint: 'Select subject',
          ),
          const SizedBox(height: 18),
          _buildTimeSlotSelector(context),
          const SizedBox(height: 20),
          _buildDurationSelector(context),
          const SizedBox(height: 20),
          const _SectionHeader(
            icon: Icons.security_outlined,
            label: 'Security Level',
          ),
          const SizedBox(height: 12),
          Row(
            children: ['LOW', 'HIGH'].map((level) {
              final isSelected = securityLevel == level;
              final color = _securityColor(level);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: level == 'LOW' ? 8 : 0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 56,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withAlpha(38)
                          : AppTheme.surface.withAlpha(13),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? color.withAlpha(128)
                            : AppTheme.shadowLight.withAlpha(25),
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onSecurityLevelChanged(level),
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            level == 'HIGH'
                                ? Icons.bluetooth_searching_rounded
                                : Icons.pin_outlined,
                            color: isSelected ? color : AppTheme.textMuted,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            level,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? color : AppTheme.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (securityLevel == 'HIGH') ...[
            const SizedBox(height: 20),
            _SectionHeader(
              icon: Icons.signal_cellular_alt_rounded,
              label: 'RSSI Threshold: $rssiThreshold dBm',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '-65',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.primary,
                      inactiveTrackColor: AppTheme.shadowLight.withAlpha(25),
                      thumbColor: AppTheme.primary,
                      overlayColor: AppTheme.primary.withAlpha(38),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: Slider(
                      value: rssiThreshold.abs().toDouble().clamp(65.0, 100.0),
                      min: 65,
                      max: 100,
                      divisions: 35,
                      label: '-${rssiThreshold.abs()} dBm',
                      onChanged: (v) => onRssiThresholdChanged(-v.toInt()),
                    ),
                  ),
                ),
                Text(
                  '-100',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Close (~3m)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  Text(
                    'Far (~15m)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
    required String hint,
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
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF130E26).withAlpha(216),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0x33FFFFFF),
              width: 1.0,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  hint,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ),
              isExpanded: true,
              dropdownColor: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textMuted,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}
