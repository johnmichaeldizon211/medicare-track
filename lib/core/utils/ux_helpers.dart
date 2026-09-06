import 'package:flutter/material.dart';

String greetingForNow([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) {
    return 'Good morning,';
  }
  if (hour < 18) {
    return 'Good afternoon,';
  }
  return 'Good evening,';
}

String initialsForName(String value, {String fallback = '?'}) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return fallback;
  }
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

bool isValidEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

bool hasLetterAndNumber(String value) {
  return RegExp(r'[A-Za-z]').hasMatch(value) && RegExp(r'\d').hasMatch(value);
}

SnackBar appSnackBar(String message, {Color? backgroundColor}) {
  return SnackBar(content: Text(message), backgroundColor: backgroundColor);
}
