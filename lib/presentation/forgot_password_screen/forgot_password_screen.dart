import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_export.dart';
import '../../routes/app_routes.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 1; // 1: Email, 2: OTP Code, 3: New Password

  final _formKeyEmail = GlobalKey<FormState>();
  final _formKeyOtp = GlobalKey<FormState>();
  final _formKeyPassword = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;

  // Resend OTP Timer
  Timer? _resendTimer;
  int _resendCountdown = 60;
  bool _canResend = false;

  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _entranceController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendCountdown = 60;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      }
      if (_resendCountdown == 0) {
        setState(() => _canResend = true);
        timer.cancel();
      }
    });
  }

  // ─── Step 1: Request Reset Code ─────────────────────────────────────────────
  Future<void> _handleSendResetCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final emailExists = await SupabaseService.doesEmailExist(email);
      if (emailExists) {
        await SupabaseService.resetPasswordForEmail(email);
      }

      if (!mounted) return;
      setState(() {
        _currentStep = 2;
        _successMessage = 'If this email exists in our system, a reset code will be sent to it.';
      });
      _startResendTimer();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          final msg = e.message.toLowerCase();
          if (msg.contains('rate limit') || msg.contains('too many')) {
            _errorMessage = 'Too many requests. Please wait a while or try again later.';
          } else if (msg.contains('network') || msg.contains('socket') || msg.contains('host') || msg.contains('503')) {
            _errorMessage = 'Database or server is currently unreachable. Try again later.';
          } else {
            _errorMessage = 'Unable to send reset code. Please verify your email address.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to send reset code. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Step 2: Verify OTP Code ────────────────────────────────────────────────
  Future<void> _handleVerifyOtp() async {
    if (!_formKeyOtp.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final otp = _otpController.text.trim();

      final response = await SupabaseService.verifyPasswordResetOtp(
        email: email,
        token: otp,
      );

      if (response.session != null || response.user != null) {
        if (!mounted) return;
        setState(() {
          _currentStep = 3;
          _successMessage = 'Code verified! Enter your new password.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Invalid or expired verification code.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          final msg = e.message.toLowerCase();
          if (msg.contains('invalid token') || msg.contains('invalid') || msg.contains('expired')) {
            _errorMessage = 'Invalid code. Check your email and try again.';
          } else if (msg.contains('network') || msg.contains('socket') || msg.contains('host')) {
            _errorMessage = 'Server is currently unreachable. Please try again later.';
          } else {
            _errorMessage = 'Verification failed. Please check the code and try again.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Verification failed. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Step 3: Update Password ────────────────────────────────────────────────
  Future<void> _handleUpdatePassword() async {
    if (!_formKeyPassword.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final newPassword = _newPasswordController.text.trim();
      await SupabaseService.updatePassword(newPassword);

      if (!mounted) return;

      // Show success dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF191338),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0x33FFFFFF)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded,
                    color: AppTheme.success, size: 28),
              ),
              const SizedBox(width: 12),
              Text(
                'Password Reset!',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: Text(
            'Your password has been successfully updated. Please sign in with your new credentials.',
            style: GoogleFonts.plusJakartaSans(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.signUpLoginScreen,
                  (_) => false,
                );
              },
              child: Text(
                'Back to Sign In',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to update password. Please check your network or try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to update password. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 0 : 24,
                          vertical: 16,
                        ),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SizedBox(
                            width: isTablet ? 440 : double.infinity,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildStepHeader(),
                                const SizedBox(height: 24),
                                _buildCardContent(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned.fill(child: Container(color: AppTheme.background)),
        Positioned(
          top: -100,
          left: -100,
          child: Container(
            width: 450,
            height: 450,
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
          bottom: -150,
          right: -150,
          child: Container(
            width: 550,
            height: 550,
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

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_currentStep == 2) {
                setState(() {
                  _currentStep = 1;
                  _errorMessage = null;
                  _successMessage = null;
                });
              } else {
                Navigator.pop(context);
              }
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Password Recovery',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader() {
    return Column(
      children: [
        // Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withAlpha(77),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            _currentStep == 1
                ? Icons.mark_email_read_outlined
                : _currentStep == 2
                    ? Icons.pin_outlined
                    : Icons.lock_reset_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _currentStep == 1
              ? 'Forgot Password?'
              : _currentStep == 2
                  ? 'Enter Verification Code'
                  : 'Set New Password',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _currentStep == 1
              ? 'Enter your account email to receive a 6-digit recovery code.'
              : _currentStep == 2
                  ? 'Enter the 6-digit code sent to ${_emailController.text}'
                  : 'Choose a strong new password for your account.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        // Step Indicator Progress Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final stepNum = index + 1;
            final isActive = stepNum <= _currentStep;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              width: isActive ? 32 : 16,
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primaryCyan
                    : Colors.white.withAlpha(38),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildCardContent() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x18FFFFFF), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  _buildMessageBanner(
                    message: _errorMessage!,
                    isError: true,
                    onDismiss: () => setState(() => _errorMessage = null),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_successMessage != null) ...[
                  _buildMessageBanner(
                    message: _successMessage!,
                    isError: false,
                    onDismiss: () => setState(() => _successMessage = null),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_currentStep == 1) _buildStep1EmailForm(),
                if (_currentStep == 2) _buildStep2OtpForm(),
                if (_currentStep == 3) _buildStep3PasswordForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBanner({
    required String message,
    required bool isError,
    required VoidCallback onDismiss,
  }) {
    final bgColor = isError ? AppTheme.errorSoft : AppTheme.successSoft;
    final borderColor = isError ? AppTheme.error : AppTheme.success;
    final icon = isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: borderColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: borderColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 16, color: borderColor),
          ),
        ],
      ),
    );
  }

  // ─── Step 1 Form: Email ─────────────────────────────────────────────────────
  Widget _buildStep1EmailForm() {
    return Form(
      key: _formKeyEmail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            label: 'Registered Email Address',
            hint: 'user@example.com',
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Email is required';
              if (!val.contains('@') || !val.contains('.')) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Send Verification Code',
            onPressed: _handleSendResetCode,
          ),
        ],
      ),
    );
  }

  // ─── Step 2 Form: OTP Code ──────────────────────────────────────────────────
  Widget _buildStep2OtpForm() {
    return Form(
      key: _formKeyOtp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            label: '6-Digit Verification Code',
            hint: '123456',
            controller: _otpController,
            prefixIcon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Code is required';
              if (val.length < 6) return 'Code must be 6 digits';
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _canResend
                    ? "Didn't receive the code?"
                    : "Resend code in ${_resendCountdown}s",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
              if (_canResend)
                TextButton(
                  onPressed: _isLoading ? null : _handleSendResetCode,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Resend Code',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Verify Code',
            onPressed: _handleVerifyOtp,
          ),
        ],
      ),
    );
  }

  // ─── Step 3 Form: New Password ──────────────────────────────────────────────
  Widget _buildStep3PasswordForm() {
    return Form(
      key: _formKeyPassword,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField(
            label: 'New Password',
            hint: '••••••••',
            controller: _newPasswordController,
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureNewPassword,
            suffixIcon: IconButton(
              onPressed: () =>
                  setState(() => _obscureNewPassword = !_obscureNewPassword),
              icon: Icon(
                _obscureNewPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'New password required';
              if (val.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Confirm New Password',
            hint: '••••••••',
            controller: _confirmPasswordController,
            prefixIcon: Icons.lock_clock_outlined,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword),
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppTheme.textMuted,
                size: 20,
              ),
            ),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Confirm password required';
              if (val != _newPasswordController.text.trim()) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          _buildActionButton(
            label: 'Reset Password',
            onPressed: _handleUpdatePassword,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          inputFormatters: inputFormatters,
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

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
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
          onTap: _isLoading ? null : onPressed,
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
                    label,
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
