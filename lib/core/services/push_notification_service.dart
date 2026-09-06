import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';
import 'package:medicare_tract/core/services/firebase_app_initializer.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
Future<void> medicareTrackFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await FirebaseAppInitializer.initialize();
  } catch (_) {
    // Firebase may be intentionally unconfigured in local builds.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const MethodChannel _platformChannel = MethodChannel(
    'medicare_tract/notifications',
  );

  static const String highImportanceChannelId =
      'medicare_tract_high_importance_sound_v2';
  static const String highImportanceChannelName =
      'Medicare Track urgent alerts';
  static const String highImportanceChannelDescription =
      'Heads-up alerts for urgent care updates, medications, and admin messages.';
  static const String taskReminderChannelId =
      'medicare_tract_task_reminders_sound_v2';
  static const String taskReminderChannelName = 'Care task reminders';
  static const String taskReminderChannelDescription =
      'Medication and care task reminders before scheduled care times.';
  static const String taskAlarmChannelId =
      'medicare_tract_task_alarms_sound_v2';
  static const String taskAlarmChannelName = 'Care task alarms';
  static const String taskAlarmChannelDescription =
      'Alarm-style alerts when medication or care tasks are due.';
  static const String _taskPayloadPrefix = 'caregiver_task:';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static final Int64List _reminderVibrationPattern = Int64List.fromList([
    0,
    350,
    180,
    350,
  ]);
  static final Int64List _alarmVibrationPattern = Int64List.fromList([
    0,
    700,
    250,
    700,
    250,
    900,
  ]);

  bool _initialized = false;
  bool _firebaseAvailable = false;
  bool _timeZoneConfigured = false;
  bool _exactAlarmPermissionRequested = false;
  String? _lastTaskReminderFingerprint;
  final Set<String> _shownImmediateReminderKeys = {};
  final Set<String> _shownImmediateAlarmKeys = {};

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      await FirebaseAppInitializer.initialize();
      _firebaseAvailable = true;
    } catch (_) {
      _firebaseAvailable = false;
      return;
    }

    if (kIsWeb) {
      return;
    }

    await _configureLocalTimeZone();
    FirebaseMessaging.onBackgroundMessage(
      medicareTrackFirebaseMessagingBackgroundHandler,
    );

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );

    final androidNotifications = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await _createAndroidNotificationChannels(androidNotifications);

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerToken);
  }

  Future<void> _createAndroidNotificationChannels(
    AndroidFlutterLocalNotificationsPlugin? androidNotifications,
  ) async {
    if (androidNotifications == null) {
      return;
    }

    await androidNotifications.createNotificationChannel(
      AndroidNotificationChannel(
        highImportanceChannelId,
        highImportanceChannelName,
        description: highImportanceChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _reminderVibrationPattern,
        showBadge: true,
      ),
    );
    await androidNotifications.createNotificationChannel(
      AndroidNotificationChannel(
        taskReminderChannelId,
        taskReminderChannelName,
        description: taskReminderChannelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _reminderVibrationPattern,
        showBadge: true,
      ),
    );
    await androidNotifications.createNotificationChannel(
      AndroidNotificationChannel(
        taskAlarmChannelId,
        taskAlarmChannelName,
        description: taskAlarmChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _alarmVibrationPattern,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }

  Future<void> registerDeviceToken() async {
    if (!_firebaseAvailable || SessionService.instance.session == null) {
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _registerToken(token);
    } catch (_) {
      // Push should never block normal app startup.
    }
  }

  Future<void> unregisterDeviceToken() async {
    if (!_firebaseAvailable || SessionService.instance.session == null) {
      return;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        return;
      }

      final userId = SessionService.instance.session!.userId;
      final tokenDocId = Uri.encodeComponent(token);
      final payload = {
        'isActive': false,
        'lastSeenAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('devicePushTokens')
          .doc(tokenDocId)
          .set(payload, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('pushTokens')
          .doc(Uri.encodeComponent(token))
          .set(payload, SetOptions(merge: true));
    } catch (_) {
      // Token cleanup is best-effort and should not block logout.
    }
  }

  Future<void> syncLoggedInCaregiverTaskReminders() async {
    if (kIsWeb) {
      return;
    }

    final session = SessionService.instance.session;
    if (session == null || session.role.toUpperCase() != 'CAREGIVER') {
      return;
    }

    try {
      final timeline = await ReportsService.instance.getShiftTimeline();
      final tasks = timeline
          .map(_taskReminderFromTimelineItem)
          .whereType<TaskReminderScheduleItem>()
          .toList();
      await syncCaregiverTaskReminders(tasks);
    } catch (_) {
      // Dashboard refresh will try again when the caregiver opens the app.
    }
  }

  Future<void> _registerToken(String? token) async {
    if (token == null ||
        token.isEmpty ||
        SessionService.instance.session == null) {
      return;
    }

    try {
      final userId = SessionService.instance.session!.userId;
      final tokenDocId = Uri.encodeComponent(token);
      final payload = {
        'userId': userId,
        'token': token,
        'platform': _platformName,
        'isActive': true,
        'lastSeenAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      };

      await FirebaseFirestore.instance
          .collection('devicePushTokens')
          .doc(tokenDocId)
          .set({
            ...payload,
            'createdAt': Timestamp.now(),
          }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('pushTokens')
          .doc(Uri.encodeComponent(token))
          .set(payload, SetOptions(merge: true));
    } catch (_) {
      // Token registration will retry on next app launch or token refresh.
    }
  }

  Future<void> syncCaregiverTaskReminders(
    List<TaskReminderScheduleItem> tasks,
  ) async {
    if (kIsWeb) {
      return;
    }

    await initialize();
    await _configureLocalTimeZone();

    final session = SessionService.instance.session;
    if (session == null || session.role.toUpperCase() != 'CAREGIVER') {
      return;
    }

    final remindersEnabled = await _taskRemindersEnabled(session.userId);
    final pendingTasks =
        tasks
            .where(
              (task) =>
                  task.isPending &&
                  task.scheduledAt.isAfter(
                    DateTime.now().subtract(const Duration(minutes: 1)),
                  ),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final fingerprint =
        '${session.userId}|$remindersEnabled|${pendingTasks.map(_taskFingerprint).join(';')}';
    if (_lastTaskReminderFingerprint == fingerprint) {
      return;
    }
    _lastTaskReminderFingerprint = fingerprint;

    await _cancelPendingCaregiverTaskNotifications();
    if (!remindersEnabled || pendingTasks.isEmpty) {
      return;
    }

    await _requestExactAlarmPermissionIfNeeded();
    final now = DateTime.now();
    for (final task in pendingTasks) {
      final reminderAt = task.scheduledAt.subtract(const Duration(minutes: 5));
      if (reminderAt.isAfter(now)) {
        await _scheduleTaskNotification(
          task: task,
          scheduledAt: reminderAt,
          isAlarm: false,
        );
      } else if (now.isBefore(task.scheduledAt) &&
          task.scheduledAt.difference(now) <= const Duration(minutes: 5)) {
        final key = '${task.id}:${task.scheduledAt.toIso8601String()}:reminder';
        if (_shownImmediateReminderKeys.add(key)) {
          await _showTaskNotification(task: task, isAlarm: false);
        }
      }

      if (task.scheduledAt.isAfter(now)) {
        await _scheduleTaskNotification(
          task: task,
          scheduledAt: task.scheduledAt,
          isAlarm: true,
        );
      } else if (now.difference(task.scheduledAt) <=
          const Duration(minutes: 1)) {
        final key = '${task.id}:${task.scheduledAt.toIso8601String()}:alarm';
        if (_shownImmediateAlarmKeys.add(key)) {
          await _showTaskNotification(task: task, isAlarm: true);
        }
      }
    }
  }

  TaskReminderScheduleItem? _taskReminderFromTimelineItem(dynamic item) {
    if (item is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(item);
    final scheduledAt = DateTime.tryParse(
      (map['scheduledAt'] ?? '').toString(),
    )?.toLocal();
    if (scheduledAt == null) {
      return null;
    }

    final kind = (map['kind'] ?? '').toString().toLowerCase();
    final taskType = (map['taskType'] ?? '').toString().toLowerCase();
    final type = kind == 'medication'
        ? 'medication'
        : taskType.contains('meal')
        ? 'meal'
        : 'care';

    if (kind != 'medication' && kind != 'care_task') {
      return null;
    }

    return TaskReminderScheduleItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? 'Care task').toString(),
      residentName: (map['residentName'] ?? 'Unknown resident').toString(),
      type: type,
      status: (map['status'] ?? 'PENDING').toString(),
      scheduledAt: scheduledAt,
    );
  }

  Future<bool> _taskRemindersEnabled(String userId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final preferences = NotificationPreferences.fromMap(
        data['notificationSetting'] is Map
            ? Map<String, dynamic>.from(data['notificationSetting'] as Map)
            : null,
      );
      return preferences.pushEnabled &&
          preferences.medicationCareTaskRemindersEnabled;
    } catch (_) {
      return true;
    }
  }

  Future<void> _scheduleTaskNotification({
    required TaskReminderScheduleItem task,
    required DateTime scheduledAt,
    required bool isAlarm,
  }) async {
    final scheduledLocal = scheduledAt.toLocal();
    if (!scheduledLocal.isAfter(DateTime.now())) {
      return;
    }

    final id = _taskNotificationId(task, isAlarm: isAlarm);
    final payload = _taskPayload(task, isAlarm: isAlarm);
    final scheduleMode = isAlarm
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.exactAllowWhileIdle;

    try {
      await _localNotifications.zonedSchedule(
        id: id,
        title: _taskNotificationTitle(isAlarm),
        body: _taskNotificationBody(task),
        scheduledDate: _tzDateTime(scheduledLocal),
        notificationDetails: _taskNotificationDetails(isAlarm),
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
      _debugLogScheduledTask(task, scheduledLocal, isAlarm);
    } on PlatformException catch (error) {
      if (error.code != 'exact_alarms_not_permitted') {
        rethrow;
      }
      await _localNotifications.zonedSchedule(
        id: id,
        title: _taskNotificationTitle(isAlarm),
        body: _taskNotificationBody(task),
        scheduledDate: _tzDateTime(scheduledLocal),
        notificationDetails: _taskNotificationDetails(isAlarm),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      _debugLogScheduledTask(task, scheduledLocal, isAlarm, inexact: true);
    }
  }

  Future<void> _showTaskNotification({
    required TaskReminderScheduleItem task,
    required bool isAlarm,
  }) async {
    await _localNotifications.show(
      id: _taskNotificationId(task, isAlarm: isAlarm),
      title: _taskNotificationTitle(isAlarm),
      body: _taskNotificationBody(task),
      notificationDetails: _taskNotificationDetails(isAlarm),
      payload: _taskPayload(task, isAlarm: isAlarm),
    );
  }

  NotificationDetails _taskNotificationDetails(bool isAlarm) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        isAlarm ? taskAlarmChannelId : taskReminderChannelId,
        isAlarm ? taskAlarmChannelName : taskReminderChannelName,
        channelDescription: isAlarm
            ? taskAlarmChannelDescription
            : taskReminderChannelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: isAlarm
            ? _alarmVibrationPattern
            : _reminderVibrationPattern,
        category: isAlarm
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        audioAttributesUsage: isAlarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
        visibility: NotificationVisibility.public,
        ticker: 'Medicare Track',
      ),
    );
  }

  Future<void> cancelCaregiverTaskNotifications() async {
    if (kIsWeb) {
      return;
    }

    await initialize();
    await _cancelPendingCaregiverTaskNotifications();
    _lastTaskReminderFingerprint = null;
    _shownImmediateReminderKeys.clear();
    _shownImmediateAlarmKeys.clear();
  }

  Future<int> pendingCaregiverTaskNotificationCount() async {
    if (kIsWeb) {
      return 0;
    }

    await initialize();
    final pending = await _localNotifications.pendingNotificationRequests();
    return pending
        .where(
          (request) => (request.payload ?? '').startsWith(_taskPayloadPrefix),
        )
        .length;
  }

  Future<void> _cancelPendingCaregiverTaskNotifications() async {
    final pending = await _localNotifications.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload ?? '';
      if (payload.startsWith(_taskPayloadPrefix)) {
        await _localNotifications.cancel(id: request.id);
      }
    }
  }

  Future<void> _configureLocalTimeZone() async {
    if (_timeZoneConfigured) {
      return;
    }

    tz_data.initializeTimeZones();
    var timeZoneName = 'Asia/Manila';
    try {
      timeZoneName =
          await _platformChannel.invokeMethod<String>('getLocalTimeZoneName') ??
          timeZoneName;
    } on MissingPluginException {
      // Keep the Philippines default when a platform channel is unavailable.
    } on PlatformException {
      // Keep the Philippines default when the OS timezone cannot be read.
    }

    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Manila'));
    }
    _timeZoneConfigured = true;
  }

  Future<void> _requestExactAlarmPermissionIfNeeded() async {
    if (_exactAlarmPermissionRequested) {
      return;
    }
    _exactAlarmPermissionRequested = true;

    try {
      final androidNotifications = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canScheduleExact = await androidNotifications
          ?.canScheduleExactNotifications();
      if (canScheduleExact == false) {
        await androidNotifications?.requestExactAlarmsPermission();
      }
    } catch (_) {
      // Scheduling falls back to inexact alarms if exact alarms are unavailable.
    }
  }

  void _debugLogScheduledTask(
    TaskReminderScheduleItem task,
    DateTime scheduledAt,
    bool isAlarm, {
    bool inexact = false,
  }) {
    if (!kDebugMode) {
      return;
    }

    debugPrint(
      'Scheduled caregiver ${isAlarm ? 'alarm' : 'reminder'}'
      '${inexact ? ' (inexact fallback)' : ''}: '
      '${task.title} for ${task.residentName} at '
      '${scheduledAt.toIso8601String()}',
    );
  }

  tz.TZDateTime _tzDateTime(DateTime localDateTime) {
    return tz.TZDateTime(
      tz.local,
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
      localDateTime.hour,
      localDateTime.minute,
      localDateTime.second,
      localDateTime.millisecond,
    );
  }

  int _taskNotificationId(
    TaskReminderScheduleItem task, {
    required bool isAlarm,
  }) {
    return _stableNotificationId(_taskPayload(task, isAlarm: isAlarm));
  }

  String _taskPayload(TaskReminderScheduleItem task, {required bool isAlarm}) {
    return '$_taskPayloadPrefix${isAlarm ? 'alarm' : 'reminder'}:'
        '${task.id}:${task.scheduledAt.toUtc().toIso8601String()}';
  }

  String _taskFingerprint(TaskReminderScheduleItem task) {
    return [
      task.id,
      task.type,
      task.title,
      task.residentName,
      task.status,
      task.scheduledAt.toUtc().toIso8601String(),
    ].join('|');
  }

  int _stableNotificationId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  String _taskNotificationTitle(bool isAlarm) {
    return isAlarm ? 'Task due now' : 'Task in 5 minutes';
  }

  String _taskNotificationBody(TaskReminderScheduleItem task) {
    return '${_taskTypeLabel(task.type)}: ${task.title} for '
        '${task.residentName} at ${_formatTime(task.scheduledAt)}.';
  }

  String _taskTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'medication':
        return 'Medication';
      case 'meal':
        return 'Meal task';
      default:
        return 'Care task';
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final title =
        message.notification?.title ??
        message.data['title'] ??
        'Medicare Track';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    if (body.toString().trim().isEmpty) {
      return;
    }

    await _localNotifications.show(
      id:
          message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
      title: title.toString(),
      body: body.toString(),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          highImportanceChannelId,
          highImportanceChannelName,
          channelDescription: highImportanceChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          ticker: 'Medicare Track',
        ),
      ),
      payload: message.data['notificationId'],
    );
  }

  String get _platformName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'web';
    }
  }
}

class TaskReminderScheduleItem {
  final String id;
  final String title;
  final String residentName;
  final String type;
  final String status;
  final DateTime scheduledAt;

  const TaskReminderScheduleItem({
    required this.id,
    required this.title,
    required this.residentName,
    required this.type,
    required this.status,
    required this.scheduledAt,
  });

  bool get isPending {
    final normalizedStatus = status.toUpperCase();
    return normalizedStatus == 'PENDING' || normalizedStatus == 'DELAYED';
  }
}
