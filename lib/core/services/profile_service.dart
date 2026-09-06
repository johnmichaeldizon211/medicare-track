import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<Map<String, dynamic>> getProfile() async {
    return _firebase.guard(() async {
      return _profileForUserId(_firebase.currentUserId);
    }, fallbackMessage: 'Unable to load profile right now.');
  }

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final profile = await _profileForUserId(userId);
      final role = (profile['role'] ?? '').toString().toUpperCase();
      final updates = <String, dynamic>{
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      };

      if (payload.containsKey('username')) {
        updates['username'] = payload['username']?.toString().trim();
      }

      if (role == 'FAMILY') {
        final familyProfile = stringMapFrom(profile['familyProfile']);
        if (payload.containsKey('contactName')) {
          familyProfile['contactName'] = payload['contactName'];
        }
        if (payload.containsKey('relationship')) {
          familyProfile['relationship'] = payload['relationship'];
        }
        if (payload.containsKey('contactNumber')) {
          familyProfile['contactNumber'] = payload['contactNumber'];
        }
        if (payload.containsKey('secondaryContactNumber')) {
          familyProfile['secondaryContactNumber'] =
              payload['secondaryContactNumber'];
        }
        if (payload.containsKey('address')) {
          familyProfile['address'] = payload['address'];
        }
        updates['familyProfile'] = familyProfile;
      }

      if (role == 'CAREGIVER') {
        final caregiverProfile = stringMapFrom(profile['caregiverProfile']);
        if (payload.containsKey('displayName')) {
          caregiverProfile['displayName'] = payload['displayName'];
        }
        if (payload.containsKey('contactNumber')) {
          caregiverProfile['contactNumber'] = payload['contactNumber'];
        }
        if (payload.containsKey('address')) {
          caregiverProfile['address'] = payload['address'];
        }
        updates['caregiverProfile'] = caregiverProfile;
      }

      await _db
          .collection('users')
          .doc(userId)
          .set(updates, SetOptions(merge: true));
      await SessionService.instance.refreshFromFirebase();
      return _profileForUserId(userId);
    }, fallbackMessage: 'Unable to update profile right now.');
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _firebase.guard(() async {
      final user = _firebase.requireUser();
      final email = user.email;
      if (email == null || email.isEmpty) {
        throw ApiException(
          statusCode: 400,
          code: 'EMAIL_REQUIRED',
          message: 'This account has no email login.',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    }, fallbackMessage: 'Unable to update password right now.');
  }

  Future<Map<String, dynamic>> updateNotifications(
    NotificationPreferences preferences,
  ) async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final payload = preferences.toJson();
      await _db.collection('users').doc(userId).set({
        'notificationSetting': payload,
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      }, SetOptions(merge: true));
      return payload;
    }, fallbackMessage: 'Unable to save notification settings.');
  }

  Future<Map<String, dynamic>> createCaregiver({
    required String name,
    required String email,
    required String username,
    required String password,
  }) async {
    return _firebase.guard(() async {
      await _assertAdmin();
      final normalizedEmail = email.trim().toLowerCase();
      final normalizedUsername = username.trim();
      await _assertUniqueUser(normalizedEmail, normalizedUsername);

      final uid = await _createAuthUser(
        email: normalizedEmail,
        password: password,
        displayName: name.trim(),
      );
      final now = DateTime.now().toUtc();
      await _db.collection('users').doc(uid).set({
        'email': normalizedEmail,
        'username': normalizedUsername,
        'role': 'CAREGIVER',
        'status': 'ACTIVE',
        'caregiverProfile': {
          'displayName': name.trim(),
          'contactNumber': '',
          'address': '',
        },
        'notificationSetting': const NotificationPreferences().toJson(),
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      await _createAdminConversationForPeer(uid, 'CAREGIVER');
      return _profileForUserId(uid);
    }, fallbackMessage: 'Unable to create caregiver account right now.');
  }

  Future<Map<String, dynamic>> createFamilyAccount({
    required String email,
    required String username,
    required String password,
    required String contactName,
    required String relationship,
    required String contactNumber,
    String? secondaryContactNumber,
    required String address,
    required String residentName,
    required String residentRoom,
    required int residentAge,
    required String residentBirthday,
    required String residentGender,
    required String residentAddress,
    required List<String> residentConditions,
  }) async {
    return _firebase.guard(() async {
      await _assertAdmin();
      final normalizedEmail = email.trim().toLowerCase();
      final normalizedUsername = username.trim();
      await _assertUniqueUser(normalizedEmail, normalizedUsername);

      final uid = await _createAuthUser(
        email: normalizedEmail,
        password: password,
        displayName: contactName.trim(),
      );
      final now = DateTime.now().toUtc();
      final residentRef = _db.collection('residents').doc();
      final userRef = _db.collection('users').doc(uid);
      final batch = _db.batch();

      batch.set(residentRef, {
        'name': residentName.trim(),
        'room': residentRoom.trim(),
        'age': residentAge,
        'birthday': residentBirthday.trim(),
        'gender': residentGender.trim(),
        'address': residentAddress.trim(),
        'medicalNotes': '',
        'overallStatus': 'STABLE',
        'conditions': FirebaseDataService.conditionMaps(residentConditions),
        'assignedCaregiverIds': <String>[],
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });

      batch.set(userRef, {
        'email': normalizedEmail,
        'username': normalizedUsername,
        'role': 'FAMILY',
        'status': 'ACTIVE',
        'familyProfile': {
          'residentId': residentRef.id,
          'contactName': contactName.trim(),
          'relationship': relationship.trim(),
          'contactNumber': contactNumber.trim(),
          'secondaryContactNumber':
              secondaryContactNumber?.trim().isEmpty == true
              ? null
              : secondaryContactNumber?.trim(),
          'address': address.trim(),
        },
        'notificationSetting': const NotificationPreferences().toJson(),
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });

      final adminIds = await _activeAdminIds();
      final conversationRef = _db.collection('conversations').doc();
      batch.set(conversationRef, {
        'residentId': residentRef.id,
        'type': 'FAMILY',
        'peerId': uid,
        'memberIds': [uid, ...adminIds],
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
        'lastMessage': null,
        'lastMessageAt': null,
      });

      await batch.commit();
      return _profileForUserId(uid);
    }, fallbackMessage: 'Unable to create family account right now.');
  }

  Future<Map<String, dynamic>> updateAdminUser({
    required String userId,
    required String email,
    required String fullName,
    String? primaryContactNumber,
    String? secondaryContactNumber,
    String? address,
    String? relationship,
    Map<String, dynamic>? resident,
  }) async {
    return _firebase.guard(() async {
      await _assertAdmin();
      final profile = await _profileForUserId(userId);
      final role = (profile['role'] ?? '').toString().toUpperCase();
      final normalizedEmail = email.trim().toLowerCase();
      final currentEmail = (profile['email'] ?? '').toString().toLowerCase();

      if (normalizedEmail != currentEmail) {
        throw ApiException(
          statusCode: 400,
          code: 'AUTH_EMAIL_UPDATE_REQUIRED',
          message:
              'Changing another user email requires a Firebase Admin Cloud Function. Keep the current email for now.',
        );
      }

      final updates = <String, dynamic>{
        'email': normalizedEmail,
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      };

      if (role == 'CAREGIVER') {
        updates['caregiverProfile'] = {
          'displayName': fullName.trim(),
          'contactNumber': primaryContactNumber?.trim() ?? '',
          'address': address?.trim() ?? '',
        };
      }

      if (role == 'FAMILY') {
        final familyProfile = stringMapFrom(profile['familyProfile']);
        familyProfile
          ..['contactName'] = fullName.trim()
          ..['relationship'] = relationship?.trim() ?? ''
          ..['contactNumber'] = primaryContactNumber?.trim() ?? ''
          ..['secondaryContactNumber'] =
              secondaryContactNumber?.trim().isEmpty == true
              ? null
              : secondaryContactNumber?.trim()
          ..['address'] = address?.trim() ?? '';
        updates['familyProfile'] = familyProfile;

        final residentId = (familyProfile['residentId'] ?? '').toString();
        if (residentId.isNotEmpty && resident != null) {
          await _db.collection('residents').doc(residentId).set({
            'name': resident['name']?.toString().trim(),
            'room': resident['room']?.toString().trim(),
            'age': resident['age'],
            'birthday': resident['birthday']?.toString().trim(),
            'gender': resident['gender']?.toString().trim(),
            'address': resident['address']?.toString().trim(),
            'conditions': FirebaseDataService.conditionMaps(
              resident['conditions'],
            ),
            'updatedAt': FirebaseDataService.timestampFrom(
              DateTime.now().toUtc(),
            ),
          }, SetOptions(merge: true));
        }
      }

      await _db
          .collection('users')
          .doc(userId)
          .set(updates, SetOptions(merge: true));
      return _profileForUserId(userId);
    }, fallbackMessage: 'Unable to update user right now.');
  }

  Future<void> deactivateUser(String userId) async {
    await _setUserStatus(userId, 'DEACTIVATED');
  }

  Future<void> activateUser(String userId) async {
    await _setUserStatus(userId, 'ACTIVE');
  }

  Future<void> deleteUser(String userId) async {
    await _firebase.guard(() async {
      await _assertAdmin();
      await _db.collection('users').doc(userId).set({
        'status': 'DEACTIVATED',
        'deletedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      }, SetOptions(merge: true));
    }, fallbackMessage: 'Unable to delete user right now.');
  }

  Future<void> deleteMyAccount() async {
    await _firebase.guard(() async {
      await _db.collection('users').doc(_firebase.currentUserId).set({
        'status': 'DEACTIVATED',
        'deletedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      }, SetOptions(merge: true));
      await SessionService.instance.clear();
    }, fallbackMessage: 'Unable to delete account right now.');
  }

  Future<List<dynamic>> listAdminUsers({
    String? role,
    bool includeInactive = false,
  }) async {
    return _firebase.guard(() async {
      await _assertAdmin();
      Query<Map<String, dynamic>> query = _db.collection('users');
      if (role != null && role.isNotEmpty) {
        query = query.where('role', isEqualTo: role.trim().toUpperCase());
      }
      final snapshot = await query.get();
      final users = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final user = await _profileForUserId(doc.id);
        final status = (user['status'] ?? 'ACTIVE').toString().toUpperCase();
        if (!includeInactive && status != 'ACTIVE') {
          continue;
        }
        users.add(user);
      }
      users.sort((a, b) => _compareDatesDesc(a['createdAt'], b['createdAt']));
      return users;
    }, fallbackMessage: 'Unable to load users right now.');
  }

  Future<Map<String, dynamic>> getAdminOverview() async {
    return ReportsService.instance.getOverview();
  }

  Future<Map<String, dynamic>> _profileForUserId(String userId) async {
    final snapshot = await _db.collection('users').doc(userId).get();
    if (!snapshot.exists) {
      throw ApiException(
        statusCode: 404,
        code: 'USER_NOT_FOUND',
        message: 'User not found.',
      );
    }
    final user = FirebaseDataService.mapFromDoc(snapshot);
    user['notificationSetting'] =
        user['notificationSetting'] ?? const NotificationPreferences().toJson();

    final role = (user['role'] ?? '').toString().toUpperCase();
    if (role == 'FAMILY') {
      final familyProfile = stringMapFrom(user['familyProfile']);
      final residentId = (familyProfile['residentId'] ?? '').toString();
      if (residentId.isNotEmpty) {
        final residentSnapshot = await _db
            .collection('residents')
            .doc(residentId)
            .get();
        if (residentSnapshot.exists) {
          final resident = FirebaseDataService.mapFromDoc(residentSnapshot);
          resident['conditions'] = FirebaseDataService.conditionMaps(
            resident['conditions'],
          );
          familyProfile['resident'] = resident;
        }
      }
      user['familyProfile'] = familyProfile;
    }

    if (role == 'CAREGIVER') {
      final assignments = await _db
          .collection('residentAssignments')
          .where('caregiverId', isEqualTo: userId)
          .where('state', isEqualTo: 'ASSIGNED')
          .get();
      final activeAssignments = FirebaseDataService.mapsFromSnapshot(
        assignments,
      ).where((assignment) => assignment['unassignedAt'] == null).toList();
      for (final assignment in activeAssignments) {
        final residentId = (assignment['residentId'] ?? '').toString();
        if (residentId.isEmpty) {
          continue;
        }
        final residentSnapshot = await _db
            .collection('residents')
            .doc(residentId)
            .get();
        if (residentSnapshot.exists) {
          assignment['resident'] = FirebaseDataService.mapFromDoc(
            residentSnapshot,
          );
        }
      }
      user['residentAssignments'] = activeAssignments;
    }

    return user;
  }

  Future<void> _assertAdmin() async {
    final sessionRole = SessionService.instance.session?.role.toUpperCase();
    if (sessionRole == 'ADMIN') {
      return;
    }

    final profile = await _firebase.currentUserProfile();
    if ((profile['role'] ?? '').toString().toUpperCase() == 'ADMIN') {
      return;
    }

    throw ApiException(
      statusCode: 403,
      code: 'ADMIN_ONLY',
      message: 'Admin access required.',
    );
  }

  Future<void> _assertUniqueUser(String email, String username) async {
    final emailMatches = await _db
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (emailMatches.docs.isNotEmpty) {
      throw ApiException(
        statusCode: 409,
        code: 'EMAIL_EXISTS',
        message: 'Email already used.',
      );
    }

    final usernameMatches = await _db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (usernameMatches.docs.isNotEmpty) {
      throw ApiException(
        statusCode: 409,
        code: 'USERNAME_EXISTS',
        message: 'Username already used.',
      );
    }
  }

  Future<String> _createAuthUser({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final defaultApp = Firebase.app();
    final secondaryApp = await Firebase.initializeApp(
      name: 'admin-user-creation-${DateTime.now().microsecondsSinceEpoch}',
      options: defaultApp.options,
    );
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw ApiException(
          statusCode: 0,
          code: 'AUTH_USER_CREATE_FAILED',
          message: 'Unable to create Firebase Auth user.',
        );
      }
      await user.updateDisplayName(displayName);
      return user.uid;
    } finally {
      await secondaryAuth.signOut();
      await secondaryApp.delete();
    }
  }

  Future<void> _createAdminConversationForPeer(
    String peerId,
    String type,
  ) async {
    final adminIds = await _activeAdminIds();
    final now = DateTime.now().toUtc();
    await _db.collection('conversations').add({
      'residentId': null,
      'type': type,
      'peerId': peerId,
      'memberIds': [peerId, ...adminIds],
      'createdAt': FirebaseDataService.timestampFrom(now),
      'updatedAt': FirebaseDataService.timestampFrom(now),
      'lastMessage': null,
      'lastMessageAt': null,
    });
  }

  Future<List<String>> _activeAdminIds() async {
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'ADMIN')
        .where('status', isEqualTo: 'ACTIVE')
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  Future<void> _setUserStatus(String userId, String status) async {
    await _firebase.guard(() async {
      await _assertAdmin();
      await _db.collection('users').doc(userId).set({
        'status': status,
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      }, SetOptions(merge: true));
    }, fallbackMessage: 'Unable to update user status right now.');
  }

  int _compareDatesDesc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateB.compareTo(dateA);
  }
}
