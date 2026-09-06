import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class ConversationService {
  ConversationService._();

  static final ConversationService instance = ConversationService._();

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  Future<List<Map<String, dynamic>>> getConversations() async {
    return _firebase.guard(() async {
      await _ensureConversationsForCurrentUser();
      final userId = _firebase.currentUserId;
      final snapshot = await _db
          .collection('conversations')
          .where('memberIds', arrayContains: userId)
          .get();
      final conversations = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        conversations.add(await _serializeConversation(doc));
      }
      conversations.sort(
        (a, b) => _compareDatesDesc(
          (a['lastMessage'] as Map<String, dynamic>?)?['createdAt'] ??
              a['updatedAt'],
          (b['lastMessage'] as Map<String, dynamic>?)?['createdAt'] ??
              b['updatedAt'],
        ),
      );
      return conversations;
    }, fallbackMessage: 'Unable to load conversations right now.');
  }

  Future<List<Map<String, dynamic>>> getMessages(String conversationId) async {
    return _firebase.guard(() async {
      await _assertMembership(conversationId);
      final snapshot = await _db
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();
      final messages = FirebaseDataService.mapsFromSnapshot(snapshot);
      for (final message in messages) {
        message['sender'] = await _userById(
          (message['senderId'] ?? '').toString(),
        );
        message['reads'] = _readsList(message);
      }
      messages.sort((a, b) => _compareDatesAsc(a['createdAt'], b['createdAt']));
      return messages;
    }, fallbackMessage: 'Unable to load messages right now.');
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .snapshots()
        .asyncMap((snapshot) async {
          final messages = FirebaseDataService.mapsFromSnapshot(snapshot);
          for (final message in messages) {
            message['sender'] = await _userById(
              (message['senderId'] ?? '').toString(),
            );
            message['reads'] = _readsList(message);
          }
          messages.sort(
            (a, b) => _compareDatesAsc(a['createdAt'], b['createdAt']),
          );
          return messages;
        });
  }

  Future<Map<String, dynamic>> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    return _firebase.guard(() async {
      final conversation = await _assertMembership(conversationId);
      final trimmedContent = content.trim();
      if (trimmedContent.isEmpty) {
        throw ApiException(
          statusCode: 400,
          code: 'EMPTY_MESSAGE',
          message: 'Message cannot be empty.',
        );
      }

      final userId = _firebase.currentUserId;
      final now = DateTime.now().toUtc();
      final conversationRef = _db
          .collection('conversations')
          .doc(conversationId);
      final messageRef = conversationRef.collection('messages').doc();
      final sender = await _userById(userId);
      final messagePayload = {
        'id': messageRef.id,
        'conversationId': conversationId,
        'senderId': userId,
        'content': trimmedContent,
        'reads': [
          {'userId': userId, 'readAt': FirebaseDataService.timestampFrom(now)},
        ],
        'createdAt': FirebaseDataService.timestampFrom(now),
      };
      final lastMessage = {
        'id': messageRef.id,
        'conversationId': conversationId,
        'senderId': userId,
        'content': trimmedContent,
        'createdAt': FirebaseDataService.timestampFrom(now),
      };

      final batch = _db.batch();
      batch.set(messageRef, messagePayload);
      batch.set(conversationRef, {
        'lastMessage': lastMessage,
        'lastMessageAt': FirebaseDataService.timestampFrom(now),
        'updatedAt': FirebaseDataService.timestampFrom(now),
      }, SetOptions(merge: true));

      final memberIds =
          (conversation['memberIds'] as List<dynamic>? ?? const [])
              .map((id) => id.toString())
              .where((id) => id.isNotEmpty && id != userId)
              .toList();
      for (final recipientId in memberIds) {
        final notificationRef = _db.collection('notifications').doc();
        batch.set(notificationRef, {
          'userId': recipientId,
          'category': 'ADMIN_MESSAGE',
          'title': 'New message',
          'body': trimmedContent,
          'data': {
            'conversationId': conversationId,
            'messageId': messageRef.id,
          },
          'sourceKey': 'message:${messageRef.id}:$recipientId',
          'readAt': null,
          'createdAt': FirebaseDataService.timestampFrom(now),
          'updatedAt': FirebaseDataService.timestampFrom(now),
        });
      }

      await batch.commit();

      return FirebaseDataService.normalizeMap({
        ...messagePayload,
        'sender': sender,
      });
    }, fallbackMessage: 'Unable to send message right now.');
  }

  Future<void> markAsRead(String messageId, {String? conversationId}) async {
    await _firebase.guard(() async {
      final userId = _firebase.currentUserId;
      final trimmedMessageId = messageId.trim();
      final trimmedConversationId = conversationId?.trim() ?? '';
      late final DocumentReference<Map<String, dynamic>> ref;
      late final Map<String, dynamic> message;

      if (trimmedMessageId.isEmpty) {
        throw ApiException(
          statusCode: 404,
          code: 'MESSAGE_NOT_FOUND',
          message: 'Message not found.',
        );
      }

      if (trimmedConversationId.isNotEmpty) {
        await _assertMembership(trimmedConversationId);
        ref = _db
            .collection('conversations')
            .doc(trimmedConversationId)
            .collection('messages')
            .doc(trimmedMessageId);
        final snapshot = await ref.get();
        if (!snapshot.exists) {
          throw ApiException(
            statusCode: 404,
            code: 'MESSAGE_NOT_FOUND',
            message: 'Message not found.',
          );
        }
        message = FirebaseDataService.mapFromDoc(snapshot);
      } else {
        final snapshot = await _db
            .collectionGroup('messages')
            .where('id', isEqualTo: trimmedMessageId)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) {
          throw ApiException(
            statusCode: 404,
            code: 'MESSAGE_NOT_FOUND',
            message: 'Message not found.',
          );
        }
        ref = snapshot.docs.first.reference;
        message = FirebaseDataService.mapFromDoc(snapshot.docs.first);
        await _assertMembership((message['conversationId'] ?? '').toString());
      }

      final reads = _readsList(message);
      final hasRead = reads.any((read) => read['userId'] == userId);
      if (!hasRead) {
        reads.add({
          'userId': userId,
          'readAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
        });
      } else {
        for (final read in reads) {
          if (read['userId'] == userId) {
            read['readAt'] = FirebaseDataService.timestampFrom(
              DateTime.now().toUtc(),
            );
          }
        }
      }
      await ref.update({'reads': reads});
    }, fallbackMessage: 'Unable to update message read status.');
  }

  Future<void> _ensureConversationsForCurrentUser() async {
    final profile = await _firebase.currentUserProfile();
    final role = (profile['role'] ?? '').toString().toUpperCase();
    if (role == 'ADMIN') {
      await _ensureAdminConversations();
      return;
    }

    final adminIds = await _activeAdminIds();
    if (adminIds.isEmpty) {
      return;
    }
    final type = role == 'CAREGIVER' ? 'CAREGIVER' : 'FAMILY';
    final userId = (profile['id'] ?? '').toString();
    final existing = await _db
        .collection('conversations')
        .where('memberIds', arrayContains: userId)
        .get();
    final hasExisting = existing.docs.any((doc) {
      final data = doc.data();
      return (data['peerId'] ?? '').toString() == userId &&
          (data['type'] ?? '').toString().toUpperCase() == type;
    });
    if (hasExisting) {
      return;
    }
    final residentId = role == 'FAMILY'
        ? ((profile['familyProfile'] as Map<String, dynamic>?)?['residentId'] ??
                  '')
              .toString()
        : null;
    await _createConversation(
      peerId: userId,
      type: type,
      residentId: residentId?.isEmpty == true ? null : residentId,
      memberIds: [userId, ...adminIds],
    );
  }

  Future<void> _ensureAdminConversations() async {
    final currentAdminId = _firebase.currentUserId;
    final users =
        FirebaseDataService.mapsFromSnapshot(
          await _db.collection('users').get(),
        ).where((user) {
          final role = (user['role'] ?? '').toString().toUpperCase();
          final status = (user['status'] ?? 'ACTIVE').toString().toUpperCase();
          return status == 'ACTIVE' &&
              (role == 'CAREGIVER' || role == 'FAMILY');
        }).toList();
    final adminIds = await _activeAdminIds();
    final existingConversations = FirebaseDataService.mapsFromSnapshot(
      await _db
          .collection('conversations')
          .where('memberIds', arrayContains: currentAdminId)
          .get(),
    );
    final existingKeys = existingConversations
        .map(
          (conversation) =>
              '${(conversation['type'] ?? '').toString().toUpperCase()}:${conversation['peerId'] ?? ''}',
        )
        .toSet();

    for (final user in users) {
      final peerId = (user['id'] ?? '').toString();
      final type = (user['role'] ?? '').toString().toUpperCase();
      final conversationKey = '$type:$peerId';
      if (existingKeys.contains(conversationKey)) {
        continue;
      }
      final residentId = type == 'FAMILY'
          ? ((user['familyProfile'] as Map<String, dynamic>?)?['residentId'] ??
                    '')
                .toString()
          : null;
      await _createConversation(
        peerId: peerId,
        type: type,
        residentId: residentId?.isEmpty == true ? null : residentId,
        memberIds: [peerId, ...adminIds],
      );
      existingKeys.add(conversationKey);
    }
  }

  Future<void> _createConversation({
    required String peerId,
    required String type,
    required String? residentId,
    required List<String> memberIds,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.collection('conversations').add({
      'peerId': peerId,
      'type': type,
      'residentId': residentId,
      'memberIds': memberIds.toSet().toList(),
      'lastMessage': null,
      'lastMessageAt': null,
      'createdAt': FirebaseDataService.timestampFrom(now),
      'updatedAt': FirebaseDataService.timestampFrom(now),
    });
  }

  Future<Map<String, dynamic>> _assertMembership(String conversationId) async {
    final snapshot = await _db
        .collection('conversations')
        .doc(conversationId)
        .get();
    if (!snapshot.exists) {
      throw ApiException(
        statusCode: 404,
        code: 'CONVERSATION_NOT_FOUND',
        message: 'Conversation not found.',
      );
    }
    final conversation = FirebaseDataService.mapFromDoc(snapshot);
    final memberIds = (conversation['memberIds'] as List<dynamic>? ?? const [])
        .map((id) => id.toString())
        .toSet();
    if (!memberIds.contains(_firebase.currentUserId)) {
      throw ApiException(
        statusCode: 403,
        code: 'FORBIDDEN',
        message: 'Conversation access forbidden.',
      );
    }
    return conversation;
  }

  Future<Map<String, dynamic>> _serializeConversation(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final conversation = FirebaseDataService.mapFromDoc(doc);
    final conversationId = doc.id;
    final peer = await _userById((conversation['peerId'] ?? '').toString());
    final resident = await _residentById(
      (conversation['residentId'] ?? '').toString(),
    );
    final isCaregiverConversation =
        (conversation['type'] ?? '').toString().toUpperCase() == 'CAREGIVER';
    final assignedResidents = isCaregiverConversation
        ? await _assignedResidentsForCaregiver(
            (conversation['peerId'] ?? '').toString(),
          )
        : resident == null
        ? <Map<String, dynamic>>[]
        : [resident];
    final lastMessage =
        await _lastMessageFor(conversationId) ??
        (conversation['lastMessage'] as Map<String, dynamic>?);
    final unreadCount = await _unreadCount(conversationId);
    return {
      ...conversation,
      'conversationId': conversationId,
      'peer': peer,
      'resident':
          resident ??
          (assignedResidents.isEmpty ? null : assignedResidents.first),
      'residents': assignedResidents,
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
    };
  }

  Future<Map<String, dynamic>?> _lastMessageFor(String conversationId) async {
    final snapshot = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    final messages = FirebaseDataService.mapsFromSnapshot(snapshot);
    if (messages.isEmpty) {
      return null;
    }
    messages.sort((a, b) => _compareDatesDesc(a['createdAt'], b['createdAt']));
    return messages.first;
  }

  Future<int> _unreadCount(String conversationId) async {
    final userId = _firebase.currentUserId;
    final snapshot = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .get();
    return FirebaseDataService.mapsFromSnapshot(snapshot).where((message) {
      if ((message['senderId'] ?? '').toString() == userId) {
        return false;
      }
      return !_readsList(message).any((read) => read['userId'] == userId);
    }).length;
  }

  Future<Map<String, dynamic>?> _userById(String userId) async {
    if (userId.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('users').doc(userId).get();
    return snapshot.exists ? FirebaseDataService.mapFromDoc(snapshot) : null;
  }

  Future<Map<String, dynamic>?> _residentById(String residentId) async {
    if (residentId.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('residents').doc(residentId).get();
    if (!snapshot.exists) {
      return null;
    }
    final resident = FirebaseDataService.mapFromDoc(snapshot);
    resident['conditions'] = FirebaseDataService.conditionMaps(
      resident['conditions'],
    );
    return resident;
  }

  Future<List<Map<String, dynamic>>> _assignedResidentsForCaregiver(
    String caregiverId,
  ) async {
    if (caregiverId.isEmpty) {
      return [];
    }
    final assignments =
        FirebaseDataService.mapsFromSnapshot(
          await _db
              .collection('residentAssignments')
              .where('caregiverId', isEqualTo: caregiverId)
              .where('state', isEqualTo: 'ASSIGNED')
              .get(),
        ).where(
          (assignment) =>
              assignment['caregiverId'] == caregiverId &&
              (assignment['state'] ?? '').toString().toUpperCase() ==
                  'ASSIGNED' &&
              assignment['unassignedAt'] == null,
        );
    final residents = <Map<String, dynamic>>[];
    for (final assignment in assignments) {
      final resident = await _residentById(
        (assignment['residentId'] ?? '').toString(),
      );
      if (resident != null) {
        residents.add(resident);
      }
    }
    residents.sort(
      (a, b) =>
          (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()),
    );
    return residents;
  }

  Future<List<String>> _activeAdminIds() async {
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'ADMIN')
        .where('status', isEqualTo: 'ACTIVE')
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  List<Map<String, dynamic>> _readsList(Map<String, dynamic> message) {
    return (message['reads'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  int _compareDatesAsc(dynamic a, dynamic b) {
    final dateA = FirebaseDataService.dateTimeFrom(a) ?? DateTime(1970);
    final dateB = FirebaseDataService.dateTimeFrom(b) ?? DateTime(1970);
    return dateA.compareTo(dateB);
  }

  int _compareDatesDesc(dynamic a, dynamic b) => _compareDatesAsc(b, a);
}
