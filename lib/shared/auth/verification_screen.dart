import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medicare_tract/core/services/auth_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class VerificationScreen extends StatefulWidget {
  final String email;

  const VerificationScreen({super.key, required this.email});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final List<TextEditingController> _otpControllers;
  bool _isSubmitting = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _otpCode => _otpControllers.map((e) => e.text).join();

  Future<void> _verifyCode() async {
    if (_otpCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the complete 6-digit code.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthService.instance.verifyPasswordOtp(
        email: widget.email,
        code: _otpCode,
      );

      if (!mounted) {
        return;
      }

      await _showResetPasswordDialog();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to verify OTP right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isResending = true);
    try {
      await AuthService.instance.requestPasswordOtp(widget.email);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent again.')),
      );
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to resend code right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final newPassword = newPasswordController.text.trim();
                          final confirmPassword = confirmController.text.trim();

                          if (newPassword.length < 6) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password must be at least 6 characters.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (newPassword != confirmPassword) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password confirmation does not match.',
                                ),
                              ),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);
                          try {
                            await AuthService.instance.resetPassword(
                              email: widget.email,
                              code: _otpCode,
                              newPassword: newPassword,
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            Navigator.pop(dialogContext);
                            if (!mounted) {
                              return;
                            }

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password reset successful. Please login.',
                                ),
                              ),
                            );
                            Navigator.pop(context);
                            Navigator.pop(context);
                          } on ApiException catch (e) {
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(SnackBar(content: Text(e.message)));
                          } catch (_) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Unable to reset password right now.',
                                ),
                              ),
                            );
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Reset'),
                ),
              ],
            );
          },
        );
      },
    );

    newPasswordController.dispose();
    confirmController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            const Text(
              'Forget Password ?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF2994A),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Enter the verification code sent to ${widget.email}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 40),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                6,
                (index) => _buildOtpBox(context, index),
              ),
            ),
            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2994A),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Verify Code',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "didn't receive the code? ",
                  style: TextStyle(color: Colors.grey),
                ),
                GestureDetector(
                  onTap: _isResending ? null : _resendCode,
                  child: Text(
                    _isResending ? 'sending...' : 'resend',
                    style: const TextStyle(
                      color: Color(0xFFF2994A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpBox(BuildContext context, int index) {
    return SizedBox(
      height: 50,
      width: 45,
      child: TextField(
        controller: _otpControllers[index],
        onChanged: (value) {
          if (value.length == 1 && index < _otpControllers.length - 1) {
            FocusScope.of(context).nextFocus();
          }
        },
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [
          LengthLimitingTextInputFormatter(1),
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFF2994A), width: 2),
          ),
        ),
      ),
    );
  }
}
