import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_export.dart';

class ShakeWidget extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double shakeRange;

  const ShakeWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.shakeRange = 16.0,
  });

  @override
  ShakeWidgetState createState() => ShakeWidgetState();
}

class ShakeWidgetState extends State<ShakeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void shake() {
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double progress = _controller.value;
        if (progress == 0.0 || progress == 1.0) return widget.child;
        final double offset = widget.shakeRange * (1.0 - progress) * math.sin(progress * 6 * math.pi);
        return Transform.translate(
          offset: Offset(offset, 0),
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class AdminPinChallengeDialog extends StatefulWidget {
  final String actionDescription;

  const AdminPinChallengeDialog({
    super.key,
    this.actionDescription = "perform this operation",
  });

  static Future<bool> show(BuildContext context, {String actionDescription = "perform this operation"}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AdminPinChallengeDialog(actionDescription: actionDescription),
    );
    return result ?? false;
  }

  @override
  State<AdminPinChallengeDialog> createState() => _AdminPinChallengeDialogState();
}

enum PinDialogStage {
  verify,
  setup,
  setupConfirm,
  forgotPassword,
}

class _AdminPinChallengeDialogState extends State<AdminPinChallengeDialog> {
  final GlobalKey<ShakeWidgetState> _shakeKey = GlobalKey<ShakeWidgetState>();
  
  PinDialogStage _stage = PinDialogStage.verify;
  String _storedPin = '';
  String _inputBuffer = '';
  String _setupPinBuffer = '';
  
  bool _isLoading = false;
  String _errorMessage = '';
  
  // Password controllers
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkStoredPin();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkStoredPin() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final pin = prefs.getString('admin_security_pin') ?? '';
      setState(() {
        _storedPin = pin;
        _stage = pin.isEmpty ? PinDialogStage.setup : PinDialogStage.verify;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onKeyPress(String val) {
    if (_isLoading) return;
    
    setState(() {
      _errorMessage = '';
    });

    if (val == 'back') {
      if (_inputBuffer.isNotEmpty) {
        setState(() {
          _inputBuffer = _inputBuffer.substring(0, _inputBuffer.length - 1);
        });
      }
      return;
    }

    if (_inputBuffer.length >= 4) return;

    setState(() {
      _inputBuffer += val;
    });

    if (_inputBuffer.length == 4) {
      _processInput();
    }
  }

  Future<void> _processInput() async {
    final entered = _inputBuffer;
    
    // Clear buffer so user doesn't see lingering dots during transition
    setState(() {
      _inputBuffer = '';
    });

    if (_stage == PinDialogStage.verify) {
      if (entered == _storedPin) {
        Navigator.pop(context, true);
      } else {
        _shakeKey.currentState?.shake();
        setState(() {
          _errorMessage = 'Incorrect PIN. Please try again.';
        });
      }
    } else if (_stage == PinDialogStage.setup) {
      setState(() {
        _setupPinBuffer = entered;
        _stage = PinDialogStage.setupConfirm;
      });
    } else if (_stage == PinDialogStage.setupConfirm) {
      if (entered == _setupPinBuffer) {
        setState(() => _isLoading = true);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('admin_security_pin', entered);
          if (mounted) {
            Navigator.pop(context, true);
          }
        } catch (e) {
          setState(() {
            _errorMessage = 'Failed to save PIN';
            _stage = PinDialogStage.setup;
          });
        } finally {
          setState(() => _isLoading = false);
        }
      } else {
        _shakeKey.currentState?.shake();
        setState(() {
          _errorMessage = 'PINs do not match. Restarting setup.';
          _stage = PinDialogStage.setup;
        });
      }
    }
  }

  Future<void> _verifyPasswordAndResetPin() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Password cannot be empty';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final email = SupabaseService.currentAuthUser?.email;
      if (email == null) {
        throw Exception('User session not found');
      }

      // Re-auth via signIn
      await SupabaseService.signIn(email, password);

      // Password matches! Reset PIN
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_security_pin');
      
      setState(() {
        _storedPin = '';
        _passwordController.clear();
        _stage = PinDialogStage.setup;
        _errorMessage = 'PIN successfully reset. Please create a new PIN.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Invalid password verification.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _storedPin.isEmpty && _errorMessage.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryCyan));
    }

    String titleText = 'Security PIN';
    String instructionText = 'Enter 4-digit PIN to authorize action';

    if (_stage == PinDialogStage.verify) {
      titleText = 'Admin Verification';
      instructionText = 'Enter PIN to ${widget.actionDescription}';
    } else if (_stage == PinDialogStage.setup) {
      titleText = 'Create Security PIN';
      instructionText = 'Set a 4-digit PIN to protect admin actions';
    } else if (_stage == PinDialogStage.setupConfirm) {
      titleText = 'Confirm Security PIN';
      instructionText = 'Confirm your 4-digit security PIN';
    } else if (_stage == PinDialogStage.forgotPassword) {
      titleText = 'Reset Security PIN';
      instructionText = 'Verify your login password to reset PIN';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131024),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24),
                Text(
                  titleText,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.04),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white60,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Subtitle instructions
            Text(
              instructionText,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (_stage == PinDialogStage.forgotPassword) ...[
              // Password input form
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Enter account password',
                    hintStyle: GoogleFonts.plusJakartaSans(color: AppTheme.textMuted, fontSize: 13),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty) ...[
                Text(
                  _errorMessage,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => setState(() {
                        _errorMessage = '';
                        _stage = PinDialogStage.verify;
                      }),
                      child: Text(
                        'Back',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _verifyPasswordAndResetPin,
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              'Verify',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Passcode Dots Indicator
              ShakeWidget(
                key: _shakeKey,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isFilled = index < _inputBuffer.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFilled ? AppTheme.primaryCyan : Colors.transparent,
                        border: Border.all(
                          color: isFilled ? AppTheme.primaryCyan : Colors.white24,
                          width: 2,
                        ),
                        boxShadow: isFilled
                            ? [
                                BoxShadow(
                                  color: AppTheme.primaryCyan.withAlpha(120),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24),
              
              if (_errorMessage.isNotEmpty) ...[
                Text(
                  _errorMessage,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],

              // Keypad Layout
              SizedBox(
                width: 240,
                child: Column(
                  children: [
                    _buildKeypadRow(['1', '2', '3']),
                    const SizedBox(height: 12),
                    _buildKeypadRow(['4', '5', '6']),
                    const SizedBox(height: 12),
                    _buildKeypadRow(['7', '8', '9']),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left placeholder / Cancel button
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: _stage == PinDialogStage.verify
                              ? TextButton(
                                  onPressed: () => setState(() {
                                    _errorMessage = '';
                                    _stage = PinDialogStage.forgotPassword;
                                  }),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'Forgot?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        _buildKeypadButton('0'),
                        _buildKeypadButton('back'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((key) => _buildKeypadButton(key)).toList(),
    );
  }

  Widget _buildKeypadButton(String key) {
    final isBack = key == 'back';
    
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onKeyPress(key),
          customBorder: const CircleBorder(),
          child: Center(
            child: isBack
                ? const Icon(
                    Icons.backspace_outlined,
                    color: Colors.white60,
                    size: 18,
                  )
                : Text(
                    key,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
