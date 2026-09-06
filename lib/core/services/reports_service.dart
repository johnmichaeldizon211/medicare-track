import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';

class ReportsService {
  ReportsService._();

  static final ReportsService instance = ReportsService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<Map<String, dynamic>> getOverview() async {
    return _firebase.guard(() async {
      final residents = await _db.collection('residents').get();
      final medicationEvents =
          FirebaseDataService.mapsFromSnapshot(
                await _db.collection('medicationEvents').get(),
              )
              .where(
                (event) => FirebaseDataService.isToday(event['scheduledAt']),
              )
              .toList();
      final careTasks = FirebaseDataService.mapsFromSnapshot(
        await _db.collection('careTasks').get(),
      );
      final careTaskEvents =
          FirebaseDataService.mapsFromSnapshot(
                await _db.collection('careTaskEvents').get(),
              )
              .where((event) => FirebaseDataService.isToday(event['updatedAt']))
              .toList();

      final takenMedicationEvents = medicationEvents
          .where((event) => _status(event['status']) == 'TAKEN')
          .length;
      final missedMedicationEvents = medicationEvents
          .where((event) => _status(event['status']) == 'MISSED')
          .length;
      final doneTaskEvents = careTaskEvents
          .where((event) => _status(event['status']) == 'DONE')
          .length;

      final totalMedicationEvents = medicationEvents.length;
      final totalTaskEvents = careTasks.length;

      return {
        'totalResidents': residents.docs.length,
        'totalMedicationEvents': totalMedicationEvents,
        'takenMedicationEvents': takenMedicationEvents,
        'missedMedicationEvents': missedMedicationEvents,
        'totalTaskEvents': totalTaskEvents,
        'doneTaskEvents': doneTaskEvents,
        'medCompliance': totalMedicationEvents == 0
            ? 0
            : ((takenMedicationEvents / totalMedicationEvents) * 100).round(),
        'taskCompletion': totalTaskEvents == 0
            ? 0
            : ((doneTaskEvents / totalTaskEvents) * 100).round(),
      };
    }, fallbackMessage: 'Unable to load overview right now.');
  }

  Future<List<dynamic>> getCaregiverPerformance() async {
    return _firebase.guard(() async {
      final currentSession = SessionService.instance.session;
      final currentRole = currentSession?.role.toUpperCase() ?? '';
      final currentUserId = currentSession?.userId ?? '';

      if (currentRole != 'ADMIN' && currentRole != 'CAREGIVER') {
        return [];
      }

      final users = currentRole == 'CAREGIVER'
          ? await _currentCaregiverUser(currentUserId)
          : FirebaseDataService.mapsFromSnapshot(
              await _db.collection('users').get(),
            ).where((user) {
              final isCaregiver = _status(user['role']) == 'CAREGIVER';
              final isActive =
                  _status(user['status']).isEmpty ||
                  _status(user['status']) == 'ACTIVE';
              return isCaregiver && isActive;
            }).toList();
      final assignments = currentRole == 'CAREGIVER'
          ? await _activeAssignmentsForCaregiver(currentUserId)
          : FirebaseDataService.mapsFromSnapshot(
                  await _db.collection('residentAssignments').get(),
                )
                .where(
                  (assignment) =>
                      _status(assignment['state']) == 'ASSIGNED' &&
                      assignment['unassignedAt'] == null,
                )
                .toList();
      final assignedResidentIds = currentRole == 'CAREGIVER'
          ? assignments
                .map(
                  (assignment) => (assignment['residentId'] ?? '').toString(),
                )
                .where((id) => id.isNotEmpty)
                .toList()
          : const <String>[];
      final medicationEvents = currentRole == 'CAREGIVER'
          ? await _todayMedicationEventsUpdatedBy(
              currentUserId,
              assignedResidentIds,
            )
          : FirebaseDataService.mapsFromSnapshot(
                  await _db.collection('medicationEvents').get(),
                )
                .where(
                  (event) => FirebaseDataService.isToday(event['updatedAt']),
                )
                .toList();
      final careTaskEvents = currentRole == 'CAREGIVER'
          ? await _todayCareTaskEventsUpdatedBy(
              currentUserId,
              assignedResidentIds,
            )
          : FirebaseDataService.mapsFromSnapshot(
                  await _db.collection('careTaskEvents').get(),
                )
                .where(
                  (event) => FirebaseDataService.isToday(event['updatedAt']),
                )
                .toList();
      final careTasks = currentRole == 'CAREGIVER'
          ? FirebaseDataService.mapsFromSnapshot(
              await _db
                  .collection('careTasks')
                  .where('assignedCaregiverId', isEqualTo: currentUserId)
                  .get(),
            )
          : FirebaseDataService.mapsFromSnapshot(
              await _db.collection('careTasks').get(),
            );

      return users.map((caregiver) {
        final caregiverId = (caregiver['id'] ?? '').toString();
        final assignedResidents = assignments
            .where((assignment) => assignment['caregiverId'] == caregiverId)
            .length;
        final caregiverMedicationEvents = medicationEvents
            .where((event) => event['updatedById'] == caregiverId)
            .toList();
        final medicationsGiven = caregiverMedicationEvents
            .where((event) => _status(event['status']) == 'TAKEN')
            .length;
        final medicationsMissed = caregiverMedicationEvents
            .where((event) => _status(event['status']) == 'MISSED')
            .length;
        final medicationsTotal = caregiverMedicationEvents.length;
        final tasksDone = careTaskEvents
            .where(
              (event) =>
                  event['updatedById'] == caregiverId &&
                  _status(event['status']) == 'DONE',
            )
            .length;
        final tasksTotal = careTasks
            .where((task) => task['assignedCaregiverId'] == caregiverId)
            .length;
        final scores = <double>[
          if (medicationsTotal > 0) medicationsGiven / medicationsTotal * 100,
          if (tasksTotal > 0) tasksDone / tasksTotal * 100,
        ];
        final score = scores.isEmpty
            ? 0
            : (scores.reduce((total, value) => total + value) / scores.length)
                  .round();

        return {
          'caregiverId': caregiverId,
          'caregiverName': _displayName(caregiver),
          'assignedResidents': assignedResidents,
          'medicationsGiven': medicationsGiven,
          'medicationsMissed': medicationsMissed,
          'medicationsTotal': medicationsTotal,
          'tasksDone': tasksDone,
          'tasksTotal': tasksTotal,
          'score': score,
        };
      }).toList();
    }, fallbackMessage: 'Unable to load caregiver performance right now.');
  }

