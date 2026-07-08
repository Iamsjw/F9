import 'dart:convert' show utf8, jsonDecode, JsonEncoder;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'web_download_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'supabase_service.dart';


import '../models/attendance_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';

class _GridReport {
  final List<String> headers1; // Date headers
  final List<String> headers2; // Time headers
  final List<List<String>> rows; // Student rows
  _GridReport({required this.headers1, required this.headers2, required this.rows});
}

class CsvExportService {
  static String _formatDateOrdinal(DateTime dt) {
    final day = dt.day;
    String suffix = 'th';
    if (day == 1 || day == 21 || day == 31) {
      suffix = 'st';
    } else if (day == 2 || day == 22) {
      suffix = 'nd';
    } else if (day == 3 || day == 23) {
      suffix = 'rd';
    }
    
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final monthStr = months[dt.month - 1];
    return '${day.toString().padLeft(2, '0')}$suffix $monthStr, ${dt.year}';
  }

  static String _formatTimeSlot(SessionModel session) {
    if (session.lectureTime != null && session.lectureTime!.isNotEmpty) {
      return session.lectureTime!;
    }
    final start = session.startTime.toLocal();
    final end = session.endTime?.toLocal() ?? start.add(const Duration(hours: 1));
    
    String formatTime12h(DateTime dt) {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${hour.toString().padLeft(2, '0')}:$minute $ampm';
    }
    
    return '${formatTime12h(start)} - ${formatTime12h(end)}';
  }

  static String generateGridCsv({
    required String subjectName,
    required String className,
    required List<UserModel> students,
    required List<SessionModel> sessions,
    required List<AttendanceModel> attendance,
  }) {
    final buffer = StringBuffer();

    // Group attendance by student_id -> session_id -> status
    final attendanceMap = <String, Map<String, String>>{};
    for (final a in attendance) {
      if (!attendanceMap.containsKey(a.studentId)) {
        attendanceMap[a.studentId] = {};
      }
      attendanceMap[a.studentId]![a.sessionId] = a.status;
    }

    // Row 1: Roll No, Name, <Session Dates...>, Attendance
    buffer.write('Roll No,Name,');
    for (final s in sessions) {
      final dateStr = _formatDateOrdinal(s.startTime.toLocal());
      buffer.write('${_escapeCsvField(dateStr)},');
    }
    buffer.writeln('Attendance');

    // Row 2: (empty), (empty), <Session Times...>, (empty)
    buffer.write(',,');
    for (final s in sessions) {
      final timeStr = _formatTimeSlot(s);
      buffer.write('${_escapeCsvField(timeStr)},');
    }
    buffer.writeln('');

    // Student rows: RollNo, Name, P/empty..., "X / Y (Percentage)"
    for (final student in students) {
      final rollNoStr = student.rollNo ?? '';
      buffer.write('${_escapeCsvField(rollNoStr)},${_escapeCsvField(student.name)}');

      int presentCount = 0;
      final studentAtt = attendanceMap[student.id] ?? {};

      for (final s in sessions) {
        final status = studentAtt[s.id];
        if (status == 'present') {
          buffer.write(',P');
          presentCount++;
        } else {
          // Absent / empty cell
          buffer.write(',');
        }
      }

      // Summary: "X / Y (Percentage)" — no % sign, 2 decimal places
      final totalSessions = sessions.length;
      final percentage = totalSessions == 0 ? 0.0 : (presentCount / totalSessions) * 100;
      final summaryVal = '$presentCount / $totalSessions (${percentage.toStringAsFixed(2)})';
      buffer.writeln(',${_escapeCsvField(summaryVal)}');
    }

    return buffer.toString();
  }

