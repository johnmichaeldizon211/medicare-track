import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medicare_tract/core/models/app_session.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/services/firebase_app_initializer.dart';

class SessionService {
  SessionService._();

  static final SessionService instance = SessionService._();

  static const _sessionKey = 'app_session';

  AppSession? _session;

  AppSession? get session => _session;
  bool get isLoggedIn => _session != null;

  Future<void> load() async {
    _session = await _loadSavedSession();
    await _loadFirebaseSession();
  }

  Future<AppSession?> _loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) {
      return null;
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppSession(
        accessToken: map['accessToken'] as String,
        refreshToken: map['refreshToken'] as String,
        role: map['role'] as String,
        email: map['email'] as String,
        userId: map['userId'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshFromFirebase() async {
    await _loadFirebaseSession();
  }

  Future<void> _loadFirebaseSession() async {
    try {
      await FirebaseAppInitializer.initialize();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _session = null;
        await _removeSavedSession();
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!snapshot.exists) {
        _session = null;
        await FirebaseAuth.instance.signOut();
        await _removeSavedSession();
        return;
      }

      final profile = FirebaseDataService.mapFromDoc(snapshot);
      final status = (profile['status'] ?? 'ACTIVE').toString().toUpperCase();
      if (status == 'DEACTIVATED') {
        _session = null;
        await FirebaseAuth.instance.signOut();
        await _removeSavedSession();
        return;
      }

      await save(
        AppSession(
          accessToken: await user.getIdToken() ?? '',
          refreshToken: user.refreshToken ?? '',
          role: (profile['role'] ?? '').toString().toUpperCase(),
          email: (profile['email'] ?? user.email ?? '').toString(),
          userId: user.uid,
        ),
      );
    } catch (_) {
      // Keep the cached session so closing/reopening the app does not become a
      // logout when Firebase is temporarily unavailable during startup.
    }
  }

  Future<void> save(AppSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKey,
      jsonEncode({
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
        'role': session.role,
        'email': session.email,
        'userId': session.userId,
      }),
    );
  }

  Future<void> clear({bool signOut = true}) async {
    _session = null;
    if (signOut) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // Local session cleanup should still succeed.
      }
    }
    await _removeSavedSession();
  }

  Future<void> _removeSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