  Future<Map<String, dynamic>> getCaregiverActivityHistory({
    String? caregiverId,
    DateTime? start,
    DateTime? end,
  }) async {
    return _firebase.guard(() async {
      final users =
          FirebaseDataService.mapsFromSnapshot(
            await _db.collection('users').get(),
          ).where((user) {
            final isCaregiver = _status(user['role']) == 'CAREGIVER';
            final isActive =
                _status(user['status']).isEmpty ||
                _status(user['status']) == 'ACTIVE';
            return isCaregiver && isActive;
          }).toList();
      final residents = FirebaseDataService.mapsFromSnapshot(
        await _db.collection('residents').get(),
      );
      final logs =
          FirebaseDataService.mapsFromSnapshot(
            await _db.collection('caregiverActivityLogs').get(),
          ).where((log) {
            final selectedCaregiverId =
                caregiverId == null ||
                    caregiverId.isEmpty ||
                    caregiverId == 'all'
                ? null
                : caregiverId;
            final completedAt = FirebaseDataService.dateTimeFrom(
              log['completedAt'],
            );
            final matchesCaregiver =
                selectedCaregiverId == null ||
                log['caregiverId'] == selectedCaregiverId;
            final matchesStart =
                start == null ||
                (completedAt != null && !completedAt.isBefore(start));
            final matchesEnd =
                end == null ||
                (completedAt != null && completedAt.isBefore(end));
            return matchesCaregiver && matchesStart && matchesEnd;
          }).toList();
      logs.sort(
        (a, b) => _compareDatesDesc(a['completedAt'], b['completedAt']),
      );

      return {
        'caregivers': users
            .map(
              (caregiver) => {
                'caregiverId': caregiver['id'],
                'caregiverName': _displayName(caregiver),
                'caregiverEmail': caregiver['email'],
              },
            )
            .toList(),
        'records': logs.take(500).map((log) {
          final caregiver = users.firstWhere(
            (user) => user['id'] == log['caregiverId'],
            orElse: () => <String, dynamic>{},
          );
          final resident = residents.firstWhere(
            (item) => item['id'] == log['residentId'],
            orElse: () => <String, dynamic>{},
          );

          return {
            'id': log['id'],
            'caregiverId': log['caregiverId'],
            'caregiverName': _displayName(caregiver),
            'residentId': log['residentId'],
            'residentName': resident['name'] ?? 'Resident',
            'roomNumber': resident['room'] ?? '',
            'type': _status(log['activityType']) == 'CARE_TASK'
                ? 'Care Task'
                : 'Medication',
            'itemTitle': log['itemTitle'],
            'itemDetails': log['itemDetails'],
            'completedAt': log['completedAt'],
          };
        }).toList(),
      };
    }, fallbackMessage: 'Unable to load caregiver activity right now.');
  }

