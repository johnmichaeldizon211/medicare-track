import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/conversation_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class ChatDetailScreen extends StatefulWidget {
  final String residentName;
  final bool isReadOnly;
  final String? conversationId;
  final String? conversationTitle;
  final String? conversationSubtitle;

  const ChatDetailScreen({
    super.key,
    required this.residentName,
    required this.isReadOnly,
    this.conversationId,
    this.conversationTitle,
    this.conversationSubtitle,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ConversationService _conversationService = ConversationService.instance;

  final List<Map<String, dynamic>> _messages = [];
  String? _conversationId;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeConversation();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeConversation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final conversations = await _conversationService.getConversations();
      Map<String, dynamic>? conversation;

      if (widget.conversationId != null && widget.conversationId!.isNotEmpty) {
        for (final item in conversations) {
          if ((item['conversationId'] ?? '').toString() ==
              widget.conversationId) {
            conversation = item;
            break;
          }
        }
      }

      conversation ??= _findConversationByResidentName(
        conversations,
        widget.residentName,
      );
      if ((widget.residentName).trim().isEmpty && conversations.isNotEmpty) {
        conversation ??= conversations.first;
      }

      if (conversation == null) {
        setState(() {
          _errorMessage = 'No conversation found for this resident yet.';
          _isLoading = false;
        });
        return;
      }

      _conversationId = (conversation['conversationId'] ?? '').toString();
      await _reloadMessages();
      _listenToMessages();
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Unable to load this conversation right now.';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _findConversationByResidentName(
    List<Map<String, dynamic>> conversations,
    String residentName,
  ) {
    for (final item in conversations) {
      final resident = item['resident'] as Map<String, dynamic>?;
      final name = (resident?['name'] ?? '').toString();
      if (name.toLowerCase() == residentName.toLowerCase()) {
        return item;
      }
    }
    return null;
  }

  Future<void> _reloadMessages() async {
    final conversationId = _conversationId;
    if (conversationId == null || conversationId.isEmpty) {
      return;
    }

    final data = await _conversationService.getMessages(conversationId);
    if (!mounted) {
      return;
    }

    setState(() {
      _messages
        ..clear()
        ..addAll(data);
      _isLoading = false;
    });

    await _markUnreadAsRead();
    _scrollToBottom();
  }

  Future<void> _markUnreadAsRead() async {
    final myUserId = SessionService.instance.session?.userId;
    if (myUserId == null) {
      return;
    }

    for (final message in _messages) {
      final senderId = (message['senderId'] ?? '').toString();
      if (senderId == myUserId) {
        continue;
      }

      final readsRaw = message['reads'] as List<dynamic>? ?? const [];
      final alreadyRead = readsRaw.any((item) {
        final readMap = Map<String, dynamic>.from(item as Map);
        return (readMap['userId'] ?? '').toString() == myUserId;
      });

      if (!alreadyRead) {
        final id = (message['id'] ?? '').toString();
        if (id.isNotEmpty) {
          try {
            await _conversationService.markAsRead(
              id,
              conversationId: _conversationId,
            );
          } catch (_) {
            // keep silent for read sync issues
          }
        }
      }
    }
  }

  void _listenToMessages() {
    final conversationId = _conversationId;
    if (conversationId == null || conversationId.isEmpty) {
      return;
    }

    _messageSubscription?.cancel();
    _messageSubscription = _conversationService.watchMessages(conversationId).listen(
      (messages) {
        if (!mounted) {
          return;
        }
        setState(() {
          _messages
            ..clear()
            ..addAll(messages);
          _isLoading = false;
        });
        _markUnreadAsRead();
        _scrollToBottom();
      },
      onError: (_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = 'Unable to sync messages right now.';
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _appendSentMessage(Map<String, dynamic> message) async {
    final id = (message['id'] ?? '').toString();
    if (id.isEmpty) {
        return;
      }
    final exists = _messages.any(
      (item) => (item['id'] ?? '').toString() == id,
    );
    if (!exists && mounted) {
      setState(() => _messages.add(message));
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    if (_isSending || widget.isReadOnly) {
      return;
    }

    if (_conversationId == null || _conversationId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conversation not ready yet. Please refresh and try again.',
          ),
        ),
      );
      return;
    }

    final content = _messageController.text.trim();
    if (content.isEmpty) {
      return;
    }

    setState(() => _isSending = true);
    try {
      final message = await _conversationService.sendMessage(
        conversationId: _conversationId!,
        content: content,
      );

      if (!mounted) {
        return;
      }

      _messageController.clear();
      await _appendSentMessage(message);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to send message right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 40,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _displaySenderName(Map<String, dynamic> message) {
    final sender = message['sender'] as Map<String, dynamic>?;
    if (sender == null) {
      return 'User';
    }
    final caregiverProfile =
        sender['caregiverProfile'] as Map<String, dynamic>?;
    final familyProfile = sender['familyProfile'] as Map<String, dynamic>?;
    if ((caregiverProfile?['displayName'] as String?)?.isNotEmpty == true) {
      return caregiverProfile!['displayName'] as String;
    }
    if ((familyProfile?['contactName'] as String?)?.isNotEmpty == true) {
      return familyProfile!['contactName'] as String;
    }
    if ((sender['username'] as String?)?.isNotEmpty == true) {
      return sender['username'] as String;
    }
    return (sender['email'] ?? 'User').toString();
  }

  String _displaySenderRole(Map<String, dynamic> message) {
    final sender = message['sender'] as Map<String, dynamic>?;
    final raw = (sender?['role'] ?? '').toString().toUpperCase();
    switch (raw) {
      case 'ADMIN':
        return 'Admin';
      case 'CAREGIVER':
        return 'Caregiver';
      case 'FAMILY':
      default:
        return 'Family';
    }
  }

  String _formatTime(dynamic raw) {
    final source = raw?.toString() ?? '';
    if (source.isEmpty) {
      return '';
    }
    try {
      final dateTime = DateTime.parse(source).toLocal();
      final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    } catch (_) {
      return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = SessionService.instance.session?.userId ?? '';
    final appBarTitle = (widget.conversationTitle ?? 'Messages').trim();
    final appBarSubtitle = (widget.conversationSubtitle ?? widget.residentName)
        .trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              appBarTitle.isEmpty ? 'Messages' : appBarTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (appBarSubtitle.isNotEmpty)
              Text(
                appBarSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_alt, color: Colors.grey.shade400, size: 16),
                const SizedBox(width: 8),
                Text(
                  "Admin conversation",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe =
                          (msg['senderId'] ?? '').toString() == myUserId;
                      return _buildChatBubble(
                        message: (msg['content'] ?? '').toString(),
                        time: _formatTime(msg['createdAt']),
                        isMe: isMe,
                        senderName: _displaySenderName(msg),
                        senderRole: _displaySenderRole(msg),
                      );
                    },
                  ),
          ),
          if (widget.isReadOnly)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: const Text(
                'Read-only conversation view',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatBubble({
    required String message,
    required String time,
    required bool isMe,
    required String senderName,
    required String senderRole,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Padding(
              padding: const EdgeInsets.only(left: 45, bottom: 5),
              child: Row(
                children: [
                  Text(
                    senderName,
                    style: const TextStyle(
                      color: Color(0xFF9575CD),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    senderRole,
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Color(0xFFEDE7F6),
                  child: Icon(Icons.person, color: Color(0xFF9575CD), size: 18),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isMe ? const Color(0xFFFFA726) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isMe
                          ? const Radius.circular(20)
                          : const Radius.circular(5),
                      bottomRight: isMe
                          ? const Radius.circular(5)
                          : const Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              top: 5,
              left: isMe ? 0 : 45,
              right: isMe ? 5 : 0,
            ),
            child: Text(
              time,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: "Write a message...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFA726),
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
