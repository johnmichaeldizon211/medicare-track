import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/auth/forgot_password_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  // Controllers to grab the text
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // State variables to hide/show passwords
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isUpdating = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        // Allows scrolling if the keyboard pops up!
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Change password",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Your password must be at least 6 characters and should include a combination of numbers, letters and special characters.",
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 30),

            // 1. Current Password
            _buildPasswordField(
              label: "Current Password",
              hint: "Enter old password",
              controller: _currentPasswordController,
              isObscured: _obscureCurrent,
              onToggleVisibility: () {
                setState(() {
                  _obscureCurrent = !_obscureCurrent;
                });
              },
            ),
            const SizedBox(height: 20),

            // 2. New Password
            _buildPasswordField(
              label: "New Password",
              hint: "Enter new password",
              controller: _newPasswordController,
              isObscured: _obscureNew,
              onToggleVisibility: () {
                setState(() {
                  _obscureNew = !_obscureNew;
                });
              },
            ),
            const SizedBox(height: 20),

            // 3. Confirm New Password
            _buildPasswordField(
              label: "Confirm New Password",
              hint: "Retype new password",
              controller: _confirmPasswordController,
              isObscured: _obscureConfirm,
              onToggleVisibility: () {
                setState(() {
                  _obscureConfirm = !_obscureConfirm;
                });
              },
            ),
            const SizedBox(height: 15),

            // Forgot Password Link
            // Forgot Password Link
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  // NEW LINK: Routes to your actual Forgot Password Screen!
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordScreen(),
                    ),
                  );
                },
                child: const Text(
                  "Forgotten your password?",
                  style: TextStyle(
                    color: Color(0xFF00BFA5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUpdating
                    ? null
                    : () async {
                        if (_newPasswordController.text !=
                            _confirmPasswordController.text) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("New passwords do not match!"),
                              backgroundColor: Color(0xFFE53935),
                            ),
                          );
                          return;
                        }

                        if (_newPasswordController.text.trim().length < 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "New password must be at least 6 characters.",
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() => _isUpdating = true);
                        try {
                          await ProfileService.instance.updatePassword(
                            currentPassword: _currentPasswordController.text,
                            newPassword: _newPasswordController.text,
                          );

                          if (!context.mounted) {
                            return;
                          }
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Password successfully updated!"),
                              backgroundColor: Color(0xFF00C853),
                            ),
                          );
                        } on ApiException catch (e) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(e.message),
                              backgroundColor: const Color(0xFFE53935),
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Unable to update password right now.",
                              ),
                              backgroundColor: Color(0xFFE53935),
                            ),
                          );
                        } finally {
                          if (mounted) {
                            setState(() => _isUpdating = false);
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFA726),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 0,
                ),
                child: _isUpdating
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
                        "Update Password",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper Widget for Password Fields
  Widget _buildPasswordField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isObscured,
    required VoidCallback onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF37474F),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isObscured,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
            // The Eye Icon!
            suffixIcon: IconButton(
              icon: Icon(
                isObscured ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: onToggleVisibility,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Color(0xFFFFA726), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