  Future<List<dynamic>> getShiftTimeline() async {
    return _firebase.guard(() async {
      final residentIds = await _accessibleResidentIds();
      if (residentIds.isEmpty) {
        return [];
      }

      final residents = await _residentDocsByIds(residentIds);
      final medications = await _collectionByResidentIds(
        'medications',
        residentIds,
      );
      final medicationEvents =
          (await _collectionByResidentIds('medicationEvents', residentIds))
              .where(
                (event) => FirebaseDataService.isToday(event['scheduledAt']),
              )
              .toList();
      final careTasks = await _collectionByResidentIds(
        'careTasks',
        residentIds,
      );

      final now = DateTime.now();
      final timeline = <Map<String, dynamic>>[];
      for (final event in medicationEvents) {
        final medication = medications.firstWhere(
          (item) => item['id'] == event['medicationId'],
          orElse: () => <String, dynamic>{},
        );
        final resident = residents.firstWhere(
          (item) => item['id'] == event['residentId'],
          orElse: () => <String, dynamic>{},
        );
        final scheduledAt = FirebaseDataService.dateTimeFrom(
          event['scheduledAt'],
        );
        final urgentExpiresAt = _urgentExpiresAt(scheduledAt, now);
        timeline.add({
          'id': event['id'],
          'kind': 'medication',
          'title': medication['name'] ?? 'Medication',
          'residentName': resident['name'] ?? 'Resident',
          'scheduledAt': event['scheduledAt'],
          'urgentExpiresAt': urgentExpiresAt?.toUtc().toIso8601String(),
          'status': event['status'] ?? 'PENDING',
          'urgent': _isUrgent(event['status'], scheduledAt, now),
        });
      }

      for (final task in careTasks) {
        final taskId = (task['id'] ?? '').toString();
        final resident = residents.firstWhere(
          (item) => item['id'] == task['residentId'],
          orElse: () => <String, dynamic>{},
        );
        final taskEvent = await _careTaskEventByTaskId(taskId);
        final scheduledAt = _parseTimeToDate(
          FirebaseDataService.todayStart(),
          (task['scheduledTime'] ?? '').toString(),
        );
        final status =
            taskEvent != null &&
                FirebaseDataService.isToday(taskEvent['updatedAt'])
            ? taskEvent['status'] ?? 'PENDING'
            : 'PENDING';
        final urgentExpiresAt = _urgentExpiresAt(scheduledAt, now);
        timeline.add({
          'id': taskId,
          'kind': 'care_task',
          'taskType': task['type'],
          'title': task['title'] ?? 'Care task',
          'residentName': resident['name'] ?? 'Resident',
          'scheduledAt': scheduledAt.toUtc().toIso8601String(),
          'urgentExpiresAt': urgentExpiresAt?.toUtc().toIso8601String(),
          'status': status,
          'urgent': _isUrgent(status, scheduledAt, now),
        });
      }

      timeline.sort(
        (a, b) => _compareDatesAsc(a['scheduledAt'], b['scheduledAt']),
      );
      return timeline;
    }, fallbackMessage: 'Unable to load shift timeline right now.');
  }

  Future<List<String>> _accessibleResidentIds() async {
    final session = SessionService.instance.session;
    final role = session?.role.toUpperCase() ?? '';
    if (role == 'FAMILY') {
      final profile = await _firebase.currentUserProfile();
      final familyProfile = profile['familyProfile'] as Map<String, dynamic>?;
      final residentId = (familyProfile?['residentId'] ?? '').toString();
      return residentId.isEmpty ? [] : [residentId];
    }
    if (role == 'CAREGIVER') {
      return _assignedResidentIdsForCaregiver(session?.userId ?? '');
    }
    if (role != 'ADMIN') {
      return [];
    }
    final residents = FirebaseDataService.mapsFromSnapshot(
      await _db.collection('residents').get(),
    );
    return residents
        .map((resident) => (resident['id'] ?? '').toString())
        .toList();
  }

  Future<List<Map<String, dynamic>>> _currentCaregiverUser(
    String userId,
  ) async {
    if (userId.isEmpty) {
      return [];
    }

    final snapshot = await _db.collection('users').doc(userId).get();
    if (!snapshot.exists) {
      return [];
    }

    final user = FirebaseDataService.mapFromDoc(snapshot);
    final isCaregiver = _status(user['role']) == 'CAREGIVER';
    final isActive =
        _status(user['status']).isEmpty || _status(user['status']) == 'ACTIVE';
    return isCaregiver && isActive ? [user] : [];
  }

