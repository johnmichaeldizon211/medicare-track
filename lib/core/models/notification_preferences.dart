class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.medicationCareTaskRemindersEnabled = true,
    this.urgentAlertsEnabled = true,
    this.adminMessagesEnabled = true,
  });

  final bool pushEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool medicationCareTaskRemindersEnabled;
  final bool urgentAlertsEnabled;
  final bool adminMessagesEnabled;

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    return NotificationPreferences(
      pushEnabled: map?['pushEnabled'] as bool? ?? true,
      soundEnabled: map?['soundEnabled'] as bool? ?? true,
      vibrationEnabled: map?['vibrationEnabled'] as bool? ?? true,
      medicationCareTaskRemindersEnabled:
          map?['medicationCareTaskRemindersEnabled'] as bool? ?? true,
      urgentAlertsEnabled: map?['urgentAlertsEnabled'] as bool? ?? true,
      adminMessagesEnabled: map?['adminMessagesEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pushEnabled': pushEnabled,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'medicationCareTaskRemindersEnabled':
          medicationCareTaskRemindersEnabled,
      'urgentAlertsEnabled': urgentAlertsEnabled,
      'adminMessagesEnabled': adminMessagesEnabled,
    };
  }

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? medicationCareTaskRemindersEnabled,
    bool? urgentAlertsEnabled,
    bool? adminMessagesEnabled,
  }) {
    return NotificationPreferences(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      medicationCareTaskRemindersEnabled:
          medicationCareTaskRemindersEnabled ??
          this.medicationCareTaskRemindersEnabled,
      urgentAlertsEnabled: urgentAlertsEnabled ?? this.urgentAlertsEnabled,
      adminMessagesEnabled:
          adminMessagesEnabled ?? this.adminMessagesEnabled,
    );
  }
}
