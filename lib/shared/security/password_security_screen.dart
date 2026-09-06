import 'package:flutter/material.dart';
import 'package:medicare_tract/shared/security/change_password_screen.dart';

// ============================================================================
// 1. MAIN SECURITY MENU SCREEN
// ============================================================================
class PasswordSecurityScreen extends StatelessWidget {
  const PasswordSecurityScreen({super.key});

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
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Password and security",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Login & recovery",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF37474F),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              "Manage your passwords, login preferences and recovery methods.",
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 30),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  _buildMenuOption(
                    title: "Change password",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChangePasswordScreen(),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, color: Colors.grey.shade300),
                  _buildMenuOption(
                    title: "Two-factor authentication",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Two-factor authentication is not available yet.",
                          ),
                        ),
                      );
                    },
                    trailingText: "Coming soon",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required String title,
    required VoidCallback onTap,
    String? trailingText,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // FIXED: Wrapped in Expanded so long titles don't push trailing content out
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF37474F),
                ),
              ),
            ),
            const SizedBox(
              width: 12,
            ), // Added spacing between title and trailing item
            if (trailingText == null)
              const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.black87,
              )
            else
              Text(
                trailingText,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
