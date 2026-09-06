import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/navigation/auth_navigation.dart';
import 'package:medicare_tract/core/services/auth_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';
import 'package:medicare_tract/shared/auth/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isSubmitting = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password.')),
      );
      return;
    }

    if (!isValidEmail(_emailController.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final session = await AuthService.instance.login(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;

      goToDashboardForRole(context, session.role);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'USER_DISABLED') {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Account Disabled'),
            content: const Text(
              'Your account has been disabled by the administrator. Please contact support/admin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to login right now. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _buildDesktopLayout();
          } else if (constraints.maxWidth > 600) {
            return _buildTabletLayout();
          } else {
            return _buildMobileLayout();
          }
        },
      ),
    );
  }

  // --- DESKTOP LAYOUT (> 900px) ---
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Left Branding Panel
        Expanded(
          flex: 5,
          child: Container(
            color: const Color(0xFF2D0C57).withValues(alpha: 0.04),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/logo.png', width: 200),
                    const SizedBox(height: 24),
                    const Text(
                      AppBranding.appName,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      AppBranding.facilityName,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Right Form Panel
        Expanded(
          flex: 6,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _buildLoginFormCard(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- TABLET LAYOUT (600px - 900px) ---
  Widget _buildTabletLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            children: [
              _buildHeaderBranding(),
              const SizedBox(height: 30),
              _buildLoginFormCard(),
            ],
          ),
        ),
      ),
    );
  }

  // --- MOBILE LAYOUT (< 600px) ---
  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          children: [
            _buildHeaderBranding(),
            const SizedBox(height: 24),
            _buildLoginFormCard(),
          ],
        ),
      ),
    );
  }

  // Header logo & titles for Mobile/Tablet views
  Widget _buildHeaderBranding() {
    return Column(
      children: [
        Image.asset('assets/images/logo.png', width: 130),
        const SizedBox(height: 16),
        const Text(
          AppBranding.appName,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D0C57),
          ),
        ),
        const Text(
          AppBranding.facilityName,
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  // Reusable Login Card Widget
  Widget _buildLoginFormCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            spreadRadius: 2,
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Welcome back",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFFF2994A),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "Enter your email and password to continue.",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 28),

          // Email Field
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Email address',
              labelStyle: const TextStyle(color: Colors.grey),
              floatingLabelStyle: const TextStyle(color: Color(0xFFF2994A)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFFF2994A),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Password Field
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: const TextStyle(color: Colors.grey),
              floatingLabelStyle: const TextStyle(color: Color(0xFFF2994A)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFFF2994A),
                  width: 2,
                ),
              ),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                );
              },
              child: const Text(
                'Forgot Password?',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Login Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2994A),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'LOGIN',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          const Center(
            child: Text(
              'Need an account? Please contact the admin.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
