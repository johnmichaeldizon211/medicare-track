import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/auth_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final bool _isEmailSearch = true;
  bool _isSending = false;
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_isEmailSearch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS reset is not available yet. Use email instead.'),
        ),
      );
      return;
    }

    final email = _inputController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }

    if (!isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await AuthService.instance.requestPasswordOtp(email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link sent. Check your email.'),
        ),
      );
      Navigator.pop(context);
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
        const SnackBar(
          content: Text('Unable to send password reset link right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
              'Forgot Password?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF2994A),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _isEmailSearch
                  ? 'Enter the email address associated with your account and we\'ll send you a password reset link'
                  : 'Enter the mobile number associated with your account and we\'ll send you a password reset link',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 40),

            TextField(
              controller: _inputController,
              keyboardType: _isEmailSearch
                  ? TextInputType.emailAddress
                  : TextInputType.phone,
              decoration: InputDecoration(
                labelText: _isEmailSearch ? 'Email address' : 'Mobile number',
                labelStyle: const TextStyle(color: Colors.grey),
                floatingLabelStyle: const TextStyle(color: Color(0xFFF2994A)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(
                    color: Color(0xFFF2994A),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSending ? null : _sendCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2994A),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: _isSending
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
                        'Send Reset Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const Text(
              'SMS recovery is not available yet.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
