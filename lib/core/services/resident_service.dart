import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';

class ResidentService {
  ResidentService._();

  static final ResidentService instance = ResidentService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<List<dynamic>> getResidents({
    String? search,
    String? status,
    bool? unassigned,
  }) async {
    return _firebase.guard(() async {
      final residents = await _loadAccessibleResidentDocs();
      final summaries = <Map<String, dynamic>>[];
      for (final resident in residents) {
        try {
          summaries.add(await _residentSummary(resident));
        } catch (_) {
          summaries.add(_basicResidentSummary(resident));
        }
      }

      final searchTerm = search?.trim().toLowerCase() ?? '';
      final statusFilter = status?.trim().toUpperCase() ?? '';
      return summaries.where((resident) {
        final name = (resident['name'] ?? '').toString().toLowerCase();
        final room = (resident['room'] ?? '').toString().toLowerCase();
        final currentStatus = (resident['overallStatus'] ?? '')
            .toString()
            .toUpperCase();
        final assignedCaregivers = listFrom(resident['assignedCaregivers']);

        if (searchTerm.isNotEmpty &&
            !name.contains(searchTerm) &&
            !room.contains(searchTerm)) {
          return false;
        }
        if (statusFilter.isNotEmpty && currentStatus != statusFilter) {
          return false;
        }
        if (unassigned == true && assignedCaregivers.isNotEmpty) {
          return false;
        }
        return true;
      }).toList();
    }, fallbackMessage: 'Unable to load residents right now.');
  }

  Future<Map<String, dynamic>> getResidentDetail(String residentId) async {
    return _firebase.guard(() async {
      await _ensureResidentAccess(residentId);
      final resident = await _residentById(residentId);
      if (resident == null) {
        throw ApiException(
          statusCode: 404,
          code: 'RESIDENT_NOT_FOUND',
          message: 'Resident not found.',
        );
      }

      final assignments = await _activeAssignmentsForResident(residentId);
      final medications = await _medicationsForResident(residentId);
      final careTasks = await _careTasksForResident(residentId);
      final familyProfile = await _familyProfileForResident(residentId);
      final todayMedicationEvents = _todayMedicationEventsFrom(medications);
      final todayCareTaskEvents = _todayCareTaskEventsFrom(careTasks);
      final missedMedicationCount = _countEventsWithStatus(
        todayMedicationEvents,
        'MISSED',
      );
      final attentionCareTaskCount = _attentionCareTaskCount(
        todayCareTaskEvents,
      );

      return {
        ...resident,
        'overallStatus': _attentionAwareStatus(
          resident['overallStatus'],
          todayMedicationEvents: todayMedicationEvents,
          todayCareTaskEvents: todayCareTaskEvents,
        ),
        'conditions': FirebaseDataService.conditionMaps(resident['conditions']),
        'assignments': assignments,
        'medications': medications,
        'careTasks': careTasks,
        'familyProfile': familyProfile,
        'todayMedicationEventsMissed': missedMedicationCount,
        'todayCareTasksAttention': attentionCareTaskCount,
        'attentionCount': missedMedicationCount + attentionCareTaskCount,
      };
    }, fallbackMessage: 'Unable to load resident details right now.');
  }

  Future<Map<String, dynamic>> createMedication({
    required String residentId,
    required String name,
    required String dosage,
    required String type,
    required String frequency,
    required DateTime startDate,
    required String duration,
    required List<Map<String, String>> reminders,
  }) async {
    return _firebase.guard(() async {
      _assertAdminSession();
      await _ensureResidentAccess(residentId);
      final now = DateTime.now().toUtc();
      final medicationRef = _db.collection('medications').doc();
      final reminderPayload = reminders
          .map(
            (reminder) => {
              'id': _db.collection('medicationReminders').doc().id,
              'time': reminder['time'] ?? '',
              'meal': reminder['meal'] ?? '',
            },
          )
          .toList();

      final batch = _db.batch();
      batch.set(medicationRef, {
        'residentId': residentId,
        'name': name.trim(),
        'dosage': dosage.trim(),
        'type': type.trim(),
        'frequency': frequency.trim(),
        'startDate': FirebaseDataService.timestampFrom(startDate),
        'duration': duration.trim(),
        'reminders': reminderPayload,
        'createdById': SessionService.instance.session?.userId,
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });

      for (final reminder in reminderPayload) {
        final eventRef = _db.collection('medicationEvents').doc();
        batch.set(eventRef, {
          'medicationId': medicationRef.id,
          'residentId': residentId,
          'scheduledAt': FirebaseDataService.timestampFrom(
            _parseTimeToDate(startDate, reminder['time'].toString()),
          ),
          'status': 'PENDING',
          'remark': null,
          'updatedById': null,
          'createdAt': FirebaseDataService.timestampFrom(now),
          'updatedAt': FirebaseDataService.timestampFrom(now),
        });
      }

      await batch.commit();
      return await _medicationById(medicationRef.id) ??
          FirebaseDataService.normalizeMap({
            'id': medicationRef.id,
            'residentId': residentId,
            'name': name,
            'dosage': dosage,
            'type': type,
            'frequency': frequency,
            'startDate': startDate,
            'duration': duration,
            'reminders': reminderPayload,
            'events': const [],
          });
    }, fallbackMessage: 'Unable to create medication right now.');
  }

