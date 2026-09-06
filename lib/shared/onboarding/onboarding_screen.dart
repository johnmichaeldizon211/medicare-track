import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/services/onboarding_service.dart';
import 'package:medicare_tract/shared/auth/entry_screen.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await OnboardingService.instance.complete();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const EntryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isDesktop = constraints.maxWidth > 600;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 480 : double.infinity,
                maxHeight: isDesktop ? 820 : double.infinity,
              ),
              child: Container(
                decoration: isDesktop
                    ? BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            spreadRadius: 4,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      )
                    : const BoxDecoration(color: Colors.white),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Background Soft Curved Circle Accent
                    Positioned(
                      bottom: -200,
                      left: -100,
                      right: -100,
                      child: Container(
                        height: 400,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF3F0FF).withValues(alpha: 0.8),
                        ),
                      ),
                    ),

                    // Top Bar (Skip Button)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 16,
                      child: TextButton(
                        onPressed: _finishOnboarding,
                        child: const Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),

                    // Page Content View
                    Column(
                      children: [
                        const SizedBox(height: 60),
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (int page) =>
                                setState(() => _currentPage = page),
                            children: [
                              _buildPageContent(
                                image: 'assets/images/onboarding1.png',
                                title: AppBranding.appName,
                                subtitle: AppBranding.facilityName,
                              ),
                              _buildPageContent(
                                image: 'assets/images/onboarding2.png',
                                title: 'Stay Informed on Medications',
                                subtitle:
                                    'Monitor medications and updates in real-time.',
                              ),
                              _buildPageContent(
                                image: 'assets/images/onboarding3.png',
                                title: 'Better Care Starts Here',
                                subtitle:
                                    'Stay updated on every task and ensure proper care.',
                              ),
                              _buildPageContent(
                                image: 'assets/images/onboarding4.png',
                                title: 'Stay Close, Even From Afar',
                                subtitle:
                                    'Communicate with caregivers anytime.',
                              ),
                            ],
                          ),
                        ),

                        // Bottom Controls (Dots + Action Button)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Page Indicator Dots
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  4,
                                  (index) => _buildDot(index),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Continue / Get Started Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    if (_currentPage == 3) {
                                      _finishOnboarding();
                                    } else {
                                      _pageController.nextPage(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF2994A),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    _currentPage == 3
                                        ? 'Get Started'
                                        : 'Continue',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? const Color(0xFFF2994A)
            : Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildPageContent({
    required String image,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          // Header Logo & Branding
          Image.asset('assets/images/logo.png', width: 64, height: 64),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D0C57),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),

          // Main Onboarding Image
          Expanded(
            child: Container(
              alignment: Alignment.center,
              child: Image.asset(image, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