  static Future<void> downloadGridCsv({
    required BuildContext context,
    required String subjectName,
    required String className,
    required List<UserModel> students,
    required List<SessionModel> sessions,
    required List<AttendanceModel> attendance,
  }) async {
    try {
      final csvContent = generateGridCsv(
        subjectName: subjectName,
        className: className,
        students: students,
        sessions: sessions,
        attendance: attendance,
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'grid_attendance_${_sanitizeFileName(subjectName)}_${_sanitizeFileName(className)}_$timestamp.csv';

      if (kIsWeb) {
        _downloadWeb(csvContent, fileName);
        _showSuccessSnackBar(context, fileName);
      } else {
        _showCsvPreview(context, csvContent, fileName);
      }
    } catch (e) {
      _showErrorSnackBar(context, e);
    }
  }

  static _GridReport? _tryParseGridCsv(String csvContent) {
    final lines = csvContent.split('\n');
    if (lines.isEmpty) return null;

    // Check if the first line is our grid header.
    // New format: first cell is empty, second cell is "Roll No".
    // Old/legacy format: first cell is "Roll No".
    final firstLine = lines[0].trim();
    final isNewFormat = firstLine.startsWith(', Roll No') || firstLine.startsWith(', "Roll No"');
    final isOldFormat = firstLine.startsWith('Roll No') || firstLine.startsWith('"Roll No"');
    if (!isNewFormat && !isOldFormat) {
      return null;
    }

    
    List<String> parseFields(String line) {
      final fields = <String>[];
      final buffer = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (c == ',' && !inQuotes) {
          fields.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(c);
        }
      }
      fields.add(buffer.toString().trim());
      return fields;
    }

    final List<List<String>> parsedRows = [];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      parsedRows.add(parseFields(trimmed));
    }

    if (parsedRows.length < 2) return null;

    final headers1 = parsedRows[0];
    final headers2 = parsedRows[1];
    final rows = parsedRows.sublist(2);

