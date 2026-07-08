import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../../services/csv_export_service.dart';
import '../../../core/app_export.dart';

class ClassesTab extends StatefulWidget {
  final ValueNotifier<int>? refreshNotifier;
  final VoidCallback? onDataChanged;

  const ClassesTab({
    super.key,
    this.refreshNotifier,
    this.onDataChanged,
  });

  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  List<ClassModel> _classes = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Student loading and caching per class
  final Map<String, List<UserModel>> _studentsMap = {};
  final Map<String, bool> _loadingStudentsMap = {};
  final Map<String, bool> _expandedClasses = {};

  @override
  void initState() {
    super.initState();
    widget.refreshNotifier?.addListener(_onExternalRefresh);
    _loadClasses();
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadClasses(showSpinner: false);
    }
  }

  Future<void> _loadClasses({bool showSpinner = true}) async {
    if (showSpinner && _classes.isEmpty) {
      setState(() => _isLoading = true);
    } else {
      setState(() => _isRefreshing = true);
    }
    try {
      debugPrint('[UI] ClassesTab._loadClasses() called');
      final classes = await SupabaseService.getClasses();
      debugPrint('[UI] ClassesTab._loadClasses() got ${classes.length} classes');
      if (mounted) {
        setState(() {
          _classes = classes;
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[UI] ClassesTab._loadClasses() failed: $e');
      debugPrint('[UI] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadStudentsForClass(String classId) async {
    if (mounted) {
      setState(() {
        _loadingStudentsMap[classId] = true;
      });
    }
    try {
      final students = await SupabaseService.getStudentsByClass(classId);
      if (mounted) {
        setState(() {
          _studentsMap[classId] = students;
          _loadingStudentsMap[classId] = false;
        });
      }
    } catch (e) {
      debugPrint('[UI] ClassesTab._loadStudentsForClass() failed: $e');
      if (mounted) {
        setState(() {
          _loadingStudentsMap[classId] = false;
        });
      }
    }
  }

  void _toggleExpand(String classId) {
    final wasExpanded = _expandedClasses[classId] ?? false;
    setState(() {
      _expandedClasses[classId] = !wasExpanded;
    });

    if (!wasExpanded && _studentsMap[classId] == null) {
      _loadStudentsForClass(classId);
    }
  }

  Future<void> _showAddClassDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Add Class',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Class Name',
              labelStyle: GoogleFonts.plusJakartaSans(
                color: AppTheme.textMuted,
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Name required' : null,
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
                final result = await SupabaseService.createClass(
                  controller.text.trim(),
                );
                if (result != null && mounted) {
                  Navigator.pop(ctx, true);
                } else if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to create class. Check Supabase logs.',
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

    if (result == true) {
      _loadClasses();
      widget.onDataChanged?.call();
    }
    controller.dispose();
  }

  Future<void> _showEditClassDialog(ClassModel classModel) async {
    final controller = TextEditingController(text: classModel.name);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit Class',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            style: GoogleFonts.plusJakartaSans(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Class Name',
              labelStyle: GoogleFonts.plusJakartaSans(
                color: AppTheme.textMuted,
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Name required' : null,
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
                final success = await SupabaseService.updateClass(
                  classModel.id,
                  controller.text.trim(),
                );
                if (success && mounted) {
                  Navigator.pop(ctx, true);
                } else if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to update class. Check Supabase logs.',
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
    );

    if (result == true) {
      _loadClasses();
      widget.onDataChanged?.call();
    }
    controller.dispose();
  }

  Future<void> _showDeleteClassDialog(ClassModel classModel) async {
    final isAuthorized = await AdminPinChallengeDialog.show(
      context,
      actionDescription: 'delete class "${classModel.name}"',
    );
    if (!isAuthorized) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Class',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${classModel.name}"? This action cannot be undone and will un-enroll students.',
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
      final messenger = ScaffoldMessenger.of(context);
      final success = await SupabaseService.deleteClass(classModel.id);
      if (success && mounted) {
        _loadClasses();
        widget.onDataChanged?.call();
      } else if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete class. Check Supabase logs.',
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

  Future<void> _showEmptyClassDialog(ClassModel classModel) async {
    final isAuthorized = await AdminPinChallengeDialog.show(
      context,
      actionDescription: 'empty all students from "${classModel.name}"',
    );
    if (!isAuthorized) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
            const SizedBox(width: 8),
            Text(
              'Empty Class',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all students from "${classModel.name}" completely? This action cannot be undone and will delete all their data.',
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
              'Empty Class',
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
      setState(() {
        _loadingStudentsMap[classModel.id] = true;
      });
      final messenger = ScaffoldMessenger.of(context);
      final success = await SupabaseService.emptyClass(classModel.id);
      if (success && mounted) {
        _loadStudentsForClass(classModel.id);
        widget.onDataChanged?.call();
      } else if (mounted) {
        setState(() {
          _loadingStudentsMap[classModel.id] = false;
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to empty class. Check Supabase logs.',
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

  Future<void> _showAddStudentDialog(ClassModel classModel) async {
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
          'Add Student to ${classModel.name}',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
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
                  if (user != null) {
                    await SupabaseService.enrollStudentInClass(
                      studentId: user.id,
                      classId: classModel.id,
                    );
                    if (mounted) Navigator.pop(ctx, true);
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

    if (result == true) {
      _loadStudentsForClass(classModel.id);
    }
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    rollNoController.dispose();
  }

  Future<void> _showEditStudentDialog(UserModel student, ClassModel currentClass) async {
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Text(
                    'Class',
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

    if (result == true) {
      _loadStudentsForClass(currentClass.id);
      if (selectedClassId != null && selectedClassId != currentClass.id) {
        _loadStudentsForClass(selectedClassId!);
      }
    }
    nameController.dispose();
    emailController.dispose();
    rollNoController.dispose();
  }

  Future<void> _showDeleteStudentDialog(UserModel student, ClassModel classModel) async {
    final isAuthorized = await AdminPinChallengeDialog.show(
      context,
      actionDescription: 'delete student "${student.name}"',
    );
    if (!isAuthorized) return;

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
      final messenger = ScaffoldMessenger.of(context);
      final success = await SupabaseService.deleteUser(student.id);
      if (success && mounted) {
        _loadStudentsForClass(classModel.id);
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

  Future<void> _importStudentsFromCsv(ClassModel classModel) async {
    final isAuthorized = await AdminPinChallengeDialog.show(
      context,
      actionDescription: 'bulk import students to "${classModel.name}"',
    );
    if (!isAuthorized) return;

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

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Bulk Import Students',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          content: Column(
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
              const SizedBox(height: 8),
              Text(
                'All imported students will be automatically enrolled in ${classModel.name}.',
                style: GoogleFonts.plusJakartaSans(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
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
      );

      if (confirm != true) return;

      setState(() {
        _loadingStudentsMap[classModel.id] = true;
      });

      double progress = 0.0;
      int current = 0;
      int total = parsed.length;
      int successCount = 0;
      int failureCount = 0;
      String currentName = '';
      bool importDone = false;
      StateSetter? dialogSetState;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              dialogSetState = setDialogState;
              
              return PopScope(
                canPop: false,
                child: AlertDialog(
                  backgroundColor: const Color(0xFF16132D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: Colors.white.withOpacity(0.08),
                      width: 1,
                    ),
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.85,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: importDone
                                ? (failureCount == 0 ? AppTheme.success.withAlpha(20) : AppTheme.warning.withAlpha(20))
                                : AppTheme.primaryCyan.withAlpha(20),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: importDone
                                ? Icon(
                                    failureCount == 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                                    color: failureCount == 0 ? AppTheme.success : AppTheme.warning,
                                    size: 28,
                                  )
                                : const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppTheme.primaryCyan,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          importDone ? 'Import Completed' : 'Importing Students',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          importDone
                              ? 'Finished processing all $total records'
                              : 'Processing $current of $total...',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (currentName.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            currentName,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 20),
                        
                        // Progress Bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            children: [
                              Container(
                                height: 8,
                                color: Colors.white.withOpacity(0.05),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 8,
                                width: (MediaQuery.of(context).size.width * 0.7) * progress,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: const LinearGradient(
                                    colors: [AppTheme.primaryCyan, AppTheme.primaryBlue],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.success.withAlpha(30)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$successCount',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                  Text(
                                    'Succeeded',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.error.withAlpha(15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.error.withAlpha(30)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$failureCount',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                  Text(
                                    'Failed',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (importDone) ...[
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                elevation: 0,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'Done',
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      // Brief delay for the dialog to slide in and register its state controller
      await Future.delayed(const Duration(milliseconds: 150));

      try {
        int idx = 0;
        for (final s in parsed) {
          idx++;
          final rollNo = s['roll_no'] ?? s['rollno'] ?? '';
          final name = s['name'] ?? '';

          current = idx;
          progress = current / total;
          currentName = 'Creating: $name (${rollNo.isNotEmpty ? rollNo : "No Roll No"})';
          dialogSetState?.call(() {});

          String email = s['email'] ?? '';
          if (email.isEmpty && rollNo.isNotEmpty) {
            email = '${rollNo.toLowerCase()}@upasthitix.com';
          }

          String password = s['password'] ?? '';
          if (password.isEmpty) {
            password = rollNo.isNotEmpty ? rollNo : 'student123';
          }
          if (password.length < 6) {
            password = password.padRight(6, '1');
          }

          if (email.isEmpty || name.isEmpty) {
            failureCount++;
            dialogSetState?.call(() {});
            continue;
          }

          try {
            final user = await SupabaseService.createUser(
              email: email.trim(),
              password: password,
              name: name.trim(),
              role: 'student',
              rollNo: rollNo.toUpperCase(),
              classId: classModel.id,
            );
            if (user != null) {
              successCount++;
            } else {
              failureCount++;
            }
          } catch (e) {
            failureCount++;
          }

          dialogSetState?.call(() {});

          // Paced delay (350ms) between creations to prevent Supabase auth rate-limit spikes
          await Future.delayed(const Duration(milliseconds: 350));
        }
      } catch (e) {
        currentName = 'Error during import: $e';
      } finally {
        importDone = true;
        progress = 1.0;
        dialogSetState?.call(() {});

        setState(() {
          _loadingStudentsMap[classModel.id] = false;
        });
        _loadStudentsForClass(classModel.id);
        widget.onDataChanged?.call();
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
              Text(
                'Classes',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
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
                    onTap: _showAddClassDialog,
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
                            'Add Class',
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
        // List of expandable class cards
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
            onRefresh: () => _loadClasses(showSpinner: false),
            child: _classes.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Center(
                        child: EmptyStateWidget(
                          icon: Icons.class_outlined,
                          title: 'No Classes Yet',
                          description:
                              'Add classes to assign teachers and enroll students.',
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _classes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final classModel = _classes[index];
                      final isExpanded = _expandedClasses[classModel.id] ?? false;
                      final students = _studentsMap[classModel.id];
                      final isLoadingStudents = _loadingStudentsMap[classModel.id] ?? false;

                      return _ClassCard(
                        classModel: classModel,
                        isExpanded: isExpanded,
                        onToggleExpand: () => _toggleExpand(classModel.id),
                        students: students,
                        isLoadingStudents: isLoadingStudents,
                        onAddClassStudent: () => _showAddStudentDialog(classModel),
                        onImportClassStudents: () => _importStudentsFromCsv(classModel),
                        onEditClass: () => _showEditClassDialog(classModel),
                        onDeleteClass: () => _showDeleteClassDialog(classModel),
                        onEmptyClass: () => _showEmptyClassDialog(classModel),
                        onEditStudent: (student) => _showEditStudentDialog(student, classModel),
                        onDeleteStudent: (student) => _showDeleteStudentDialog(student, classModel),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ClassCard extends StatefulWidget {
  final ClassModel classModel;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final List<UserModel>? students;
  final bool isLoadingStudents;
  final VoidCallback onAddClassStudent;
  final VoidCallback onImportClassStudents;
  final VoidCallback onEditClass;
  final VoidCallback onDeleteClass;
  final VoidCallback onEmptyClass;
  final Function(UserModel) onEditStudent;
  final Function(UserModel) onDeleteStudent;

  const _ClassCard({
    required this.classModel,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.students,
    required this.isLoadingStudents,
    required this.onAddClassStudent,
    required this.onImportClassStudents,
    required this.onEditClass,
    required this.onDeleteClass,
    required this.onEmptyClass,
    required this.onEditStudent,
    required this.onDeleteStudent,
  });

  @override
  State<_ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<_ClassCard> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color baseColor,
    required VoidCallback onTap,
    bool isSolid = false,
  }) {
    final Color textColor = isSolid ? Colors.white : baseColor;
    final Color iconColor = isSolid ? Colors.white : baseColor;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isSolid
            ? LinearGradient(
                colors: [
                  baseColor,
                  baseColor.withAlpha(200),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isSolid ? null : baseColor.withAlpha(20),
        border: Border.all(
          color: isSolid ? baseColor.withAlpha(100) : baseColor.withAlpha(60),
          width: 1,
        ),
        boxShadow: isSolid
            ? [
                BoxShadow(
                  color: baseColor.withAlpha(60),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = widget.students?.where((s) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.email.toLowerCase().contains(q) ||
          (s.rollNo ?? '').toLowerCase().contains(q);
    }).toList() ?? [];

    return Container(
      decoration: AppTheme.neumorphic(
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Class Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppTheme.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.class_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.classModel.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.isLoadingStudents
                                ? 'Loading students...'
                                : widget.students == null
                                    ? 'Tap to view students'
                                    : '${widget.students!.length} student(s) enrolled',
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
                        Icons.edit_outlined,
                        color: AppTheme.primary,
                        size: 18,
                      ),
                      tooltip: 'Edit Class',
                      onPressed: widget.onEditClass,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outlined,
                        color: AppTheme.error,
                        size: 18,
                      ),
                      tooltip: 'Delete Class',
                      onPressed: widget.onDeleteClass,
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: widget.isExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.textMuted,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Collapsible Student Section
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            child: widget.isExpanded
                ? Container(
                    decoration: const BoxDecoration(
                      color: Color(0x06FFFFFF),
                      border: Border(
                        top: BorderSide(color: Color(0x12FFFFFF)),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Student management tools header
                        Row(
                          children: [
                            Text(
                              'Students list',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _buildActionButton(
                                  icon: Icons.person_add_alt_1_rounded,
                                  label: 'Add Student',
                                  baseColor: const Color(0xFF10B981),
                                  onTap: widget.onAddClassStudent,
                                  isSolid: true,
                                ),
                                _buildActionButton(
                                  icon: Icons.upload_file_rounded,
                                  label: 'Bulk CSV',
                                  baseColor: AppTheme.primaryCyan,
                                  onTap: widget.onImportClassStudents,
                                ),
                                if (widget.students != null && widget.students!.isNotEmpty)
                                  _buildActionButton(
                                    icon: Icons.delete_sweep_rounded,
                                    label: 'Empty Class',
                                    baseColor: AppTheme.error,
                                    onTap: widget.onEmptyClass,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Sleek inline search bar
                        TextField(
                          controller: _searchController,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search roll number or name...',
                            hintStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textDisabled, fontSize: 12),
                            prefixIcon: Icon(Icons.search_rounded, size: 16, color: AppTheme.textMuted),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            fillColor: const Color(0xFF0F0C1E).withOpacity(0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0x18FFFFFF)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0x18FFFFFF)),
                            ),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // Student list view
                        if (widget.isLoadingStudents)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(color: AppTheme.primaryCyan),
                            ),
                          )
                        else if (widget.students == null || widget.students!.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                children: [
                                  Icon(Icons.people_outline_rounded, size: 28, color: AppTheme.textMuted.withOpacity(0.5)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'No students in this class yet.',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (filteredStudents.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No matching students found.',
                                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredStudents.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, idx) {
                              final student = filteredStudents[idx];
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundVariant.withOpacity(0.4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0x12FFFFFF)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppTheme.primary.withOpacity(0.2),
                                      ),
                                      child: Center(
                                        child: Text(
                                          student.name.isNotEmpty ? student.name[0].toUpperCase() : 'S',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  student.name,
                                                  style: GoogleFonts.plusJakartaSans(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (student.rollNo != null && student.rollNo!.isNotEmpty) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.primaryCyan.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    student.rollNo!,
                                                    style: GoogleFonts.plusJakartaSans(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.primaryCyan,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            student.email,
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 10,
                                              color: AppTheme.textMuted,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        color: AppTheme.primary,
                                        size: 16,
                                      ),
                                      tooltip: 'Edit Student',
                                      onPressed: () => widget.onEditStudent(student),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outlined,
                                        color: AppTheme.error,
                                        size: 16,
                                      ),
                                      tooltip: 'Delete Student',
                                      onPressed: () => widget.onDeleteStudent(student),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
