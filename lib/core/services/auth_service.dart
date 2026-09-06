import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:medicare_tract/core/models/app_session.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/services/push_notification_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/core/services/time_clock_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseAuth get _auth => _firebase.auth;

  Future<AppSession> login({
    required String email,
    required String password,
  }) async {
    return _firebase.guard(() async {
      final normalizedEmail = email.trim().toLowerCase();
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password.trim(),
      );
      final user = credential.user;
      if (user == null) {
        throw ApiException(
          statusCode: 401,
          code: 'INVALID_CREDENTIALS',
          message: 'Invalid email or password.',
        );
      }

      final profile = await _firebase.currentUserProfile();
      final session = AppSession(
        accessToken: await user.getIdToken() ?? '',
        refreshToken: user.refreshToken ?? '',
        role: (profile['role'] ?? '').toString().toUpperCase(),
        email: (profile['email'] ?? user.email ?? normalizedEmail).toString(),
        userId: user.uid,
      );

      if (_isCaregiver(session)) {
        try {
          await TimeClockService.instance.timeIn();
        } catch (_) {
          await SessionService.instance.clear();
          rethrow;
        }
      }

      await SessionService.instance.save(session);
      await PushNotificationService.instance.registerDeviceToken();
      unawaited(
        PushNotificationService.instance.syncLoggedInCaregiverTaskReminders(),
      );
      return session;
    }, fallbackMessage: 'Unable to login right now. Please try again.');
  }

  Future<void> requestPasswordOtp(String email) async {
    await _firebase.guard(() async {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    }, fallbackMessage: 'Unable to send password reset email right now.');
  }

  Future<void> verifyPasswordOtp({
    required String email,
    required String code,
  }) async {
    await _firebase.guard(() async {
      await _auth.verifyPasswordResetCode(code.trim());
    }, fallbackMessage: 'Invalid or expired reset code.');
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _firebase.guard(() async {
      await _auth.confirmPasswordReset(
        code: code.trim(),
        newPassword: newPassword,
      );
    }, fallbackMessage: 'Unable to reset password right now.');
  }

  Future<void> logout() async {
    final session = SessionService.instance.session;
    if (session != null && _isCaregiver(session)) {
      try {
        await TimeClockService.instance.timeOutIfActive();
      } catch (_) {
        // Logout must still complete even if the attendance write fails.
      }
    }

    await PushNotificationService.instance.unregisterDeviceToken();
    await PushNotificationService.instance.cancelCaregiverTaskNotifications();
    await SessionService.instance.clear();
  }

  Future<Map<String, dynamic>> me() async {
    return _firebase.guard(
      _firebase.currentUserProfile,
      fallbackMessage: 'Unable to load your account right now.',
    );
  }

  bool _isCaregiver(AppSession session) {
    return session.role.toUpperCase() == 'CAREGIVER';
  }
}