    return _GridReport(headers1: headers1, headers2: headers2, rows: rows);
  }

  static List<Map<String, String>> parseStudentsCsv(String csvContent) {
    final lines = csvContent.split('\n');
    final List<Map<String, String>> students = [];
    if (lines.isEmpty) return [];

    List<String> parseFields(String line) {
      final fields = <String>[];
      final buffer = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (c == ',' && !inQuotes) {
          fields.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(c);
        }
      }
      fields.add(buffer.toString().trim());
      return fields;
    }

    // Try to find the header row
    List<String>? headers;
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      final fields = parseFields(lines[i]);
      // Look for indicators of student fields
      final isHeader = fields.any((f) {
        final lower = f.toLowerCase();
        return lower.contains('roll') || lower.contains('name') || lower.contains('email');
      });
      if (isHeader) {
        headers = fields.map((h) => h.toLowerCase().replaceAll('_', '').replaceAll(' ', '')).toList();
        headerIndex = i;
        break;
      }
    }

    // Fallback headers if not found
    if (headers == null) {
      headers = ['rollno', 'name', 'email', 'password'];
    }

    final startLine = headerIndex + 1;
    for (int i = startLine; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final fields = parseFields(line);
      final student = <String, String>{};
      
      for (int j = 0; j < headers.length; j++) {
        if (j < fields.length) {
          final val = fields[j].replaceAll('"', '');
          final key = headers[j];
          student[key] = val;
        }
      }
      
      // Normalize fields
      // Roll No key
      final rollNoKey = student.keys.firstWhere(
        (k) => k.contains('roll'),
        orElse: () => 'roll_no',
      );
      final rollNo = student[rollNoKey] ?? '';
      
      // Name key
      String name = '';
      final firstNameKey = student.keys.firstWhere((k) => k.contains('first'), orElse: () => '');
      final lastNameKey = student.keys.firstWhere((k) => k.contains('last'), orElse: () => '');
      final nameKey = student.keys.firstWhere((k) => k == 'name' || k.contains('full'), orElse: () => '');
      
      if (firstNameKey.isNotEmpty) {
        name = '${student[firstNameKey] ?? ''} ${student[lastNameKey] ?? ''}'.trim();
      } else if (nameKey.isNotEmpty) {
        name = student[nameKey] ?? '';
      }
      
      // Email key
      final emailKey = student.keys.firstWhere((k) => k.contains('email'), orElse: () => 'email');
      final email = student[emailKey] ?? '';
      
      // Password key
      final passwordKey = student.keys.firstWhere((k) => k.contains('pass'), orElse: () => 'password');
      final password = student[passwordKey] ?? '';

      if (rollNo.isNotEmpty || name.isNotEmpty) {
        students.add({
          'roll_no': rollNo,
          'name': name,
          'email': email,
          'password': password,
        });
      }
    }

    return students;
  }

  static String _escapeCsvField(dynamic value) {
    if (value == null) return '""';
    final str = value.toString().trim();
    return '"${str.replaceAll('"', '""')}"';
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  static String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    return '$day/$month/${dt.year}';
  }

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static String generateCsv({
    required String subjectName,
    required String className,
    required SessionModel session,
    required List<AttendanceModel> attendance,
  }) {
    final buffer = StringBuffer();

    // Build attendance lookup: studentId -> status
    final attMap = <String, AttendanceModel>{};
    for (final a in attendance) {
      attMap[a.studentId] = a;
    }

    final dateStr = _formatDateOrdinal(session.startTime.toLocal());
    final timeStr = _formatTimeSlot(session);

    // Row 1: Roll No, Name, Date, Attendance
    buffer.writeln('Roll No,Name,${_escapeCsvField(dateStr)},Attendance');

    // Row 2: (empty), (empty), Time, (empty)
    buffer.writeln(',,${_escapeCsvField(timeStr)},');

    // Sort attendance by roll number / name
    final sorted = List<AttendanceModel>.from(attendance);
    sorted.sort((a, b) {
      final rollA = (a.studentName ?? '').toLowerCase();
      final rollB = (b.studentName ?? '').toLowerCase();
      return rollA.compareTo(rollB);
    });

    // Student rows: RollNo, Name, P/empty, "X / Y (Percentage)"
    for (final a in sorted) {
      final rollNo = ''; // AttendanceModel does not carry rollNo; leave blank
      final name = a.studentName ?? 'Unknown';
      final isPresent = a.status == 'present';
      final presentCount = isPresent ? 1 : 0;
      final summaryVal = '$presentCount / 1 (${(presentCount * 100).toStringAsFixed(2)})';
      buffer.writeln(
        '${_escapeCsvField(rollNo)},${_escapeCsvField(name)},${isPresent ? 'P' : ''},${_escapeCsvField(summaryVal)}',
      );
    }

    return buffer.toString();
  }

  static Future<void> downloadCsv({
    required BuildContext context,
    required String subjectName,
    required String className,
    required SessionModel session,
    required List<AttendanceModel> attendance,
  }) async {
    try {
      final csvContent = generateCsv(
        subjectName: subjectName,
        className: className,
        session: session,
        attendance: attendance,
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'attendance_${_sanitizeFileName(subjectName)}_${_sanitizeFileName(className)}_$timestamp.csv';

      if (kIsWeb) {
        _downloadWeb(csvContent, fileName);
        _showSuccessSnackBar(context, fileName);
      } else {
        _showCsvPreview(context, csvContent, fileName);
      }
    } catch (e) {
      _showErrorSnackBar(context, e);
    }
  }

  static Future<void> downloadCsvFromMap({
    required BuildContext context,
    required Map<String, dynamic> sessionData,
    required List<Map<String, dynamic>> attendanceData,
  }) async {
    try {
      final csvContent = _generateCsvFromMap(sessionData, attendanceData);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final subjectName =
          (sessionData['subjects'] as Map?)?['name'] ?? 'Unknown';
      final className =
          (sessionData['classes'] as Map?)?['name'] ?? 'Unknown';
      final fileName =
          'attendance_${_sanitizeFileName(subjectName)}_${_sanitizeFileName(className)}_$timestamp.csv';

      if (kIsWeb) {
        _downloadWeb(csvContent, fileName);
        _showSuccessSnackBar(context, fileName);
      } else {
        _showCsvPreview(context, csvContent, fileName);
      }
    } catch (e) {
      _showErrorSnackBar(context, e);
    }
  }

  static String _generateCsvFromMap(
    Map<String, dynamic> session,
    List<Map<String, dynamic>> attendance,
  ) {
    final buffer = StringBuffer();
    final startTime = session['start_time'] != null
        ? DateTime.parse(session['start_time'] as String)
        : DateTime.now();
    final endTime = session['end_time'] != null
        ? DateTime.parse(session['end_time'] as String)
        : null;
    final lectureTime = session['lecture_time'] as String?;

    // Build a temporary SessionModel-like object for _formatTimeSlot
    // by computing the time string directly here
    String timeStr;
    if (lectureTime != null && lectureTime.isNotEmpty) {
      timeStr = lectureTime;
    } else {
      final endDt = endTime ?? startTime.add(const Duration(hours: 1));
      String fmt12(DateTime dt) {
        final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        final m = dt.minute.toString().padLeft(2, '0');
        return '${h.toString().padLeft(2, '0')}:$m $ampm';
      }
      timeStr = '${fmt12(startTime.toLocal())} - ${fmt12(endDt.toLocal())}';
    }

    final dateStr = _formatDateOrdinal(startTime.toLocal());

    // Row 1: Roll No, Name, Date, Attendance
    buffer.writeln('Roll No,Name,${_escapeCsvField(dateStr)},Attendance');

    // Row 2: (empty), (empty), Time, (empty)
    buffer.writeln(',,${_escapeCsvField(timeStr)},');

    // Sort by student name
    final sorted = List<Map<String, dynamic>>.from(attendance);
    sorted.sort((a, b) {
      final nameA = (a['users']?['name'] as String? ?? '').toLowerCase();
      final nameB = (b['users']?['name'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    // Student rows: RollNo, Name, P/empty, "X / Y (Percentage)"
    for (final a in sorted) {
      final name = a['users']?['name'] as String? ?? 'Unknown';
      final rawStatus = a['status'] as String? ?? 'absent';
      final isPresent = rawStatus == 'present';
      final presentCount = isPresent ? 1 : 0;
      final summaryVal = '$presentCount / 1 (${(presentCount * 100).toStringAsFixed(2)})';
      buffer.writeln(',${_escapeCsvField(name)},${isPresent ? 'P' : ''},${_escapeCsvField(summaryVal)}');
    }

    return buffer.toString();
  }

  static Future<void> downloadAdminReportCsv({
    required BuildContext context,
    required String className,
    required List<dynamic> records,
  }) async {
    try {
      final csvContent = _generateAdminReportCsv(className, records);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'attendance_report_${_sanitizeFileName(className)}_$timestamp.csv';

      if (kIsWeb) {
        _downloadWeb(csvContent, fileName);
        _showSuccessSnackBar(context, fileName);
      } else {
        _showCsvPreview(context, csvContent, fileName);
      }
    } catch (e) {
      _showErrorSnackBar(context, e);
    }
  }

  static String _generateAdminReportCsv(
    String className,
    List<dynamic> records,
  ) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('UpasthitiX Attendance Report');
    buffer.writeln('');

    // Class details
    buffer.writeln('CLASS DETAILS');
    buffer.writeln('Class,${_escapeCsvField(className)}');
    buffer.writeln('Generated At,${_formatDate(DateTime.now())} ${_formatTime(DateTime.now())}');
    buffer.writeln('');

    // Summary
    final total = records.length;
    final presentCount = records.where((r) => r['status'] == 'present').length;
    final rate = total == 0 ? 0.0 : (presentCount / total) * 100;

    buffer.writeln('SUMMARY');
    buffer.writeln('Total Records,$total');
    buffer.writeln('Present,$presentCount');
    buffer.writeln('Attendance Rate,${rate.toStringAsFixed(1)}%');
    buffer.writeln('');

    // Attendance records
    buffer.writeln('ATTENDANCE RECORDS');
    buffer.writeln('No.,Student Name,Email,Subject,Status,Timestamp');
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      final name = r['users']?['name'] ?? 'Unknown';
      final email = r['users']?['email'] ?? 'N/A';
      final subject = r['sessions']?['subjects']?['name'] ?? 'Unknown';
      final status = r['status'] == 'present'
          ? 'Present'
          : (r['status'] == 'revoked' ? 'Revoked' : (r['status'] ?? 'Unknown'));
      final ts = r['timestamp'] != null
          ? '${_formatDate(DateTime.parse(r['timestamp'] as String))} ${_formatTime(DateTime.parse(r['timestamp'] as String))}'
          : 'N/A';

      buffer.writeln(
        '${i + 1},${_escapeCsvField(name)},${_escapeCsvField(email)},${_escapeCsvField(subject)},${_escapeCsvField(status)},${_escapeCsvField(ts)}',
      );
    }

    return buffer.toString();
  }

  static void _downloadWeb(String csvContent, String fileName) {
    downloadWebCsv(csvContent, fileName);
  }

  static void _showGridCsvPreview(
    BuildContext context,
    _GridReport report,
    String fileName,
    String csvContent,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grid Report Preview',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fileName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionHeader('Grid Preview (Scroll to view)'),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.shadowLight.withAlpha(25),
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Table(
                          defaultColumnWidth: const IntrinsicColumnWidth(),
                          border: TableBorder.all(
                            color: AppTheme.textMuted.withAlpha(30),
                            width: 1,
                          ),
                          children: [
                            // Date row
                            TableRow(
                              decoration: BoxDecoration(color: AppTheme.primary.withAlpha(20)),
                              children: report.headers1.map((h) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Text(
                                  h,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: AppTheme.textPrimary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )).toList(),
                            ),
                            // Time row
                            TableRow(
                              decoration: BoxDecoration(color: AppTheme.primary.withAlpha(10)),
                              children: report.headers2.map((h) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Text(
                                  h,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                    color: AppTheme.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )).toList(),
                            ),
                            // Data rows
                            ...report.rows.map((row) {
                              return TableRow(
                                children: row.map((cell) {
                                  final isP = cell.trim() == 'P';
                                  final isHeaderCol = row.indexOf(cell) < 2; // Roll No & Name cols
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Text(
                                      cell,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: (isP || isHeaderCol) ? FontWeight.w600 : FontWeight.normal,
                                        color: isP
                                            ? AppTheme.success
                                            : (isHeaderCol ? AppTheme.textPrimary : AppTheme.textSecondary),
                                      ),
                                      textAlign: isHeaderCol ? TextAlign.left : TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.textSecondary.withAlpha(50), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Close',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(
                        Icons.copy_all_rounded,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: csvContent));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'CSV copied to clipboard!',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12),
                            ),
                            backgroundColor: AppTheme.successSoft,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      label: Text(
                        'Copy',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.share_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: () async {
                        try {
                          final tempDir = await getTemporaryDirectory();
                          final file = File('${tempDir.path}/$fileName');
                          await file.writeAsString(csvContent, encoding: utf8);
                          await Share.shareXFiles(
                            [XFile(file.path)],
                            subject: fileName,
                          );
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Failed to share: $e'),
                                backgroundColor: AppTheme.errorSoft,
                              ),
                            );
                          }
                        }
                      },
                      label: Text(
                        'Share',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showCsvPreview(
    BuildContext context,
    String csvContent,
    String fileName,
  ) {
    // Check if it is a grid report first
    final gridReport = _tryParseGridCsv(csvContent);
    if (gridReport != null) {
      _showGridCsvPreview(context, gridReport, fileName, csvContent);
      return;
    }

    final report = _parseCsv(csvContent);
    final isAdminReport = report.headers.contains('Subject');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.analytics_outlined,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Preview',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fileName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (report.details.isNotEmpty) ...[
                        _buildSectionHeader('Details'),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.shadowLight.withAlpha(25),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: report.details.entries.map((e) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      e.key,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      e.value,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (report.summary.isNotEmpty) ...[
                        _buildSectionHeader('Summary'),
                        const SizedBox(height: 8),
                        Row(
                          children: report.summary.entries.map((e) {
                            return Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.primary.withAlpha(15),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      e.key,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      e.value,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryCyan,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildSectionHeader('Attendance Records (${report.records.length})'),
                      const SizedBox(height: 8),
                      if (report.records.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No records found.',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: report.records.length,
                          itemBuilder: (context, idx) {
                            final record = report.records[idx];
                            if (record.length < 4) return const SizedBox.shrink();

                            final name = record[1];
                            final email = record[2];
                            
                            final String status;
                            final String extra;
                            final bool isPresent;

                            if (isAdminReport && record.length >= 6) {
                              final subject = record[3];
                              status = record[4];
                              extra = 'Subject: $subject | ${record[5]}';
                              isPresent = status.toLowerCase() == 'present';
                            } else {
                              status = record[3];
                              extra = record[4];
                              isPresent = status.toLowerCase() == 'present';
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.shadowLight.withAlpha(15),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      record[0],
                                      style: GoogleFonts.plusJakartaSans(
                                        color: AppTheme.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppTheme.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          email,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppTheme.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          extra,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: AppTheme.textMuted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPresent ? AppTheme.successSoft : AppTheme.errorSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isPresent ? AppTheme.success : AppTheme.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.textSecondary.withAlpha(50), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'Close',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.primary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: Icon(
                        Icons.copy_all_rounded,
                        color: AppTheme.primary,
                        size: 16,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: csvContent));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'CSV copied to clipboard!',
                              style: GoogleFonts.plusJakartaSans(fontSize: 12),
                            ),
                            backgroundColor: AppTheme.successSoft,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                      label: Text(
                        'Copy',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.share_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      onPressed: () async {
                        try {
                          final tempDir = await getTemporaryDirectory();
                          final file = File('${tempDir.path}/$fileName');
                          await file.writeAsString(csvContent, encoding: utf8);
                          await Share.shareXFiles(
                            [XFile(file.path)],
                            subject: fileName,
                          );
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text('Failed to share: $e'),
                                backgroundColor: AppTheme.errorSoft,
                              ),
                            );
                          }
                        }
                      },
                      label: Text(
                        'Share/Save',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static _PreviewReport _parseCsv(String csvContent) {
    final lines = csvContent.split('\n');
    String title = 'Attendance Report';
    final details = <String, String>{};
    final summary = <String, String>{};
    final headers = <String>[];
    final records = <List<String>>[];

    String section = '';

    List<String> parseFields(String line) {
      final fields = <String>[];
      final buffer = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          inQuotes = !inQuotes;
        } else if (c == ',' && !inQuotes) {
          fields.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(c);
        }
      }
      fields.add(buffer.toString().trim());
      return fields;
    }

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('UpasthitiX')) {
        title = line;
        continue;
      }

      if (line == 'SESSION DETAILS' || line == 'CLASS DETAILS') {
        section = 'DETAILS';
        continue;
      } else if (line == 'SUMMARY') {
        section = 'SUMMARY';
        continue;
      } else if (line == 'ATTENDANCE RECORDS') {
        section = 'RECORDS';
        continue;
      }

      final fields = parseFields(line);
      if (fields.isEmpty) continue;

      if (section == 'DETAILS') {
        if (fields.length >= 2) {
          details[fields[0]] = fields[1];
        }
      } else if (section == 'SUMMARY') {
        if (fields.length >= 2) {
          summary[fields[0]] = fields[1];
        }
      } else if (section == 'RECORDS') {
        if (headers.isEmpty) {
          headers.addAll(fields);
        } else {
          records.add(fields);
        }
      }
    }

    return _PreviewReport(
      title: title,
      details: details,
      summary: summary,
      headers: headers,
      records: records,
    );
  }

  static Future<void> downloadFullBackupJson(BuildContext context) async {
    try {
      final data = await SupabaseService.fetchFullSystemBackupData();
      final jsonContent = const JsonEncoder.withIndent('  ').convert(data);
      final now = DateTime.now();
      final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'UpasthitiX_Full_Backup_$dateStr.json';

      if (kIsWeb) {
        downloadWebText(jsonContent, fileName, 'application/json;charset=utf-8');
        _showSuccessSnackBar(context, fileName);
      } else {
        _showJsonBackupPreview(context, jsonContent, fileName, data['summary'] as Map<String, dynamic>);
      }
    } catch (e) {
      _showErrorSnackBar(context, e);
    }
  }

  static void _showJsonBackupPreview(
    BuildContext context,
    String jsonContent,
    String fileName,
    Map<String, dynamic> summary,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.75,
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppTheme.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.backup_rounded, color: AppTheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Full System Backup',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          fileName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('Users: ${summary['users_count']}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
                    Text('Sessions: ${summary['sessions_count']}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
                    Text('Attendance: ${summary['attendance_count']}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    jsonContent,
                    style: GoogleFonts.firaCode(fontSize: 10, color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonContent));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Backup JSON copied to clipboard!', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                            backgroundColor: AppTheme.successSoft,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: Icon(Icons.copy_rounded, color: AppTheme.primary, size: 16),
                      label: Text('Copy JSON', style: GoogleFonts.plusJakartaSans(color: AppTheme.primary, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                      onPressed: () async {
                        try {
                          final dir = await getTemporaryDirectory();
                          final file = File('${dir.path}/$fileName');
                          await file.writeAsString(jsonContent, encoding: utf8);
                          await Share.shareXFiles([XFile(file.path)], text: 'UpasthitiX Backup JSON');
                        } catch (e) {
                          debugPrint('Error sharing backup: $e');
                        }
                      },
                      icon: const Icon(Icons.share_rounded, color: Colors.white, size: 16),
                      label: Text('Export / Share', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12)),
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

  static Future<void> showRestoreBackupDialog(
    BuildContext context, {
    VoidCallback? onRestored,
  }) async {
    final textController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        bool isLoading = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            Future<void> processRestore(String jsonRaw) async {
              setDialogState(() {
                isLoading = true;
                errorMessage = null;
              });

              try {
                final Map<String, dynamic> decoded = jsonDecode(jsonRaw) as Map<String, dynamic>;
                if (decoded['app'] != 'UpasthitiX' || !decoded.containsKey('tables')) {
                  throw Exception('Invalid backup format. Must be an UpasthitiX JSON backup file.');
                }

                final counts = await SupabaseService.restoreFullSystemBackup(decoded);

                if (dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Backup restored successfully! (${counts['users']} users, ${counts['sessions']} sessions, ${counts['attendance']} attendance records)',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                      backgroundColor: AppTheme.successSoft,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  onRestored?.call();
                }
              } catch (e) {
                setDialogState(() {
                  isLoading = false;
                  errorMessage = e.toString().replaceAll('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              backgroundColor: AppTheme.surfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(26),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.restore_page_rounded,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Restore System Backup',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select an UpasthitiX backup JSON file or paste backup content to restore the system database:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.surface,
                        foregroundColor: AppTheme.primary,
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.primary.withAlpha(80)),
                        ),
                      ),
                      icon: const Icon(Icons.file_upload_rounded, size: 18),
                      label: Text(
                        'Pick Backup .JSON File',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              try {
                                final result = await fp.FilePicker.pickFiles(
                                  type: fp.FileType.custom,
                                  allowedExtensions: ['json'],
                                  withData: true,
                                );
                                if (result != null && result.files.isNotEmpty) {
                                  final file = result.files.first;
                                  String? content;
                                  if (file.bytes != null) {
                                    content = utf8.decode(file.bytes!);
                                  } else if (file.path != null) {
                                    content = await File(file.path!).readAsString();
                                  }
                                  if (content != null && content.isNotEmpty) {
                                    textController.text = content;
                                    await processRestore(content);
                                  }
                                }
                              } catch (err) {
                                setDialogState(() {
                                  errorMessage = 'Error picking file: $err';
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'OR PASTE JSON',
                            style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      maxLines: 4,
                      enabled: !isLoading,
                      style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Paste backup JSON string here...',
                        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textMuted),
                        filled: true,
                        fillColor: AppTheme.background,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.errorSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          errorMessage!,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: isLoading
                      ? null
                      : () {
                          if (textController.text.trim().isNotEmpty) {
                            processRestore(textController.text.trim());
                          }
                        },
                  child: isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          'Restore Data',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static void _showSuccessSnackBar(BuildContext context, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'File downloaded: $fileName',
          style: GoogleFonts.plusJakartaSans(fontSize: 12),
        ),
        backgroundColor: AppTheme.successSoft,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Failed to download file: $e',
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

class _PreviewReport {
  final String title;
  final Map<String, String> details;
  final Map<String, String> summary;
  final List<String> headers;
  final List<List<String>> records;

  _PreviewReport({
    required this.title,
    required this.details,
    required this.summary,
    required this.headers,
    required this.records,
  });
}

