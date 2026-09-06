import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:medicare_tract/core/services/firebase_app_initializer.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class FirebaseDataService {
  FirebaseDataService._();

  static final FirebaseDataService instance = FirebaseDataService._();

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;

  Future<void> ensureInitialized() async {
    await FirebaseAppInitializer.initialize();
  }

  User requireUser() {
    final user = auth.currentUser;
    if (user == null) {
      throw ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'Please log in again.',
      );
    }
    return user;
  }

  String get currentUserId => requireUser().uid;

  CollectionReference<Map<String, dynamic>> collection(String path) {
    return db.collection(path);
  }

  DocumentReference<Map<String, dynamic>> document(String path) {
    return db.doc(path);
  }

  Future<Map<String, dynamic>> currentUserProfile() async {
    final user = requireUser();
    final snapshot = await collection('users').doc(user.uid).get();
    if (!snapshot.exists) {
      throw ApiException(
        statusCode: 404,
        code: 'USER_PROFILE_MISSING',
        message:
            'Your Firebase user profile is missing. Ask an admin to create your Firestore user record.',
      );
    }

    final profile = mapFromDoc(snapshot);
    final status = (profile['status'] ?? 'ACTIVE').toString().toUpperCase();
    if (status == 'DEACTIVATED') {
      await auth.signOut();
      throw ApiException(
        statusCode: 403,
        code: 'USER_DISABLED',
        message:
            'Your account has been disabled by the administrator. Please contact support/admin.',
      );
    }

    return profile;
  }

  Future<T> guard<T>(
    Future<T> Function() action, {
    String fallbackMessage = 'Firebase request failed. Please try again.',
  }) async {
    try {
      await ensureInitialized();
      return await action();
    } catch (error) {
      throw mapFirebaseException(error, fallbackMessage: fallbackMessage);
    }
  }

  ApiException mapFirebaseException(
    Object error, {
    String fallbackMessage = 'Firebase request failed. Please try again.',
  }) {
    if (error is ApiException) {
      return error;
    }

    if (error is FirebaseAuthException) {
      return _mapAuthException(error);
    }

    if (error is FirebaseException) {
      final code = error.code.toUpperCase().replaceAll('-', '_');
      final denied = error.code == 'permission-denied';
      return ApiException(
        statusCode: denied ? 403 : 0,
        code: denied ? 'PERMISSION_DENIED' : code,
        message: error.message?.trim().isNotEmpty == true
            ? error.message!
            : fallbackMessage,
      );
    }

    return ApiException(
      statusCode: 0,
      code: 'FIREBASE_ERROR',
      message: fallbackMessage,
    );
  }

  ApiException _mapAuthException(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-not-found':
      case 'wrong-password':
        return ApiException(
          statusCode: 401,
          code: 'INVALID_CREDENTIALS',
          message: 'Invalid email or password.',
        );
      case 'user-disabled':
        return ApiException(
          statusCode: 403,
          code: 'USER_DISABLED',
          message:
              'Your account has been disabled by the administrator. Please contact support/admin.',
        );
      case 'email-already-in-use':
        return ApiException(
          statusCode: 409,
          code: 'EMAIL_EXISTS',
          message: 'Email already used.',
        );
      case 'weak-password':
        return ApiException(
          statusCode: 400,
          code: 'WEAK_PASSWORD',
          message: 'Password must be stronger.',
        );
      case 'requires-recent-login':
        return ApiException(
          statusCode: 401,
          code: 'REQUIRES_RECENT_LOGIN',
          message: 'Please log in again before changing your password.',
        );
      default:
        return ApiException(
          statusCode: 0,
          code: error.code.toUpperCase().replaceAll('-', '_'),
          message: error.message?.trim().isNotEmpty == true
              ? error.message!
              : 'Authentication failed. Please try again.',
        );
    }
  }

  static Map<String, dynamic> mapFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return normalizeMap(<String, dynamic>{
      ...data,
      'id': data['id'] ?? doc.id,
    });
  }

  static List<Map<String, dynamic>> mapsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(mapFromDoc).toList();
  }

  static Map<String, dynamic> normalizeMap(Map<dynamic, dynamic> source) {
    return source.map(
      (key, value) => MapEntry(key.toString(), normalizeValue(value)),
    );
  }

  static dynamic normalizeValue(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc().toIso8601String();
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is DocumentReference) {
      return value.id;
    }
    if (value is Map) {
      return normalizeMap(value);
    }
    if (value is Iterable) {
      return value.map(normalizeValue).toList();
    }
    return value;
  }

  static DateTime? dateTimeFrom(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return DateTime.tryParse(value.toString());
  }

  static Timestamp timestampFrom(DateTime value) {
    return Timestamp.fromDate(value.toUtc());
  }

  static DateTime todayStart([DateTime? now]) {
    final local = now ?? DateTime.now();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime todayEnd([DateTime? now]) {
    return todayStart(now).add(const Duration(days: 1));
  }

  static bool isToday(dynamic value) {
    final date = dateTimeFrom(value)?.toLocal();
    if (date == null) {
      return false;
    }
    final start = todayStart();
    final end = todayEnd();
    return !date.isBefore(start) && date.isBefore(end);
  }

  static List<String> conditionNames(dynamic value) {
    final list = value is Iterable ? value : const [];
    return list
        .map((item) {
          if (item is Map) {
            return (item['name'] ?? '').toString().trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<Map<String, dynamic>> conditionMaps(dynamic value) {
    return conditionNames(value).map((name) => {'name': name}).toList();
  }
}
