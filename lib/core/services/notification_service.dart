import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<List<dynamic>> listNotifications() async {
    return _firebase.guard(() async {
      final snapshot = await _db
          .collection('notifications')
          .where('userId', isEqualTo: _firebase.currentUserId)
          .get();
      final notifications = FirebaseDataService.mapsFromSnapshot(snapshot);
      notifications.sort(
        (a, b) => _compareDatesDesc(a['createdAt'], b['createdAt']),
      );
      return notifications.take(100).toList();
    }, fallbackMessage: 'Unable to load notifications right now.');
  }

  Future<Map<String, dynamic>> markAsRead(String notificationId) async {
    return _firebase.guard(() async {
      final ref = _db.collection('notifications').doc(notificationId);
      final snapshot = await ref.get();
      final notification = FirebaseDataService.mapFromDoc(snapshot);
      if (notification['userId'] != _firebase.currentUserId) {
        throw ApiException(
          statusCode: 404,
          code: 'NOTIFICATION_NOT_FOUND',
          message: 'Notification not found.',
        );
      }
      await ref.update({
        'readAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      });
      return FirebaseDataService.mapFromDoc(await ref.get());
    }, fallbackMessage: 'Unable to mark notification as read.');
  }

  Future<int> markAllAsRead() async {
    return _firebase.guard(() async {
      final snapshot = await _db
          .collection('notifications')
          .where('userId', isEqualTo: _firebase.currentUserId)
          .get();
      final now = FirebaseDataService.timestampFrom(DateTime.now().toUtc());
      final batch = _db.batch();
      var updated = 0;
      for (final doc in snapshot.docs) {
        final data = FirebaseDataService.mapFromDoc(doc);
        if (data['readAt'] != null) {
          continue;
        }
        batch.update(doc.reference, {'readAt': now, 'updatedAt': now});
        updated += 1;
      }
      await batch.commit();
      return updated;
    }, fallbackMessage: 'Unable to mark all notifications as read.');
  }

  int _compareDatesDesc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateB.compareTo(dateA);
  }
}
