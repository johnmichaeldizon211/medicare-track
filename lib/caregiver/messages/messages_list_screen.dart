import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/messages/chat_detail_screen.dart';
import 'package:medicare_tract/core/services/conversation_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final ConversationService _conversationService = ConversationService.instance;
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final data = await _conversationService.getConversations();
      if (!mounted) return;
      setState(() {
        _conversations = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load conversations right now.';
        _loading = false;
      });
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NA';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _formatLastMessageTime(Map<String, dynamic>? lastMessage) {
    if (lastMessage == null) {
      return '';
    }
    final raw = (lastMessage['createdAt'] ?? '').toString();
    if (raw.isEmpty) {
      return '';
    }
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    } catch (_) {
      return '';
    }
  }

  String _residentContext(String residentName, String room) {
    if (room.isEmpty) {
      return residentName;
    }
    return '$residentName, Room $room';
  }

  String _adminThreadContext(Map<String, dynamic> chat) {
    final residentsRaw = chat['residents'] as List<dynamic>? ?? const [];
    final residents = residentsRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    if (residents.length > 1) {
      return '${residents.length} assigned residents';
    }
    if (residents.length == 1) {
      final name = (residents.first['name'] ?? 'Resident').toString();
      final room = (residents.first['room'] ?? '').toString();
      return _residentContext(name, room);
    }

    final resident = chat['resident'] as Map<String, dynamic>? ?? {};
    final residentName = (resident['name'] ?? 'Assigned residents').toString();
    final room = (resident['room'] ?? '').toString();
    return _residentContext(residentName, room);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > 900 ? 900.0 : null;
        final horizontalPadding = constraints.maxWidth > 700 ? 24.0 : 20.0;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: contentWidth ?? double.infinity,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Messages',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFFA726),
                                ),
                              ),
                              Text(
                                'Admin communication',
                                style: TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Caregiver',
                            style: TextStyle(
                              color: Color(0xFFFFA726),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadConversations,
                      child: _loading
                          ? const InlineLoading(message: 'Loading conversations...')
                          : _errorMessage != null
                              ? ListView(
                                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                  children: [
                                    StatusView.error(
                                      title: 'Could not load messages',
                                      message: _errorMessage!,
                                      onAction: _loadConversations,
                                    ),
                                  ],
                                )
                              : _conversations.isEmpty
                                  ? ListView(
                                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                      children: const [
                                        StatusView.empty(
                                          icon: Icons.chat_bubble_outline,
                                          title: 'No conversations yet',
                                          message: 'Your Admin conversation will appear here.',
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                                      itemCount: _conversations.length,
                                      itemBuilder: (context, index) {
                                        final chat = _conversations[index];
                                        final residentContext = _adminThreadContext(chat);
                                        final unreadCount =
                                            (chat['unreadCount'] as num?)?.toInt() ?? 0;
                                        final hasUnread = unreadCount > 0;
                                        final lastMessage =
                                            chat['lastMessage'] as Map<String, dynamic>?;

                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ChatDetailScreen(
                                                  residentName: residentContext,
                                                  isReadOnly: false,
                                                  conversationId: (chat['conversationId'] ?? '')
                                                      .toString(),
                                                  conversationTitle: 'Admin',
                                                  conversationSubtitle: residentContext,
                                                ),
                                              ),
                                            ).then((_) => _loadConversations());
                                          },
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 15),
                                            padding: const EdgeInsets.all(15),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(15),
                                              border: Border.all(
                                                color: hasUnread
                                                    ? const Color(0xFF00BFA5).withValues(alpha: 0.5)
                                                    : Colors.grey.withValues(alpha: 0.2),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.02),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                CircleAvatar(
                                                  radius: 25,
                                                  backgroundColor: const Color(0xFFE0F2F1),
                                                  child: Text(
                                                    _initials('Admin'),
                                                    style: const TextStyle(
                                                      color: Color(0xFF00BFA5),
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 15),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              'Admin',
                                                              style: TextStyle(
                                                                fontWeight: hasUnread
                                                                    ? FontWeight.bold
                                                                    : FontWeight.w600,
                                                                fontSize: 16,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 10),
                                                          Text(
                                                            _formatLastMessageTime(lastMessage),
                                                            style: TextStyle(
                                                              color: hasUnread
                                                                  ? const Color(0xFFFFA726)
                                                                  : Colors.grey,
                                                              fontSize: 12,
                                                              fontWeight: hasUnread
                                                                  ? FontWeight.bold
                                                                  : FontWeight.normal,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        residentContext,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          color: Color(0xFF00BFA5),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        (lastMessage?['content'] ?? 'No messages yet')
                                                            .toString(),
                                                        style: TextStyle(
                                                          color: hasUnread ? Colors.black87 : Colors.grey,
                                                          fontSize: 13,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                if (hasUnread)
                                                  Container(
                                                    padding: const EdgeInsets.all(6),
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFFFFA726),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Text(
                                                      unreadCount.toString(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  const Icon(
                                                    Icons.chevron_right,
                                                    color: Colors.grey,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
