class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? classId;
  final String? className;
  final String? rollNo;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.classId,
    this.className,
    this.rollNo,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    // Extract class name from nested classes join
    String? extractedClassName;
    final classData = map['classes'];
    if (classData is Map<String, dynamic>) {
      extractedClassName = classData['name'] as String?;
    }
    return UserModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'student',
      classId: map['class_id'] as String?,
      className: extractedClassName ?? map['class_name'] as String?,
      rollNo: map['roll_no'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'roll_no': rollNo,
  };

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
  bool get isStudent => role == 'student';
}
