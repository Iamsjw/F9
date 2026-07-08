import 'dart:async';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:ui';

import '../../core/app_export.dart';
import '../../routes/app_routes.dart';

class SignUpLoginScreen extends StatefulWidget {
  const SignUpLoginScreen({super.key});

  @override
  State<SignUpLoginScreen> createState() => _SignUpLoginScreenState();
}

class _SignUpLoginScreenState extends State<SignUpLoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late AnimationController _entranceController;
  late AnimationController _logoController;
  late Animation<double> _entranceFade;
  late Animation<Offset> _entranceSlide;
  late Animation<double> _logoScale;
  late Animation<double> _logoPulse;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _entranceFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    _logoPulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );

    _entranceController.forward();
    _checkExistingSession(); // called once only
  }

  void _navigateToReplacement(String routeName) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, routeName);
      }
    });
  }

  Future<void> _checkExistingSession() async {
    try {
      // Try to refresh the session first — this re-validates an expired access
      // token using the persisted refresh token, keeping users logged in.
      final currentSession = SupabaseService.client.auth.currentSession;
      if (currentSession != null) {
        try {
          await SupabaseService.client.auth.refreshSession();
        } catch (_) {
          // Refresh failed (e.g. refresh token expired) — fall through to
          // check currentAuthUser which will be null, showing the login screen.
        }
      }
    } catch (_) {}

    final user = SupabaseService.currentAuthUser;
    if (user == null) return;

    final profile = await SupabaseService.getUserProfile(user.id);
    if (profile == null || !mounted) return;

    switch (profile.role) {
      case 'teacher':
        _navigateToReplacement(AppRoutes.teacherSessionScreen);
        break;
      case 'student':
        _navigateToReplacement(AppRoutes.studentAttendanceScreen);
        break;
      case 'admin':
        _navigateToReplacement(AppRoutes.adminDashboardScreen);
        break;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _logoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint(
        '[Auth] Attempting sign in for ${_emailController.text.trim()}',
      );
      final response = await SupabaseService.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      debugPrint('[Auth] Sign in response: user=${response.user?.id}');
      if (response.user != null) {
        final profile = await SupabaseService.getUserProfile(response.user!.id);
        if (profile != null && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _navigateByRole(profile.role);
          });
          return;
        } else if (mounted) {
          setState(() => _errorMessage = 'Profile not found. Contact admin.');
        }
      }
    } on AuthException catch (e) {
      debugPrint('[Auth] AuthException: ${e.message}');
      if (mounted) {
        setState(() {
          final msg = e.message.toLowerCase();
          if (msg.contains('invalid login credentials') ||
              msg.contains('invalid') ||
              msg.contains('grant_type')) {
            _errorMessage = 'Invalid email or password. Please try again.';
          } else if (msg.contains('network') ||
              msg.contains('socket') ||
              msg.contains('connection') ||
              msg.contains('host') ||
              msg.contains('paused') ||
              msg.contains('503') ||
              msg.contains('500') ||
              msg.contains('fetch')) {
            _errorMessage = 'Database or server is currently unreachable. Please try again later.';
          } else if (msg.contains('rate limit') || msg.contains('too many')) {
            _errorMessage = 'Too many attempts. Please wait a few minutes before trying again.';
          } else {
            _errorMessage = 'Authentication failed. Please check your internet connection or credentials.';
          }
        });
      }
    } catch (e) {
      debugPrint('[Auth] Unexpected error: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Unable to connect to service. Please check your connection.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateByRole(String role) {
    if (role == 'teacher') {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.teacherSessionScreen,
        (_) => false,
      );
    } else if (role == 'student') {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.studentAttendanceScreen,
        (_) => false,
      );
    } else {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.adminDashboardScreen,
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            _buildBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 0 : 24,
                    vertical: 24,
                  ),
                  child: AnimatedBuilder(
                    animation: _entranceController,
                    builder: (context, child) {
                      return FadeTransition(
                        opacity: _entranceFade,
                        child: SlideTransition(
                          position: _entranceSlide,
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      width: isTablet ? 440 : double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoSection(),
                          const SizedBox(height: 36),
                          _buildAuthCard(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
          top: -150,
          right: -150,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primaryCyan.withOpacity(0.18),
                  AppTheme.primaryCyan.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -200,
          left: -200,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primaryBlue.withOpacity(0.15),
                  AppTheme.primaryBlue.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, child) {
        return ScaleTransition(
          scale: _logoScale,
          child: Transform.scale(scale: _logoPulse.value, child: child),
        );
      },
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD946EF).withOpacity(0.35),
                  blurRadius: 30,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'UpasthitiX',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Smart Attendance System',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0x18FFFFFF),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildEmailField(),
                  const SizedBox(height: 16),
                  _buildPasswordField(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorMessage(),
                  ],
                  const SizedBox(height: 28),
                  _buildSubmitButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return _buildField(
      label: 'Email Address',
      hint: 'you@example.com',
      controller: _emailController,
      prefixIcon: Icons.email_outlined,
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        final email = v?.trim() ?? '';
        if (email.isEmpty) return 'Email required';
        if (!email.contains('@') || !email.contains('.')) {
          return 'Enter a valid email (e.g. user@example.com)';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return _buildField(
      label: 'Password',
      trailingLabel: TextButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRoutes.forgotPasswordScreen);
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          'Forgot Password?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.primaryCyan,
          ),
        ),
      ),
      hint: '••••••••',
      controller: _passwordController,
      prefixIcon: Icons.lock_outline_rounded,
      obscureText: _obscurePassword,
      suffixIcon: IconButton(
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          color: AppTheme.textMuted,
          size: 20,
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password required';
        if (v.length < 6) return 'Min 6 characters';
        return null;
      },
    );
  }

  Widget _buildField({
    required String label,
    Widget? trailingLabel,
    required String hint,
    required TextEditingController controller,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            if (trailingLabel != null) trailingLabel,
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppTheme.textDisabled,
            ),
            prefixIcon: Icon(prefixIcon, color: AppTheme.textMuted, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFF130E26).withOpacity(0.85),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0x33FFFFFF), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0x22FFFFFF), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.primary,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.error,
                width: 1,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppTheme.error,
                width: 1.5,
              ),
            ),
            errorStyle: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppTheme.error,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.errorSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.error,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(Icons.close_rounded, size: 16, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(77),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _handleSignIn,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withAlpha(26),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Sign In',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