  Future<List<Map<String, dynamic>>> _activeAssignmentsForCaregiver(
    String caregiverId,
  ) async {
    if (caregiverId.isEmpty) {
      return [];
    }

    return FirebaseDataService.mapsFromSnapshot(
      await _db
          .collection('residentAssignments')
          .where('caregiverId', isEqualTo: caregiverId)
          .where('state', isEqualTo: 'ASSIGNED')
          .get(),
    ).where((assignment) => assignment['unassignedAt'] == null).toList();
  }

  Future<List<String>> _assignedResidentIdsForCaregiver(
    String caregiverId,
  ) async {
    final assignments = await _activeAssignmentsForCaregiver(caregiverId);
    final ids = assignments
        .map((assignment) => (assignment['residentId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    ids.sort();
    return ids;
  }

  Future<List<Map<String, dynamic>>> _residentDocsByIds(
    List<String> residentIds,
  ) async {
    final residents = <Map<String, dynamic>>[];
    for (final residentId in residentIds) {
      final snapshot = await _db.collection('residents').doc(residentId).get();
      if (snapshot.exists) {
        residents.add(FirebaseDataService.mapFromDoc(snapshot));
      }
    }
    return residents;
  }

  Future<List<Map<String, dynamic>>> _collectionByResidentIds(
    String collection,
    List<String> residentIds,
  ) async {
    final records = <Map<String, dynamic>>[];
    for (final residentId in residentIds) {
      records.addAll(
        FirebaseDataService.mapsFromSnapshot(
          await _db
              .collection(collection)
              .where('residentId', isEqualTo: residentId)
              .get(),
        ),
      );
    }
    return records;
  }

  Future<Map<String, dynamic>?> _careTaskEventByTaskId(
    String careTaskId,
  ) async {
    if (careTaskId.isEmpty) {
      return null;
    }

    final snapshot = await _db
        .collection('careTaskEvents')
        .doc(careTaskId)
        .get();
    return snapshot.exists ? FirebaseDataService.mapFromDoc(snapshot) : null;
  }

  Future<List<Map<String, dynamic>>> _todayMedicationEventsUpdatedBy(
    String userId,
    List<String> residentIds,
  ) async {
    if (userId.isEmpty || residentIds.isEmpty) {
      return [];
    }

    return (await _collectionByResidentIds('medicationEvents', residentIds))
        .where(
          (event) =>
              event['updatedById'] == userId &&
              FirebaseDataService.isToday(event['updatedAt']),
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> _todayCareTaskEventsUpdatedBy(
    String userId,
    List<String> residentIds,
  ) async {
    if (userId.isEmpty || residentIds.isEmpty) {
      return [];
    }

    return (await _collectionByResidentIds('careTaskEvents', residentIds))
        .where(
          (event) =>
              event['updatedById'] == userId &&
              FirebaseDataService.isToday(event['updatedAt']),
        )
        .toList();
  }

  bool _isUrgent(dynamic status, DateTime? scheduledAt, DateTime now) {
    if (scheduledAt == null) {
      return false;
    }
    final normalized = _status(status);
    if (normalized == 'TAKEN' ||
        normalized == 'DONE' ||
        normalized == 'COMPLETED') {
      return false;
    }
    return !now.isBefore(scheduledAt) &&
        now.isBefore(FirebaseDataService.todayEnd(now));
  }

  DateTime? _urgentExpiresAt(DateTime? scheduledAt, DateTime now) {
    if (scheduledAt == null) {
      return null;
    }
    return FirebaseDataService.todayEnd(now);
  }

  DateTime _parseTimeToDate(DateTime base, String time) {
    final match = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(time.trim());
    var hour = 0;
    var minute = 0;
    if (match != null) {
      hour = int.tryParse(match.group(1) ?? '') ?? 0;
      minute = int.tryParse(match.group(2) ?? '') ?? 0;
      final modifier = (match.group(3) ?? '').toUpperCase();
      if (modifier == 'PM' && hour < 12) {
        hour += 12;
      }
      if (modifier == 'AM' && hour == 12) {
        hour = 0;
      }
    }
    return DateTime(base.year, base.month, base.day, hour, minute);
  }

  String _displayName(Map<String, dynamic> user) {
    final caregiverProfile = user['caregiverProfile'] as Map<String, dynamic>?;
    final familyProfile = user['familyProfile'] as Map<String, dynamic>?;
    return (caregiverProfile?['displayName'] ??
            familyProfile?['contactName'] ??
            user['username'] ??
            user['email'] ??
            'Caregiver')
        .toString();
  }

  String _status(dynamic value) => (value ?? '').toString().toUpperCase();

  int _compareDatesAsc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateA.compareTo(dateB);
  }

  int _compareDatesDesc(dynamic a, dynamic b) => _compareDatesAsc(b, a);
}