  Future<Map<String, dynamic>> updateMedication({
    required String medicationId,
    required String name,
    required String dosage,
    required String type,
    required String frequency,
    required DateTime startDate,
    required String duration,
    required List<Map<String, String>> reminders,
  }) async {
    return _firebase.guard(() async {
      _assertAdminSession();
      final existing = await _medicationById(medicationId);
      if (existing == null) {
        throw ApiException(
          statusCode: 404,
          code: 'MEDICATION_NOT_FOUND',
          message: 'Medication not found.',
        );
      }
      await _ensureResidentAccess((existing['residentId'] ?? '').toString());

      final existingEvents = mapListFrom(existing['events']);
      final completed =
          existingEvents.isNotEmpty &&
          existingEvents.every(
            (event) =>
                (event['status'] ?? '').toString().toUpperCase() == 'TAKEN',
          );
      if (completed) {
        throw ApiException(
          statusCode: 400,
          code: 'MEDICATION_COMPLETED',
          message: 'Completed medications cannot be edited.',
        );
      }

      final now = DateTime.now().toUtc();
      final reminderPayload = reminders
          .map(
            (reminder) => {
              'id': _db.collection('medicationReminders').doc().id,
              'time': reminder['time'] ?? '',
              'meal': reminder['meal'] ?? '',
            },
          )
          .toList();
      final oldEvents = await _db
          .collection('medicationEvents')
          .where('medicationId', isEqualTo: medicationId)
          .get();
      final batch = _db.batch();
      for (final doc in oldEvents.docs) {
        batch.delete(doc.reference);
      }
      batch.update(_db.collection('medications').doc(medicationId), {
        'name': name.trim(),
        'dosage': dosage.trim(),
        'type': type.trim(),
        'frequency': frequency.trim(),
        'startDate': FirebaseDataService.timestampFrom(startDate),
        'duration': duration.trim(),
        'reminders': reminderPayload,
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      for (final reminder in reminderPayload) {
        final eventRef = _db.collection('medicationEvents').doc();
        batch.set(eventRef, {
          'medicationId': medicationId,
          'residentId': existing['residentId'],
          'scheduledAt': FirebaseDataService.timestampFrom(
            _parseTimeToDate(startDate, reminder['time'].toString()),
          ),
          'status': 'PENDING',
          'remark': null,
          'updatedById': null,
          'createdAt': FirebaseDataService.timestampFrom(now),
          'updatedAt': FirebaseDataService.timestampFrom(now),
        });
      }
      await batch.commit();
      return await _medicationById(medicationId) ?? existing;
    }, fallbackMessage: 'Unable to update medication right now.');
  }

  Future<void> deleteMedication(String medicationId) async {
    await _firebase.guard(() async {
      _assertAdminSession();
      final existing = await _medicationById(medicationId);
      if (existing != null) {
        await _ensureResidentAccess((existing['residentId'] ?? '').toString());
      }

      final events = await _db
          .collection('medicationEvents')
          .where('medicationId', isEqualTo: medicationId)
          .get();
      final batch = _db.batch();
      for (final doc in events.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_db.collection('medications').doc(medicationId));
      await batch.commit();
    }, fallbackMessage: 'Unable to delete medication right now.');
  }

  Future<List<dynamic>> getResidentMedications(String residentId) async {
    return _firebase.guard(() async {
      await _ensureResidentAccess(residentId);
      return _medicationsForResident(residentId);
    }, fallbackMessage: 'Unable to load medications right now.');
  }

  Future<void> updateMedicationEventStatus({
    required String eventId,
    required String status,
    String? remark,
  }) async {
    await _firebase.guard(() async {
      final eventRef = _db.collection('medicationEvents').doc(eventId);
      final eventSnapshot = await eventRef.get();
      if (!eventSnapshot.exists) {
        throw ApiException(
          statusCode: 404,
          code: 'MEDICATION_EVENT_NOT_FOUND',
          message: 'Medication event not found.',
        );
      }
      final event = FirebaseDataService.mapFromDoc(eventSnapshot);
      final residentId = (event['residentId'] ?? '').toString();
      await _ensureResidentAccess(residentId);

      final userId = _firebase.currentUserId;
      final now = DateTime.now().toUtc();
      final normalizedStatus = status.trim().toUpperCase();
      await eventRef.update({
        'status': normalizedStatus,
        'remark': remark,
        'updatedById': userId,
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });

      final oldStatus = (event['status'] ?? '').toString().toUpperCase();
      if (normalizedStatus == 'TAKEN' && oldStatus != 'TAKEN') {
        final medication = await _medicationById(
          (event['medicationId'] ?? '').toString(),
        );
        await _createActivityLog(
          residentId: residentId,
          activityType: 'MEDICATION',
          itemTitle: (medication?['name'] ?? 'Medication').toString(),
          itemDetails: _compactDetails(
            (medication?['dosage'] ?? '').toString(),
            (medication?['type'] ?? '').toString(),
          ),
          completedAt: now,
          medicationEventId: eventId,
        );
      }
    }, fallbackMessage: 'Unable to update medication status right now.');
  }

  Future<List<dynamic>> getResidentCareTasks(String residentId) async {
    return _firebase.guard(() async {
      await _ensureResidentAccess(residentId);
      return _careTasksForResident(residentId);
    }, fallbackMessage: 'Unable to load care tasks right now.');
  }

  Future<List<dynamic>> getResidentCompletionHistory(
    String residentId, {
    String? type,
    DateTime? start,
    DateTime? end,
  }) async {
    return _firebase.guard(() async {
      await _ensureResidentAccess(residentId);
      final query = _db
          .collection('caregiverActivityLogs')
          .where('residentId', isEqualTo: residentId);

      final typeFilter = type?.trim().toUpperCase();

      final snapshot = await query.get();
      final records = FirebaseDataService.mapsFromSnapshot(snapshot).where((
        record,
      ) {
        final completedAt = FirebaseDataService.dateTimeFrom(
          record['completedAt'],
        );
        final matchesType =
            typeFilter != 'MEDICATION' && typeFilter != 'CARE_TASK'
            ? true
            : (record['activityType'] ?? '').toString().toUpperCase() ==
                  typeFilter;
        final matchesStart =
            start == null ||
            (completedAt != null && !completedAt.isBefore(start));
        final matchesEnd =
            end == null || (completedAt != null && completedAt.isBefore(end));
        return matchesType && matchesStart && matchesEnd;
      }).toList();
      records.sort(
        (a, b) => _compareDatesDesc(a['completedAt'], b['completedAt']),
      );
      for (final record in records) {
        final caregiver = await _userById(
          (record['caregiverId'] ?? '').toString(),
        );
        final resident = await _residentById(
          (record['residentId'] ?? '').toString(),
        );
        record['caregiverName'] = _displayName(caregiver);
        record['residentName'] = (resident?['name'] ?? '').toString();
        record['roomNumber'] = (resident?['room'] ?? '').toString();
        record['type'] =
            (record['activityType'] ?? '').toString().toUpperCase() ==
                'CARE_TASK'
            ? 'Care Task'
            : 'Medication';
      }
      return records;
    }, fallbackMessage: 'Unable to load completion history right now.');
  }

  Future<Map<String, dynamic>> createCareTask({
    required String residentId,
    required String title,
    required String type,
    required String scheduledTime,
    required String frequency,
    String? assignedCaregiverId,
  }) async {
    return _firebase.guard(() async {
      _assertAdminSession();
      await _ensureResidentAccess(residentId);
      final caregiverId =
          assignedCaregiverId ?? await _defaultCaregiverId(residentId);
      final now = DateTime.now().toUtc();
      final ref = _db.collection('careTasks').doc();
      await ref.set({
        'residentId': residentId,
        'title': title.trim(),
        'type': type.trim(),
        'scheduledTime': scheduledTime.trim(),
        'frequency': frequency.trim(),
        'assignedCaregiverId': caregiverId,
        'createdById': SessionService.instance.session?.userId,
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      return _withDailyCareTaskEvent(
        FirebaseDataService.mapFromDoc(await ref.get()),
      );
    }, fallbackMessage: 'Unable to create care task right now.');
  }

  Future<List<dynamic>> createCareTasksBatch({
    required String residentId,
    required List<Map<String, String>> tasks,
    String? assignedCaregiverId,
  }) async {
    return _firebase.guard(() async {
      _assertAdminSession();
      final created = <Map<String, dynamic>>[];
      for (final task in tasks) {
        created.add(
          await createCareTask(
            residentId: residentId,
            title: task['title'] ?? '',
            type: task['type'] ?? '',
            scheduledTime: task['scheduledTime'] ?? '',
            frequency: task['frequency'] ?? 'Daily',
            assignedCaregiverId: assignedCaregiverId,
          ),
        );
      }
      return created;
    }, fallbackMessage: 'Unable to create care tasks right now.');
  }

  Future<Map<String, dynamic>> updateCareTask({
    required String careTaskId,
    required String title,
    required String type,
    required String scheduledTime,
    required String frequency,
  }) async {
    return _firebase.guard(() async {
      _assertAdminSession();
      final ref = _db.collection('careTasks').doc(careTaskId);
      final snapshot = await ref.get();
      if (!snapshot.exists) {
        throw ApiException(
          statusCode: 404,
          code: 'CARE_TASK_NOT_FOUND',
          message: 'Care task not found.',
        );
      }
      final existing = FirebaseDataService.mapFromDoc(snapshot);
      await _ensureResidentAccess((existing['residentId'] ?? '').toString());
      await ref.update({
        'title': title.trim(),
        'type': type.trim(),
        'scheduledTime': scheduledTime.trim(),
        'frequency': frequency.trim(),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      });
      return _withDailyCareTaskEvent(
        FirebaseDataService.mapFromDoc(await ref.get()),
      );
    }, fallbackMessage: 'Unable to update care task right now.');
  }

  Future<void> deleteCareTask(String careTaskId) async {
    await _firebase.guard(() async {
      _assertAdminSession();
      final task = await _db.collection('careTasks').doc(careTaskId).get();
      if (task.exists) {
        final map = FirebaseDataService.mapFromDoc(task);
        await _ensureResidentAccess((map['residentId'] ?? '').toString());
      }
      final batch = _db.batch();
      batch.delete(_db.collection('careTasks').doc(careTaskId));
      batch.delete(_db.collection('careTaskEvents').doc(careTaskId));
      await batch.commit();
    }, fallbackMessage: 'Unable to delete care task right now.');
  }

  Future<void> updateCareTaskStatus({
    required String careTaskId,
    required String status,
    String? remark,
  }) async {
    await _firebase.guard(() async {
      final taskRef = _db.collection('careTasks').doc(careTaskId);
      final taskSnapshot = await taskRef.get();
      if (!taskSnapshot.exists) {
        throw ApiException(
          statusCode: 404,
          code: 'CARE_TASK_NOT_FOUND',
          message: 'Care task not found.',
        );
      }
      final task = FirebaseDataService.mapFromDoc(taskSnapshot);
      final residentId = (task['residentId'] ?? '').toString();
      await _ensureResidentAccess(residentId);

      final eventRef = _db.collection('careTaskEvents').doc(careTaskId);
      final eventSnapshot = await eventRef.get();
      final currentStatus = eventSnapshot.exists
          ? (FirebaseDataService.mapFromDoc(eventSnapshot)['status'] ?? '')
                .toString()
                .toUpperCase()
          : 'PENDING';
      final now = DateTime.now().toUtc();
      final normalizedStatus = status.trim().toUpperCase();
      final userId = _firebase.currentUserId;
      await eventRef.set({
        'careTaskId': careTaskId,
        'residentId': residentId,
        'status': normalizedStatus,
        'remark': remark,
        'timeCompleted': normalizedStatus == 'DONE'
            ? FirebaseDataService.timestampFrom(now)
            : null,
        'updatedById': userId,
        'updatedAt': FirebaseDataService.timestampFrom(now),
      }, SetOptions(merge: true));

      if (normalizedStatus == 'DONE' && currentStatus != 'DONE') {
        await _createActivityLog(
          residentId: residentId,
          activityType: 'CARE_TASK',
          itemTitle: (task['title'] ?? 'Care task').toString(),
          itemDetails: _compactDetails(
            (task['type'] ?? '').toString(),
            (task['scheduledTime'] ?? '').toString(),
          ),
          completedAt: now,
          careTaskEventId: careTaskId,
        );
      }
    }, fallbackMessage: 'Unable to update care task status right now.');
  }

  Future<void> updateMedicalNotes({
    required String residentId,
    required String medicalNotes,
  }) async {
    await _firebase.guard(() async {
      await _ensureResidentAccess(residentId);
      await _db.collection('residents').doc(residentId).update({
        'medicalNotes': medicalNotes.trim(),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      });
    }, fallbackMessage: 'Unable to update medical notes right now.');
  }

  Future<void> assignCaregiver({
    required String residentId,
    required String caregiverId,
  }) async {
    await _firebase.guard(() async {
      _assertAdminSession();
      await _ensureResidentAccess(residentId);
      final existing = await _db
          .collection('residentAssignments')
          .where('residentId', isEqualTo: residentId)
          .where('state', isEqualTo: 'ASSIGNED')
          .get();
      final now = DateTime.now().toUtc();
      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.update(doc.reference, {
          'state': 'UNASSIGNED',
          'unassignedAt': FirebaseDataService.timestampFrom(now),
          'updatedAt': FirebaseDataService.timestampFrom(now),
        });
      }
      batch.update(_db.collection('residents').doc(residentId), {
        'assignedCaregiverIds': [caregiverId],
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      final ref = _db
          .collection('residentAssignments')
          .doc('${residentId}_$caregiverId');
      batch.set(ref, {
        'residentId': residentId,
        'caregiverId': caregiverId,
        'state': 'ASSIGNED',
        'assignedAt': FirebaseDataService.timestampFrom(now),
        'unassignedAt': null,
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      await batch.commit();
    }, fallbackMessage: 'Unable to assign caregiver right now.');
  }

  Future<void> unassignCaregiver({required String residentId}) async {
    await _firebase.guard(() async {
      _assertAdminSession();
      await _ensureResidentAccess(residentId);
      final existing = await _db
          .collection('residentAssignments')
          .where('residentId', isEqualTo: residentId)
          .where('state', isEqualTo: 'ASSIGNED')
          .get();
      final now = DateTime.now().toUtc();
      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.update(doc.reference, {
          'state': 'UNASSIGNED',
          'unassignedAt': FirebaseDataService.timestampFrom(now),
          'updatedAt': FirebaseDataService.timestampFrom(now),
        });
      }
      batch.update(_db.collection('residents').doc(residentId), {
        'assignedCaregiverIds': <String>[],
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      await batch.commit();
    }, fallbackMessage: 'Unable to unassign caregiver right now.');
  }

  Future<List<Map<String, dynamic>>> _loadAccessibleResidentDocs() async {
    final session = SessionService.instance.session;
    final role = session?.role.toUpperCase() ?? '';
    if (role == 'FAMILY') {
      final profile = await _firebase.currentUserProfile();
      final familyProfile = asStringMap(profile['familyProfile']);
      final residentId = (familyProfile?['residentId'] ?? '').toString();
      final resident = await _residentById(residentId);
      return resident == null ? [] : [resident];
    }
    if (role == 'CAREGIVER') {
      final residentIds = await _assignedResidentIdsForCaregiver(
        session?.userId ?? '',
      );
      final residents = <Map<String, dynamic>>[];
      for (final residentId in residentIds) {
        final resident = await _residentById(residentId);
        if (resident != null) {
          residents.add(resident);
        }
      }
      residents.sort(
        (a, b) => (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        ),
      );
      return residents;
    }

    return _allResidents();
  }

  Future<void> _ensureResidentAccess(String residentId) async {
    if (residentId.isEmpty) {
      throw ApiException(
        statusCode: 404,
        code: 'RESIDENT_NOT_FOUND',
        message: 'Resident not found.',
      );
    }

    final session = SessionService.instance.session;
    final role = session?.role.toUpperCase() ?? '';
    if (role == 'ADMIN') {
      return;
    }
    if (role == 'FAMILY') {
      final profile = await _firebase.currentUserProfile();
      final familyProfile = asStringMap(profile['familyProfile']);
      if ((familyProfile?['residentId'] ?? '').toString() == residentId) {
        return;
      }
    }
    if (role == 'CAREGIVER') {
      final hasAssignment = await _caregiverHasResidentAccess(
        residentId,
        session?.userId ?? '',
      );
      if (hasAssignment) {
        return;
      }
    }

    throw ApiException(
      statusCode: 403,
      code: 'FORBIDDEN',
      message: 'Resident access forbidden.',
    );
  }

  void _assertAdminSession() {
    final role = SessionService.instance.session?.role.toUpperCase() ?? '';
    if (role == 'ADMIN') {
      return;
    }

    throw ApiException(
      statusCode: 403,
      code: 'ADMIN_ONLY',
      message: 'Admin access required.',
    );
  }

  Future<bool> _caregiverHasResidentAccess(
    String residentId,
    String caregiverId,
  ) async {
    if (residentId.isEmpty || caregiverId.isEmpty) {
      return false;
    }

    final resident = await _residentById(residentId);
    final assignedCaregiverIds = listFrom(
      resident?['assignedCaregiverIds'],
    ).map((id) => id.toString()).toSet();
    if (assignedCaregiverIds.contains(caregiverId)) {
      return true;
    }

    final assignedResidentIds = await _assignedResidentIdsForCaregiver(
      caregiverId,
    );
    return assignedResidentIds.contains(residentId);
  }

  Future<List<String>> _assignedResidentIdsForCaregiver(
    String caregiverId,
  ) async {
    if (caregiverId.isEmpty) {
      return [];
    }

    final snapshot = await _db
        .collection('residentAssignments')
        .where('caregiverId', isEqualTo: caregiverId)
        .where('state', isEqualTo: 'ASSIGNED')
        .get();
    final ids = FirebaseDataService.mapsFromSnapshot(snapshot)
        .where((assignment) => assignment['unassignedAt'] == null)
        .map((assignment) => (assignment['residentId'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    ids.sort();
    return ids;
  }

  Future<List<Map<String, dynamic>>> _allResidents() async {
    final snapshot = await _db.collection('residents').get();
    final residents = FirebaseDataService.mapsFromSnapshot(snapshot);
    residents.sort(
      (a, b) =>
          (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()),
    );
    return residents;
  }

  Future<Map<String, dynamic>?> _residentById(String residentId) async {
    if (residentId.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('residents').doc(residentId).get();
    return snapshot.exists ? FirebaseDataService.mapFromDoc(snapshot) : null;
  }

  Future<Map<String, dynamic>?> _userById(String userId) async {
    if (userId.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('users').doc(userId).get();
    return snapshot.exists ? FirebaseDataService.mapFromDoc(snapshot) : null;
  }

  Future<Map<String, dynamic>> _residentSummary(
    Map<String, dynamic> resident,
  ) async {
    final residentId = (resident['id'] ?? '').toString();
    final medicationSnapshot = await _db
        .collection('medications')
        .where('residentId', isEqualTo: residentId)
        .get();
    final careTaskSnapshot = await _db
        .collection('careTasks')
        .where('residentId', isEqualTo: residentId)
        .get();
    final assignments = await _activeAssignmentsForResident(residentId);
    final familyProfile = await _familyProfileForResident(residentId);

    final medicationEvents = <Map<String, dynamic>>[];
    for (final medication in medicationSnapshot.docs) {
      final events = await _db
          .collection('medicationEvents')
          .where('medicationId', isEqualTo: medication.id)
          .where('residentId', isEqualTo: residentId)
          .get();
      medicationEvents.addAll(FirebaseDataService.mapsFromSnapshot(events));
    }
    final todayMedicationEvents = medicationEvents
        .where((event) => FirebaseDataService.isToday(event['scheduledAt']))
        .toList();
    final todayMedicationEventsMissed = _countEventsWithStatus(
      todayMedicationEvents,
      'MISSED',
    );

    final careTasks = FirebaseDataService.mapsFromSnapshot(careTaskSnapshot);
    final todayCareTaskEvents = <Map<String, dynamic>>[];
    final todayCompletedCareTasks = <Map<String, dynamic>>[];
    for (final task in careTasks) {
      final event = await _careTaskEventFor((task['id'] ?? '').toString());
      todayCareTaskEvents.add(event);
      if ((event['status'] ?? '').toString().toUpperCase() == 'DONE') {
        todayCompletedCareTasks.add(event);
      }
    }
    final todayCareTasksAttention = _attentionCareTaskCount(
      todayCareTaskEvents,
    );
    final attentionCount =
        todayMedicationEventsMissed + todayCareTasksAttention;

    return {
      'id': residentId,
      'name': resident['name'],
      'room': resident['room'],
      'age': resident['age'],
      'overallStatus': _attentionAwareStatus(
        resident['overallStatus'],
        todayMedicationEvents: todayMedicationEvents,
        todayCareTaskEvents: todayCareTaskEvents,
      ),
      'conditions': FirebaseDataService.conditionNames(resident['conditions']),
      'assignedCaregivers': assignments.map((assignment) {
        final caregiver = asStringMap(assignment['caregiver']);
        return {
          'id': (assignment['caregiverId'] ?? caregiver?['id'] ?? '')
              .toString(),
          'name': _displayName(caregiver),
        };
      }).toList(),
      'medicationCount': medicationSnapshot.docs.length,
      'careTaskCount': careTaskSnapshot.docs.length,
      'todayMedicationEventsTotal': todayMedicationEvents.length,
      'todayMedicationEventsCompleted': todayMedicationEvents
          .where(
            (event) =>
                (event['status'] ?? '').toString().toUpperCase() == 'TAKEN',
          )
          .length,
      'todayMedicationEventsMissed': todayMedicationEventsMissed,
      'todayCareTasksTotal': careTasks.length,
      'todayCareTasksCompleted': todayCompletedCareTasks.length,
      'todayCareTasksAttention': todayCareTasksAttention,
      'attentionCount': attentionCount,
      'familyEmail': asStringMap(familyProfile?['user'])?['email'],
    };
  }

  Map<String, dynamic> _basicResidentSummary(Map<String, dynamic> resident) {
    return {
      'id': (resident['id'] ?? '').toString(),
      'name': resident['name'],
      'room': resident['room'],
      'age': resident['age'],
      'overallStatus': _normalizedStatus(resident['overallStatus']).isEmpty
          ? 'STABLE'
          : _normalizedStatus(resident['overallStatus']),
      'conditions': FirebaseDataService.conditionNames(resident['conditions']),
      'assignedCaregivers': const [],
      'medicationCount': 0,
      'careTaskCount': 0,
      'todayMedicationEventsTotal': 0,
      'todayMedicationEventsCompleted': 0,
      'todayMedicationEventsMissed': 0,
      'todayCareTasksTotal': 0,
      'todayCareTasksCompleted': 0,
      'todayCareTasksAttention': 0,
      'attentionCount': 0,
      'familyEmail': null,
    };
  }

  Future<List<Map<String, dynamic>>> _activeAssignmentsForResident(
    String residentId,
  ) async {
    var query = _db
        .collection('residentAssignments')
        .where('residentId', isEqualTo: residentId)
        .where('state', isEqualTo: 'ASSIGNED');
    final session = SessionService.instance.session;
    final role = session?.role.toUpperCase() ?? '';
    if (role == 'CAREGIVER') {
      query = query.where('caregiverId', isEqualTo: session?.userId ?? '');
    }

    final snapshot = await query.get();
    final assignments = FirebaseDataService.mapsFromSnapshot(
      snapshot,
    ).where((assignment) => assignment['unassignedAt'] == null).toList();
    for (final assignment in assignments) {
      assignment['caregiver'] = await _userById(
        (assignment['caregiverId'] ?? '').toString(),
      );
    }
    return assignments;
  }

  Future<Map<String, dynamic>?> _familyProfileForResident(
    String residentId,
  ) async {
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'FAMILY')
        .where('familyProfile.residentId', isEqualTo: residentId)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }

    final user = FirebaseDataService.mapFromDoc(snapshot.docs.first);
    final profile = stringMapFrom(user['familyProfile']);
    return {
      ...profile,
      'userId': user['id'],
      'residentId': residentId,
      'user': user,
    };
  }

  Future<List<Map<String, dynamic>>> _medicationsForResident(
    String residentId,
  ) async {
    final snapshot = await _db
        .collection('medications')
        .where('residentId', isEqualTo: residentId)
        .get();
    final medications = FirebaseDataService.mapsFromSnapshot(snapshot);
    for (final medication in medications) {
      medication['events'] = await _medicationEventsFor(
        (medication['id'] ?? '').toString(),
        residentId: residentId,
      );
    }
    medications.sort(
      (a, b) => _compareDatesDesc(a['createdAt'], b['createdAt']),
    );
    return medications;
  }

  Future<Map<String, dynamic>?> _medicationById(String medicationId) async {
    if (medicationId.isEmpty) {
      return null;
    }
    final snapshot = await _db
        .collection('medications')
        .doc(medicationId)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    final medication = FirebaseDataService.mapFromDoc(snapshot);
    medication['events'] = await _medicationEventsFor(
      medicationId,
      residentId: (medication['residentId'] ?? '').toString(),
    );
    return medication;
  }

  Future<List<Map<String, dynamic>>> _medicationEventsFor(
    String medicationId, {
    String? residentId,
  }) async {
    var query = _db
        .collection('medicationEvents')
        .where('medicationId', isEqualTo: medicationId);
    if (residentId != null && residentId.isNotEmpty) {
      query = query.where('residentId', isEqualTo: residentId);
    }
    final snapshot = await query.get();
    final events = FirebaseDataService.mapsFromSnapshot(snapshot);
    events.sort((a, b) => _compareDatesAsc(a['scheduledAt'], b['scheduledAt']));
    return events;
  }

  Future<List<Map<String, dynamic>>> _careTasksForResident(
    String residentId,
  ) async {
    final snapshot = await _db
        .collection('careTasks')
        .where('residentId', isEqualTo: residentId)
        .get();
    final tasks = FirebaseDataService.mapsFromSnapshot(snapshot);
    final result = <Map<String, dynamic>>[];
    for (final task in tasks) {
      result.add(await _withDailyCareTaskEvent(task));
    }
    result.sort((a, b) => _compareDatesAsc(a['createdAt'], b['createdAt']));
    return result;
  }

  Future<Map<String, dynamic>> _withDailyCareTaskEvent(
    Map<String, dynamic> task,
  ) async {
    return {
      ...task,
      'event': await _careTaskEventFor((task['id'] ?? '').toString(), task),
    };
  }

  Future<Map<String, dynamic>> _careTaskEventFor(
    String careTaskId, [
    Map<String, dynamic>? task,
  ]) async {
    final snapshot = await _db
        .collection('careTaskEvents')
        .doc(careTaskId)
        .get();
    if (snapshot.exists) {
      final event = FirebaseDataService.mapFromDoc(snapshot);
      if (FirebaseDataService.isToday(event['updatedAt'])) {
        return event;
      }
    }

    final resolvedTask =
        task ??
        FirebaseDataService.mapFromDoc(
          await _db.collection('careTasks').doc(careTaskId).get(),
        );
    final residentId = (resolvedTask['residentId'] ?? '').toString();
    final scheduledAt = _parseTimeToDate(
      FirebaseDataService.todayStart(),
      (resolvedTask['scheduledTime'] ?? '').toString(),
    );
    return {
      'id': null,
      'careTaskId': careTaskId,
      'residentId': residentId,
      'status': 'PENDING',
      'remark': null,
      'timeCompleted': null,
      'updatedById': null,
      'updatedAt': scheduledAt.toUtc().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _todayMedicationEventsFrom(
    List<Map<String, dynamic>> medications,
  ) {
    final todayEvents = <Map<String, dynamic>>[];
    for (final medication in medications) {
      for (final eventMap in mapListFrom(medication['events'])) {
        if (FirebaseDataService.isToday(eventMap['scheduledAt'])) {
          todayEvents.add(eventMap);
        }
      }
    }
    return todayEvents;
  }

  List<Map<String, dynamic>> _todayCareTaskEventsFrom(
    List<Map<String, dynamic>> careTasks,
  ) {
    final todayEvents = <Map<String, dynamic>>[];
    for (final task in careTasks) {
      final event = task['event'];
      if (event is! Map) {
        continue;
      }
      final eventMap = Map<String, dynamic>.from(event);
      if (FirebaseDataService.isToday(eventMap['updatedAt'])) {
        todayEvents.add(eventMap);
      }
    }
    return todayEvents;
  }

  String _attentionAwareStatus(
    dynamic baseStatus, {
    required List<Map<String, dynamic>> todayMedicationEvents,
    required List<Map<String, dynamic>> todayCareTaskEvents,
  }) {
    final normalized = _normalizedStatus(baseStatus);
    if (normalized == 'CRITICAL') {
      return 'CRITICAL';
    }

    final hasMissedMedication =
        _countEventsWithStatus(todayMedicationEvents, 'MISSED') > 0;
    final hasAttentionCareTask =
        _attentionCareTaskCount(todayCareTaskEvents) > 0;
    if (hasMissedMedication || hasAttentionCareTask) {
      return 'NEEDS_ATTENTION';
    }

    return normalized.isEmpty ? 'STABLE' : normalized;
  }

  int _countEventsWithStatus(List<Map<String, dynamic>> events, String status) {
    return events
        .where((event) => _normalizedStatus(event['status']) == status)
        .length;
  }

  int _attentionCareTaskCount(List<Map<String, dynamic>> events) {
    return events.where((event) {
      final status = _normalizedStatus(event['status']);
      return status == 'MISSED' || status == 'DELAYED';
    }).length;
  }

  String _normalizedStatus(dynamic value) {
    return (value ?? '').toString().trim().toUpperCase();
  }

  Future<String?> _defaultCaregiverId(String residentId) async {
    final assignments = await _activeAssignmentsForResident(residentId);
    if (assignments.isEmpty) {
      return null;
    }
    return (assignments.first['caregiverId'] ?? '').toString();
  }

  Future<void> _createActivityLog({
    required String residentId,
    required String activityType,
    required String itemTitle,
    String? itemDetails,
    required DateTime completedAt,
    String? medicationEventId,
    String? careTaskEventId,
  }) async {
    final caregiverId = _firebase.currentUserId;
    if (caregiverId.isEmpty) {
      return;
    }
    await _db.collection('caregiverActivityLogs').add({
      'caregiverId': caregiverId,
      'residentId': residentId,
      'activityType': activityType,
      'itemTitle': itemTitle,
      'itemDetails': itemDetails,
      'completedAt': FirebaseDataService.timestampFrom(completedAt),
      'medicationEventId': medicationEventId,
      'careTaskEventId': careTaskEventId,
      'createdAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
    });
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

  int _compareDatesAsc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateA.compareTo(dateB);
  }

  int _compareDatesDesc(dynamic a, dynamic b) {
    return _compareDatesAsc(b, a);
  }

  String _displayName(Map<String, dynamic>? user) {
    if (user == null) {
      return 'Caregiver';
    }
    final caregiverProfile = asStringMap(user['caregiverProfile']);
    final familyProfile = asStringMap(user['familyProfile']);
    return (caregiverProfile?['displayName'] ??
            familyProfile?['contactName'] ??
            user['username'] ??
            user['email'] ??
            'Caregiver')
        .toString();
  }

  String? _compactDetails(String first, String second) {
    final values = [
      first.trim(),
      second.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return values.isEmpty ? null : values.join(' - ');
  }
}
