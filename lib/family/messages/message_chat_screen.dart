import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/messages/chat_detail_screen.dart';

class MessageChatScreen extends StatelessWidget {
  final String residentName;
  final bool isReadOnly;
  final String? conversationId;

  const MessageChatScreen({
    super.key,
    this.residentName = '',
    this.isReadOnly = false,
    this.conversationId,
  });

  @override
  Widget build(BuildContext context) {
    return ChatDetailScreen(
      residentName: residentName,
      isReadOnly: isReadOnly,
      conversationId: conversationId,
      conversationTitle: 'Admin',
    );
  }
}
