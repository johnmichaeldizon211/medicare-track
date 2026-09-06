import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medicare_tract/core/navigation/auth_navigation.dart';
import 'package:medicare_tract/core/services/onboarding_service.dart';
import 'package:medicare_tract/core/services/push_notification_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/shared/auth/landing_screen.dart';
import 'package:medicare_tract/shared/auth/entry_screen.dart';

const MethodChannel _notificationPermissionChannel = MethodChannel(
  'medicare_tract/notifications',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestNotificationPermission();
  await PushNotificationService.instance.initialize();
  await SessionService.instance.load();
  await OnboardingService.instance.load();
  await PushNotificationService.instance.registerDeviceToken();
  runApp(const MedicareTrackApp());
  unawaited(PushNotificationService.instance.syncLoggedInCaregiverTaskReminders());
}

Future<void> _requestNotificationPermission() async {
  try {
    await _notificationPermissionChannel.invokeMethod<bool>(
      'requestPostNotifications',
    );
  } on MissingPluginException {
    // Non-Android platforms do not register this channel.
  } on PlatformException {
    // Keep startup moving even if the OS permission dialog cannot be shown.
  }
}

class MedicareTrackApp extends StatelessWidget {
  const MedicareTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medicare Track',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: const _AppStartupScreen(),
    );
  }
}

class _AppStartupScreen extends StatelessWidget {
  const _AppStartupScreen();

  @override
  Widget build(BuildContext context) {
    final session = SessionService.instance.session;
    if (session == null) {
      return OnboardingService.instance.isCompleted
          ? const EntryScreen()
          : const LandingScreen();
    }

    return dashboardForRole(session.role);
  }
}
