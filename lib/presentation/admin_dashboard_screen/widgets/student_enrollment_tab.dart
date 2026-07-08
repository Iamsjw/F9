import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/csv_export_service.dart';
import '../../../core/app_export.dart';

class StudentEnrollmentTab extends StatefulWidget {
  const StudentEnrollmentTab({super.key});

  @override
  State<StudentEnrollmentTab> createState() => _StudentEnrollmentTabState();
}

class _StudentEnrollmentTabState extends State<StudentEnrollmentTab> {
  List<UserModel> _students = [];
  List<ClassModel> _classes = [];
  bool _isLoading = true;
  String _filter = 'all'; // 'all', 'enrolled', 'unenrolled'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SupabaseService.listUsers(role: 'student'),
        SupabaseService.getClasses(),
      ]);
      if (mounted) {
        setState(() {
          _students = results[0] as List<UserModel>;
          _classes = results[1] as List<ClassModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<UserModel> get _filteredStudents {
    switch (_filter) {
      case 'enrolled':
        return _students.where((s) => s.classId != null).toList();
      case 'unenrolled':
        return _students.where((s) => s.classId == null).toList();
      default:
        return _students;
    }
  }

  Future<void> _showAddStudentDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    final rollNoController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Add Student',
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
              TextFormField(
                controller: rollNoController,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Roll Number (Alphanumeric)',
                  labelStyle: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textMuted,
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Roll number required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nameController,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textMuted,
                  ),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: emailController,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textMuted,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email required';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Valid email required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: GoogleFonts.plusJakartaSans(
                    color: AppTheme.textMuted,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password required';
                  if (v.length < 6) return 'Min 6 characters';
                  return null;
                },
              ),
            ],
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
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final user = await SupabaseService.createUser(
                    email: emailController.text.trim(),
                    password: passwordController.text,
                    name: nameController.text.trim(),
                    role: 'student',
                    rollNo: rollNoController.text.trim().toUpperCase(),
                  );
                  if (user != null && mounted) {
                    Navigator.pop(ctx, true);
                  }
                } catch (err) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to create student: $err',
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
            },
            child: Text(
              'Add',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == true) _loadData();

    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    rollNoController.dispose();
  }

  Future<void> _showEditStudentDialog(UserModel student) async {
    final nameController = TextEditingController(text: student.name);
    final emailController = TextEditingController(text: student.email);
    final rollNoController = TextEditingController(text: student.rollNo);
    String? selectedClassId = student.classId;
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
            'Edit Student',
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
                TextFormField(
                  controller: rollNoController,
                  style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Roll Number (Alphanumeric)',
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Roll number required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameController,
                  style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textMuted,
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email required';
                    if (!v.contains('@') || !v.contains('.')) {
                      return 'Valid email required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Class dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class (Optional)',
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
                          value: selectedClassId,
                          hint: Text(
                            'Select class...',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppTheme.textDisabled,
                            ),
                          ),
                          isExpanded: true,
                          dropdownColor: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      ),
                    ),
                  ],
                ),
              ],
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
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  // ignore: use_build_context_synchronously
                  final messenger = ScaffoldMessenger.of(context);
                  final success = await SupabaseService.updateUser(
                    student.id,
                    data: {
                      'name': nameController.text.trim(),
                      'email': emailController.text.trim(),
                      'class_id': selectedClassId,
                      'roll_no': rollNoController.text.trim().toUpperCase(),
                    },
                  );
                  if (success && mounted) {
                    // ignore: use_build_context_synchronously
                    Navigator.pop(ctx, true);
                  } else if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to update student. Check Supabase logs.',
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
              },
              child: Text(
                'Save',
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

    if (result == true) _loadData();
    nameController.dispose();
    emailController.dispose();
    rollNoController.dispose();
  }

  Future<void> _importStudentsFromCsv() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String csvContent = '';

      if (kIsWeb) {
        if (file.bytes != null) {
          csvContent = utf8.decode(file.bytes!);
        } else {
          throw Exception('File bytes are empty on web');
        }
      } else {
        if (file.path != null) {
          final ioFile = File(file.path!);
          csvContent = await ioFile.readAsString();
        } else {
          throw Exception('File path is empty on mobile');
        }
      }

      if (csvContent.isEmpty) {
        throw Exception('CSV file is empty');
      }

      final parsed = CsvExportService.parseStudentsCsv(csvContent);
      if (parsed.isEmpty) {
        throw Exception('No students could be parsed from the CSV. Please check columns.');
      }

      // Show confirmation dialog with parsed student count and class mapping
      String? selectedClassId;
      final formKey = GlobalKey<FormState>();
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx2, setDialogState) => AlertDialog(
            backgroundColor: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Bulk Import Students',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found ${parsed.length} student records in the CSV.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Class to enroll these students (Optional):',
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
                        value: selectedClassId,
                        hint: Text(
                          'Select class...',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTheme.textDisabled,
                          ),
                        ),
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Note: Roll numbers will be used for logins if no emails are provided. Default passwords will be set if missing in CSV.',
                    style: GoogleFonts.plusJakartaSans(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
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
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Import',
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

      if (confirm != true) return;

      // Start import process
      setState(() => _isLoading = true);
      
      int successCount = 0;
      int failureCount = 0;
      
      for (final s in parsed) {
        final rollNo = s['roll_no'] ?? '';
        final name = s['name'] ?? '';
        
        // Auto-generate email if empty: <roll_no>@upasthitix.com
        String email = s['email'] ?? '';
        if (email.isEmpty && rollNo.isNotEmpty) {
          email = '${rollNo.toLowerCase()}@upasthitix.com';
        }
        
        // Default password if empty: roll number or default pass
        String password = s['password'] ?? '';
        if (password.isEmpty) {
          password = rollNo.isNotEmpty ? rollNo : 'student123';
        }
        if (password.length < 6) {
          password = password.padRight(6, '1');
        }

        if (email.isEmpty || name.isEmpty) {
          failureCount++;
          continue;
        }

        try {
          final user = await SupabaseService.createUser(
            email: email.trim(),
            password: password,
            name: name.trim(),
            role: 'student',
            rollNo: rollNo.toUpperCase(),
            classId: selectedClassId,
          );
          if (user != null) {
            successCount++;
          } else {
            failureCount++;
          }
        } catch (e) {
          failureCount++;
        }

        // Paced delay (350ms) between creations to prevent Supabase auth rate-limit spikes
        await Future.delayed(const Duration(milliseconds: 350));
      }

      _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import completed: $successCount succeeded, $failureCount failed.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            backgroundColor: successCount > 0 ? const Color(0xFF065F46) : const Color(0xFF991B1B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error during bulk import: $e',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF991B1B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showDeleteStudentDialog(UserModel student) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Student',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete ${student.name}? This action cannot be undone.',
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
              'Delete',
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
      final success = await SupabaseService.deleteUser(student.id);
      if (success && mounted) {
        _loadData();
      } else if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete student. Check Supabase logs.',
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

  Future<void> _showEnrollDialog(UserModel student) async {
    String? classId = student.classId;
    final formKey = GlobalKey<FormState>();

    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState2) => AlertDialog(
            backgroundColor: AppTheme.surfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              student.classId != null ? 'Change Class' : 'Enroll Student',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    student.email,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Class',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
                        value: classId,
                        isExpanded: true,
                        hint: Text(
                          'Choose a class...',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppTheme.textMuted,
                          ),
                        ),
                        items: _classes.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              c.name,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState2(() => classId = value);
                        },
                      ),
                    ),
                  ),
                ],
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
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: classId == null
                    ? null
                    : () async {
                        // ignore: use_build_context_synchronously
                        final messenger = ScaffoldMessenger.of(context);
                        final success =
                            await SupabaseService.enrollStudentInClass(
                          studentId: student.id,
                          classId: classId!,
                        );
                        if (success && mounted) {
                          // ignore: use_build_context_synchronously
                          Navigator.pop(
                            ctx, // ignore: use_build_context_synchronously
                            true,
                          );
                        } else if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to enroll student. Check Supabase logs.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                ),
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
                  student.classId != null ? 'Update' : 'Enroll',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((result) {
      if (result == true) _loadData();
    });
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
        // Header
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
          child: Row(
            children: [
              Text(
                'Students',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_students.length}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _showAddStudentDialog,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  'Add Student',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _importStudentsFromCsv,
                icon: Icon(Icons.upload_file_rounded, size: 16, color: AppTheme.primary),
                label: Text(
                  'Bulk Import',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filter chips
              _FilterChip(
                label: 'All',
                isSelected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Enrolled',
                isSelected: _filter == 'enrolled',
                onTap: () => setState(() => _filter = 'enrolled'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Unenrolled',
                isSelected: _filter == 'unenrolled',
                onTap: () => setState(() => _filter = 'unenrolled'),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _filteredStudents.isEmpty
              ? Center(
                  child: EmptyStateWidget(
                    icon: Icons.people_outline_rounded,
                    title: _filter == 'unenrolled'
                        ? 'All Students Enrolled'
                        : 'No Students Yet',
                    description: _filter == 'unenrolled'
                        ? 'All students are assigned to a class.'
                        : 'Add students to the system first.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredStudents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final isEnrolled = student.classId != null;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isEnrolled
                              ? AppTheme.success.withAlpha(40)
                              : AppTheme.warning.withAlpha(40),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isEnrolled
                                  ? AppTheme.successSoft
                                  : AppTheme.warningSoft,
                            ),
                            child: Center(
                              child: Text(
                                student.name.isNotEmpty
                                    ? student.name[0].toUpperCase()
                                    : 'S',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isEnrolled
                                      ? AppTheme.success
                                      : AppTheme.warning,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      student.name,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    if (student.rollNo != null && student.rollNo!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary.withAlpha(20),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          student.rollNo!,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryCyan,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  student.email,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                if (isEnrolled)
                                  Text(
                                    'Class: ${_classes.firstWhere((c) => c.id == student.classId, orElse: () => const ClassModel(id: "", name: "Unknown")).name}',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                else
                                  Text(
                                    'Not enrolled',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.warning,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              color: AppTheme.primary,
                              size: 18,
                            ),
                            tooltip: 'Edit Student',
                            onPressed: () =>
                                _showEditStudentDialog(student),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outlined,
                              color: AppTheme.error,
                              size: 18,
                            ),
                            tooltip: 'Delete Student',
                            onPressed: () =>
                                _showDeleteStudentDialog(student),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () => _showEnrollDialog(student),
                            style: TextButton.styleFrom(
                              foregroundColor: isEnrolled
                                  ? AppTheme.primary
                                  : AppTheme.success,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                            ),
                            child: Text(
                              isEnrolled ? 'Change' : 'Enroll',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(26)
              : Colors.transparent,
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
            fontWeight: FontWeight.w600,
            color: isSelected ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
