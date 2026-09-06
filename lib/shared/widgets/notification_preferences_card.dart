import 'package:flutter/material.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';

class NotificationPreferencesCard extends StatelessWidget {
  const NotificationPreferencesCard({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.activeColor,
    this.isSaving = false,
  });

  final NotificationPreferences preferences;
  final ValueChanged<NotificationPreferences> onChanged;
  final Color activeColor;
  final bool isSaving;

  void _update(NotificationPreferences next) {
    if (!isSaving) {
      onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = preferences.pushEnabled && !isSaving;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _PreferenceTile(
            icon: Icons.notifications_active_outlined,
            title: 'Push Notifications',
            subtitle: 'Master switch for all alerts',
            value: preferences.pushEnabled,
            activeColor: activeColor,
            onChanged: isSaving
                ? null
                : (value) => _update(
                    preferences.copyWith(pushEnabled: value),
                  ),
          ),
          const _PreferenceDivider(),
          _PreferenceTile(
            icon: Icons.volume_up_outlined,
            title: 'Sound',
            subtitle: 'Play sound with alerts',
            value: preferences.soundEnabled,
            activeColor: activeColor,
            onChanged: controlsEnabled
                ? (value) => _update(
                    preferences.copyWith(soundEnabled: value),
                  )
                : null,
          ),
          const _PreferenceDivider(),
          _PreferenceTile(
            icon: Icons.vibration,
            title: 'Vibration',
            subtitle: 'Vibrate with alerts',
            value: preferences.vibrationEnabled,
            activeColor: activeColor,
            onChanged: controlsEnabled
                ? (value) => _update(
                    preferences.copyWith(vibrationEnabled: value),
                  )
                : null,
          ),
          const _PreferenceDivider(),
          _PreferenceTile(
            icon: Icons.medication_outlined,
            title: 'Medication & Care Task Reminders',
            subtitle: 'New schedules and assignments',
            value: preferences.medicationCareTaskRemindersEnabled,
            activeColor: activeColor,
            onChanged: controlsEnabled
                ? (value) => _update(
                    preferences.copyWith(
                      medicationCareTaskRemindersEnabled: value,
                    ),
                  )
                : null,
          ),
          const _PreferenceDivider(),
          _PreferenceTile(
            icon: Icons.priority_high_rounded,
            title: 'Urgent Alerts & Overdue Updates',
            subtitle: 'Missed tasks and overdue medication',
            value: preferences.urgentAlertsEnabled,
            activeColor: activeColor,
            onChanged: controlsEnabled
                ? (value) => _update(
                    preferences.copyWith(urgentAlertsEnabled: value),
                  )
                : null,
          ),
          const _PreferenceDivider(),
          _PreferenceTile(
            icon: Icons.campaign_outlined,
            title: 'Admin Messages & Announcements',
            subtitle: 'Inbox and facility messages',
            value: preferences.adminMessagesEnabled,
            activeColor: activeColor,
            onChanged: controlsEnabled
                ? (value) => _update(
                    preferences.copyWith(adminMessagesEnabled: value),
                  )
                : null,
          ),
          if (isSaving)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: activeColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;

    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: activeColor.withValues(alpha: enabled ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: enabled ? activeColor : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: enabled ? Colors.black87 : Colors.grey,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}

class _PreferenceDivider extends StatelessWidget {
  const _PreferenceDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      color: Color(0xFFEEEEEE),
      indent: 60,
      endIndent: 20,
    );
  }
}
