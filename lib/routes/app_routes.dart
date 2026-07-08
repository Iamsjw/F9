import 'package:flutter/material.dart';

import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/sign_up_login_screen/sign_up_login_screen.dart';
import '../presentation/forgot_password_screen/forgot_password_screen.dart';
import '../presentation/student_attendance_screen/student_attendance_screen.dart';
import '../presentation/teacher_session_screen/teacher_session_screen.dart';
import '../presentation/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../presentation/completed_classes_timetable_screen/completed_classes_timetable_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splashScreen = '/splash-screen';
  static const String signUpLoginScreen = '/sign-up-login-screen';
  static const String forgotPasswordScreen = '/forgot-password-screen';
  static const String teacherSessionScreen = '/teacher-session-screen';
  static const String studentAttendanceScreen = '/student-attendance-screen';
  static const String adminDashboardScreen = '/admin-dashboard-screen';
  static const String completedClassesTimetableScreen = '/completed-classes-timetable';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const SplashScreen(),
    splashScreen: (context) => const SplashScreen(),
    signUpLoginScreen: (context) => const SignUpLoginScreen(),
    forgotPasswordScreen: (context) => const ForgotPasswordScreen(),
    teacherSessionScreen: (context) => const TeacherSessionScreen(),
    studentAttendanceScreen: (context) => const StudentAttendanceScreen(),
    adminDashboardScreen: (context) => const AdminDashboardScreen(),
    completedClassesTimetableScreen: (context) => const CompletedClassesTimetableScreen(),
  };
}
