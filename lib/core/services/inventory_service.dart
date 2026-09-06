import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class InventoryService {
  InventoryService._();

  static final InventoryService instance = InventoryService._();
  static const int expirationAlertWindowDays = 30;

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<List<dynamic>> getMedicineInventory({String? search}) async {
    return _firebase.guard(() async {
      final snapshot = await _db.collection('medicineInventory').get();
      final term = search?.trim().toLowerCase() ?? '';
      final items = FirebaseDataService.mapsFromSnapshot(snapshot)
          .where(
            (item) =>
                term.isEmpty ||
                (item['name'] ?? '').toString().toLowerCase().contains(term),
          )
          .toList();
      items.sort(_compareInventoryItems);
      return items;
    }, fallbackMessage: 'Unable to load medicine inventory right now.');
  }

  Future<Map<String, dynamic>> createMedicine({
    required String name,
    required int count,
    DateTime? expirationDate,
  }) async {
    return _firebase.guard(() async {
      final normalizedName = name.trim();
      final existing = await _db
          .collection('medicineInventory')
          .where('name', isEqualTo: normalizedName)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        throw ApiException(
          statusCode: 409,
          code: 'MEDICINE_EXISTS',
          message: 'Medicine already exists in inventory.',
        );
      }

      final now = DateTime.now().toUtc();
      final ref = _db.collection('medicineInventory').doc();
      await ref.set({
        'name': normalizedName,
        'count': count < 0 ? 0 : count,
        'expirationDate': expirationDate == null
            ? null
            : FirebaseDataService.timestampFrom(_dateOnlyUtc(expirationDate)),
        'createdAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      });
      return FirebaseDataService.mapFromDoc(await ref.get());
    }, fallbackMessage: 'Unable to create medicine right now.');
  }

  Future<Map<String, dynamic>> updateMedicine({
    required String id,
    required String name,
    required int count,
    DateTime? expirationDate,
  }) async {
    return _firebase.guard(() async {
      final normalizedName = name.trim();
      final existing = await _db
          .collection('medicineInventory')
          .where('name', isEqualTo: normalizedName)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty && existing.docs.first.id != id) {
        throw ApiException(
          statusCode: 409,
          code: 'MEDICINE_EXISTS',
          message: 'Medicine already exists in inventory.',
        );
      }

      final ref = _db.collection('medicineInventory').doc(id);
      await ref.update({
        'name': normalizedName,
        'count': count < 0 ? 0 : count,
        'expirationDate': expirationDate == null
            ? null
            : FirebaseDataService.timestampFrom(_dateOnlyUtc(expirationDate)),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      });
      return FirebaseDataService.mapFromDoc(await ref.get());
    }, fallbackMessage: 'Unable to update medicine right now.');
  }

  Future<Map<String, dynamic>> adjustMedicine({
    required String id,
    required int delta,
  }) async {
    return _firebase.guard(() async {
      final ref = _db.collection('medicineInventory').doc(id);
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          throw ApiException(
            statusCode: 404,
            code: 'MEDICINE_NOT_FOUND',
            message: 'Medicine not found.',
          );
        }
        final current = _safeInt(snapshot.data()?['count']);
        final next = current + delta;
        if (next < 0) {
          throw ApiException(
            statusCode: 400,
            code: 'INVALID_STOCK_COUNT',
            message: 'Medicine count cannot go below zero.',
          );
        }
        transaction.update(ref, {
          'count': next,
          'updatedAt': FirebaseDataService.timestampFrom(
            DateTime.now().toUtc(),
          ),
        });
      });
      return FirebaseDataService.mapFromDoc(await ref.get());
    }, fallbackMessage: 'Unable to adjust medicine stock right now.');
  }

  Future<void> deleteMedicine({required String id}) async {
    await _firebase.guard(() async {
      await _db.collection('medicineInventory').doc(id).delete();
    }, fallbackMessage: 'Unable to delete medicine right now.');
  }

  Future<int> syncExpirationAlerts({
    required List<Map<String, dynamic>> items,
    int daysAhead = expirationAlertWindowDays,
  }) async {
    if (items.isEmpty) {
      return 0;
    }

    return _firebase.guard(() async {
      final today = _today();
      final alertItems = items.where((item) {
        final days = _daysUntilExpiration(item['expirationDate'], today);
        return days != null && days <= daysAhead;
      }).toList();
      if (alertItems.isEmpty) {
        return 0;
      }

      final adminSnapshot = await _db
          .collection('users')
          .where('role', isEqualTo: 'ADMIN')
          .get();
      final adminIds = adminSnapshot.docs
          .map(FirebaseDataService.mapFromDoc)
          .where((user) {
            final status = (user['status'] ?? 'ACTIVE')
                .toString()
                .toUpperCase();
            return status == 'ACTIVE';
          })
          .map((user) => (user['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
      if (adminIds.isEmpty) {
        return 0;
      }

      var created = 0;
      var pendingWrites = 0;
      var batch = _db.batch();
      final now = DateTime.now().toUtc();
      final nowTimestamp = FirebaseDataService.timestampFrom(now);

      Future<void> commitPending() async {
        if (pendingWrites == 0) {
          return;
        }
        await batch.commit();
        batch = _db.batch();
        pendingWrites = 0;
      }

      for (final item in alertItems) {
        final itemId = (item['id'] ?? '').toString();
        final name = (item['name'] ?? 'Medicine').toString();
        final expirationDate = _expirationDate(item['expirationDate']);
        final days = _daysUntilExpiration(item['expirationDate'], today);
        if (itemId.isEmpty || expirationDate == null || days == null) {
          continue;
        }

        final dateKey = _dateKey(expirationDate);
        final expired = days < 0;
        final title = expired
            ? 'Medicine expired'
            : days == 0
            ? 'Medicine expires today'
            : 'Medicine expiring soon';
        final body = expired
            ? '$name expired on ${_formatDate(expirationDate)}.'
            : '$name expires on ${_formatDate(expirationDate)} '
                  '($days day${days == 1 ? '' : 's'} left).';

        for (final adminId in adminIds) {
          final sourceKey =
              'medicine-expiration:$itemId:$dateKey:user:$adminId';
          final notificationRef = _db
              .collection('notifications')
              .doc(sourceKey);
          final existing = await notificationRef.get();
          if (existing.exists) {
            continue;
          }

          batch.set(notificationRef, {
            'userId': adminId,
            'category': 'URGENT_ALERT',
            'title': title,
            'body': body,
            'data': {
              'type': 'medicine_expiration',
              'medicineId': itemId,
              'medicineName': name,
              'expirationDate': FirebaseDataService.timestampFrom(
                _dateOnlyUtc(expirationDate),
              ),
              'daysUntilExpiration': days,
            },
            'sourceKey': sourceKey,
            'readAt': null,
            'createdAt': nowTimestamp,
            'updatedAt': nowTimestamp,
          });
          pendingWrites += 1;
          created += 1;

          if (pendingWrites >= 400) {
            await commitPending();
          }
        }
      }

      await commitPending();
      return created;
    }, fallbackMessage: 'Unable to sync medicine expiration alerts.');
  }

  int _safeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _compareInventoryItems(Map<String, dynamic> a, Map<String, dynamic> b) {
    final rankCompare = _expirationRank(
      a['expirationDate'],
    ).compareTo(_expirationRank(b['expirationDate']));
    if (rankCompare != 0) {
      return rankCompare;
    }

    final dateA = _expirationDate(a['expirationDate']);
    final dateB = _expirationDate(b['expirationDate']);
    if (dateA != null && dateB != null) {
      final dateCompare = dateA.compareTo(dateB);
      if (dateCompare != 0) {
        return dateCompare;
      }
    }

    final countCompare = _safeInt(a['count']).compareTo(_safeInt(b['count']));
    if (countCompare != 0) {
      return countCompare;
    }
    return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
  }

  int _expirationRank(dynamic value) {
    final days = _daysUntilExpiration(value, _today());
    if (days == null) {
      return 3;
    }
    if (days < 0) {
      return 0;
    }
    if (days <= expirationAlertWindowDays) {
      return 1;
    }
    return 2;
  }

  DateTime? _expirationDate(dynamic value) {
    final parsed = FirebaseDataService.dateTimeFrom(value);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  int? _daysUntilExpiration(dynamic value, DateTime today) {
    final expirationDate = _expirationDate(value);
    if (expirationDate == null) {
      return null;
    }
    return expirationDate.difference(today).inDays;
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _dateOnlyUtc(DateTime value) {
    return DateTime.utc(value.year, value.month, value.day);
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}
