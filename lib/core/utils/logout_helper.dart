import 'package:flutter/material.dart';
import 'package:medicare_tract/core/navigation/auth_navigation.dart';
import 'package:medicare_tract/core/services/auth_service.dart';

Future<void> performLogout(BuildContext context) async {
  try {
    await AuthService.instance.logout();
  } catch (_) {
    // local cleanup still happens in AuthService, so we ignore remote failures here
  }

  if (!context.mounted) {
    return;
  }

  goToEntryScreen(context);
}

Future<void> confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Sign Out Confirmation'),
        content: const Text('Are you sure you want to sign out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign Out'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) {
    return;
  }

  if (confirmed == true) {
    await performLogout(context);
  }
}
