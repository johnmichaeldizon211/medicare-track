import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class TimeClockService {
  TimeClockService._();

  static final TimeClockService instance = TimeClockService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<Map<String, dynamic>> getMyStatus() async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final logs = await _todayLogsForCaregiver(userId);
      final activeLog = logs
          .where((log) => log['timeOut'] == null)
          .cast<Map<String, dynamic>?>()
          .firstWhere((log) => log != null, orElse: () => null);
      final totalMinutes = logs.fold<int>(
        0,
        (total, log) => total + _minutesForLog(log),
      );
      return {
        'activeLog': activeLog,
        'logs': logs,
        'todayTotalMinutes': totalMinutes,
        'todayTotalHours': _hoursFromMinutes(totalMinutes),
      };
    }, fallbackMessage: 'Unable to load time clock right now.');
  }

  Future<Map<String, dynamic>> timeIn() async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final openLog = await _openLogForCaregiver(userId);
      if (openLog != null) {
        return {'activeLog': openLog, 'created': false};
      }

      final now = DateTime.now().toUtc();
      final ref = _db.collection('caregiverTimeLogs').doc();
      await ref.set({
        'caregiverId': userId,
        'timeIn': FirebaseDataService.timestampFrom(now),
        'timeOut': null,
        'totalMinutes': null,
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      return {
        'activeLog': await _serializeTimeLog(
          FirebaseDataService.mapFromDoc(await ref.get()),
        ),
        'created': true,
      };
    }, fallbackMessage: 'Unable to time in right now.');
  }

  Future<Map<String, dynamic>> timeOut() async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final openLog = await _openLogForCaregiver(userId);
      if (openLog == null) {
        throw ApiException(
          statusCode: 400,
          code: 'NO_ACTIVE_TIME_LOG',
          message: 'No active time-in record found.',
        );
      }

      return {
        'log': await _closeOpenLog(openLog),
        'loggedOut': true,
      };
    }, fallbackMessage: 'Unable to time out right now.');
  }

  Future<Map<String, dynamic>?> timeOutIfActive() async {
    return _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final openLog = await _openLogForCaregiver(userId);
      if (openLog == null) {
        return null;
      }

      return _closeOpenLog(openLog);
    }, fallbackMessage: 'Unable to time out right now.');
  }

  Future<Map<String, dynamic>> getAdminToday() async {
    return _firebase.guard(() async {
      final users =
          FirebaseDataService.mapsFromSnapshot(await _db.collection('users').get())
              .where((user) {
        final role = (user['role'] ?? '').toString().toUpperCase();
        final status = (user['status'] ?? 'ACTIVE').toString().toUpperCase();
        return role == 'CAREGIVER' && status == 'ACTIVE';
      }).toList();
      final logs =
          FirebaseDataService.mapsFromSnapshot(await _db.collection('caregiverTimeLogs').get())
              .where(_logTouchesTodayOrOpen)
              .toList();
      final serializedLogs = <Map<String, dynamic>>[];
      for (final log in logs) {
        serializedLogs.add(await _serializeTimeLog(log, users: users));
      }
      serializedLogs.sort(
        (a, b) => _compareDatesDesc(a['timeIn'], b['timeIn']),
      );

      final caregiverSummaries = users.map((caregiver) {
        final caregiverId = (caregiver['id'] ?? '').toString();
        final caregiverLogs = serializedLogs
            .where((log) => log['caregiverId'] == caregiverId)
            .toList();
        final activeLog = caregiverLogs
            .where((log) => log['timeOut'] == null)
            .cast<Map<String, dynamic>?>()
            .firstWhere((log) => log != null, orElse: () => null);
        final latestLog = caregiverLogs.isEmpty ? null : caregiverLogs.first;
        final totalMinutes = caregiverLogs.fold<int>(
          0,
          (total, log) => total + _safeInt(log['totalMinutes']),
        );
        return {
          'caregiverId': caregiverId,
          'caregiverName': _displayName(caregiver),
          'caregiverEmail': caregiver['email'],
          'isTimedIn': activeLog != null,
          'timeIn': activeLog?['timeIn'] ?? latestLog?['timeIn'],
          'timeOut': latestLog?['timeOut'],
          'totalMinutes': totalMinutes,
          'totalHours': _hoursFromMinutes(totalMinutes),
          'logs': caregiverLogs,
        };
      }).toList();

      final totalMinutes = caregiverSummaries.fold<int>(
        0,
        (total, caregiver) => total + _safeInt(caregiver['totalMinutes']),
      );

      return {
        'date': FirebaseDataService.todayStart().toUtc().toIso8601String(),
        'activeCount': caregiverSummaries
            .where((caregiver) => caregiver['isTimedIn'] == true)
            .length,
        'completedCount':
            serializedLogs.where((log) => log['timeOut'] != null).length,
        'totalMinutes': totalMinutes,
        'totalHours': _hoursFromMinutes(totalMinutes),
        'caregivers': caregiverSummaries,
        'logs': serializedLogs,
      };
    }, fallbackMessage: 'Unable to load caregiver attendance right now.');
  }

  Future<List<Map<String, dynamic>>> _todayLogsForCaregiver(String userId) async {
    final snapshot = await _db
        .collection('caregiverTimeLogs')
        .where('caregiverId', isEqualTo: userId)
        .get();
    final logs = FirebaseDataService.mapsFromSnapshot(snapshot)
        .where(_logTouchesTodayOrOpen)
        .toList();
    final serialized = <Map<String, dynamic>>[];
    for (final log in logs) {
      serialized.add(await _serializeTimeLog(log));
    }
    serialized.sort((a, b) => _compareDatesDesc(a['timeIn'], b['timeIn']));
    return serialized;
  }

  Future<Map<String, dynamic>?> _openLogForCaregiver(String userId) async {
    final snapshot = await _db
        .collection('caregiverTimeLogs')
        .where('caregiverId', isEqualTo: userId)
        .where('timeOut', isNull: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    return _serializeTimeLog(FirebaseDataService.mapFromDoc(snapshot.docs.first));
  }

  Future<Map<String, dynamic>> _closeOpenLog(Map<String, dynamic> openLog) async {
    final ref = _db.collection('caregiverTimeLogs').doc(
          (openLog['id'] ?? '').toString(),
        );
    final now = DateTime.now().toUtc();
    final totalMinutes = _minutesBetween(
      FirebaseDataService.dateTimeFrom(openLog['timeIn']) ?? now,
      now,
    );
    await ref.update({
      'timeOut': FirebaseDataService.timestampFrom(now),
      'totalMinutes': totalMinutes,
      'updatedAt': FirebaseDataService.timestampFrom(now),
    });
    return _serializeTimeLog(FirebaseDataService.mapFromDoc(await ref.get()));
  }

  Future<Map<String, dynamic>> _serializeTimeLog(
    Map<String, dynamic> log, {
    List<Map<String, dynamic>>? users,
  }) async {
    final caregiverId = (log['caregiverId'] ?? '').toString();
    final caregiver = users?.firstWhere(
          (user) => user['id'] == caregiverId,
          orElse: () => <String, dynamic>{},
        ) ??
        await _userById(caregiverId) ??
        <String, dynamic>{};
    final totalMinutes = log['totalMinutes'] == null
        ? _minutesForLog(log)
        : _safeInt(log['totalMinutes']);
    return {
      'id': log['id'],
      'caregiverId': caregiverId,
      'caregiverName': _displayName(caregiver),
      'caregiverEmail': caregiver['email'],
      'timeIn': log['timeIn'],
      'timeOut': log['timeOut'],
      'totalMinutes': totalMinutes,
      'totalHours': _hoursFromMinutes(totalMinutes),
      'isActive': log['timeOut'] == null,
    };
  }

  Future<Map<String, dynamic>?> _userById(String userId) async {
    if (userId.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('users').doc(userId).get();
    return snapshot.exists ? FirebaseDataService.mapFromDoc(snapshot) : null;
  }

  bool _logTouchesTodayOrOpen(Map<String, dynamic> log) {
    if (log['timeOut'] == null) {
      return true;
    }
    return FirebaseDataService.isToday(log['timeIn']) ||
        FirebaseDataService.isToday(log['timeOut']);
  }

  int _minutesForLog(Map<String, dynamic> log) {
    final timeIn = FirebaseDataService.dateTimeFrom(log['timeIn']);
    if (timeIn == null) {
      return 0;
    }
    final timeOut = FirebaseDataService.dateTimeFrom(log['timeOut']);
    return _minutesBetween(timeIn, timeOut ?? DateTime.now());
  }

  int _minutesBetween(DateTime start, DateTime end) {
    return end.difference(start).inMinutes.clamp(0, 1 << 31).toInt();
  }

  double _hoursFromMinutes(int minutes) {
    return (minutes / 60 * 10).round() / 10;
  }

  int _safeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _compareDatesDesc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateB.compareTo(dateA);
  }

  String _displayName(Map<String, dynamic> user) {
    final caregiverProfile = user['caregiverProfile'] as Map<String, dynamic>?;
    return (caregiverProfile?['displayName'] ??
            user['username'] ??
            user['email'] ??
            'Caregiver')
        .toString();
  }
}
