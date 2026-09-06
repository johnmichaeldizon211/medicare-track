import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/shared/auth/login_screen.dart';

class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isTablet = constraints.maxWidth >= 600;
          final bool isDesktop = constraints.maxWidth >= 1000;

          final double contentWidth = isDesktop
              ? 520
              : isTablet
              ? 500
              : double.infinity;

          final double logoSize = isDesktop
              ? 190
              : isTablet
              ? 180
              : 165;

          return Stack(
            children: [
              // ============================================================
              // BACKGROUND IMAGE
              // ============================================================
              Positioned.fill(
                child: Image.asset(
                  'assets/images/lifehouse_bg.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),

              // ============================================================
              // SOFT WHITE OVERLAY
              // Keeps the background visible while making text readable.
              // ============================================================
              Positioned.fill(
                child: Container(color: Colors.white.withValues(alpha: 0.38)),
              ),

              // ============================================================
              // MAIN CONTENT
              // ============================================================
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop
                          ? 40
                          : isTablet
                          ? 32
                          : 22,
                      vertical: 30,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentWidth),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ==================================================
                          // LOGO
                          // ==================================================
                          Image.asset(
                            'assets/images/logo.png',
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                          ),

                          SizedBox(height: isDesktop ? 22 : 16),

                          // ==================================================
                          // APP NAME
                          // ==================================================
                          Text(
                            AppBranding.appName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isDesktop
                                  ? 42
                                  : isTablet
                                  ? 38
                                  : 34,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2D0C57),
                              letterSpacing: -1.0,
                              height: 1.1,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // ==================================================
                          // FACILITY NAME
                          // ==================================================
                          Text(
                            AppBranding.facilityName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color.fromARGB(255, 236, 104, 52),
                              fontSize: isDesktop ? 20 : 18,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ==================================================
                          // HEART DIVIDER
                          // ==================================================
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: isTablet ? 100 : 70,
                                height: 1.5,
                                color: const Color(0xFFF2994A),
                              ),

                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFF2994A),
                                  size: 20,
                                ),
                              ),

                              Container(
                                width: isTablet ? 100 : 70,
                                height: 1.5,
                                color: const Color(0xFFF2994A),
                              ),
                            ],
                          ),

                          const SizedBox(height: 22),

                          // ==================================================
                          // DESCRIPTION
                          // ==================================================
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'A reliable system to help manage and track '
                              'medications with accuracy and care.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFF555555),
                                fontSize: isDesktop ? 18 : 16,
                                fontWeight: FontWeight.w400,
                                height: 1.5,
                              ),
                            ),
                          ),

                          SizedBox(height: isDesktop ? 42 : 34),

                          // ==================================================
                          // CONTINUE BUTTON
                          // ==================================================
                          SizedBox(
                            width: double.infinity,
                            height: isDesktop ? 70 : 64,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2994A),
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: const Color(
                                  0xFFF2994A,
                                ).withValues(alpha: 0.30),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Shield icon
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.verified_user_outlined,
                                      color: Colors.white,
                                      size: 23,
                                    ),
                                  ),

                                  const SizedBox(width: 16),

                                  const Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 25),

                          // ==================================================
                          // SMALL SECURITY MESSAGE
                          // ==================================================
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: Color(0xFF777777),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Secure & confidential',
                                style: TextStyle(
                                  color: const Color(0xFF777777),
                                  fontSize: isDesktop ? 14 : 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
