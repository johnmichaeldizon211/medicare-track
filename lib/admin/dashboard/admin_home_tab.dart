import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/residents/admin_residents_list_screen.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/services/time_clock_service.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';

class AdminHomeTab extends StatefulWidget {
  final VoidCallback onNavigateToResidents;
  final VoidCallback onNavigateToInventory;
  final VoidCallback onNavigateToReports;
  final VoidCallback onNavigateToMessages;
  final VoidCallback onNavigateToProfile;

  const AdminHomeTab({
    super.key,
    required this.onNavigateToResidents,
    required this.onNavigateToInventory,
    required this.onNavigateToReports,
    required this.onNavigateToMessages,
    required this.onNavigateToProfile,
  });

  @override
  State<AdminHomeTab> createState() => _AdminHomeTabState();
}

class _AdminHomeTabState extends State<AdminHomeTab> {
  final ProfileService _profileService = ProfileService.instance;
  final ReportsService _reportsService = ReportsService.instance;
  final ResidentService _residentService = ResidentService.instance;
  final TimeClockService _timeClockService = TimeClockService.instance;

  String _adminDisplayName = 'Admin';
  int _taskDonePercent = 0;
  int _medRatePercent = 0;
  int _missedCount = 0;
  int _residentCount = 0;
  int _activeCaregiverCount = 0;
  double _totalCaregiverHours = 0;
  List<Map<String, dynamic>> _caregiverTimeSummaries = [];
  List<Map<String, dynamic>> _residentPreview = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _loadDashboard();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  int _safeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _safeDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _safeString(
    dynamic value, {
    String fallback = AppBranding.placeholderValue,
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _statusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case 'NEEDS_ATTENTION':
        return 'Needs Attention';
      case 'CRITICAL':
        return 'Critical';
      case 'STABLE':
      default:
        return 'Stable';
    }
  }

  Color _statusColor(String raw) {
    switch (raw.toUpperCase()) {
      case 'NEEDS_ATTENTION':
        return const Color(0xFFFFA726);
      case 'CRITICAL':
        return const Color(0xFFE53935);
      case 'STABLE':
      default:
        return const Color(0xFF00C853);
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'A';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  DateTime? _parseDateTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatClockTime(dynamic value) {
    final dateTime = _parseDateTime(value);
    if (dateTime == null) {
      return '--';
    }

    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _formatHours(double hours) {
    if (hours <= 0) {
      return '0h';
    }
    final totalMinutes = (hours * 60).round();
    final wholeHours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (wholeHours == 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${wholeHours}h';
    }
    return '${wholeHours}h ${minutes}m';
  }

  Future<void> _loadDashboard() async {
    try {
      final attendanceFuture = _timeClockService.getAdminToday().catchError(
        (_) => <String, dynamic>{},
      );
      final profileFuture = _profileService.getProfile().catchError(
        (_) => <String, dynamic>{},
      );
      final overviewFuture = _reportsService.getOverview().catchError(
        (_) => <String, dynamic>{},
      );
      final residentsFuture = _residentService.getResidents().catchError(
        (_) => <dynamic>[],
      );

      final results = await Future.wait<dynamic>([
        profileFuture,
        overviewFuture,
        residentsFuture,
      ]);
      final attendance = await attendanceFuture;

      final profile = Map<String, dynamic>.from(results[0] as Map);
      final overview = Map<String, dynamic>.from(results[1] as Map);
      final residents = (results[2] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final residentOverview = _overviewFromResidents(residents);
      final caregiverTimeSummaries =
          (attendance['caregivers'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList()
            ..sort((a, b) {
              final aActive = a['isTimedIn'] == true;
              final bActive = b['isTimedIn'] == true;
              if (aActive != bActive) {
                return aActive ? -1 : 1;
              }
              return _safeString(
                a['caregiverName'],
                fallback: 'Caregiver',
              ).compareTo(
                _safeString(b['caregiverName'], fallback: 'Caregiver'),
              );
            });

      final caregiverProfile =
          profile['caregiverProfile'] as Map<String, dynamic>?;
      final displayName = _safeString(
        caregiverProfile?['displayName'] ??
            profile['username'] ??
            profile['email'] ??
            'Admin',
        fallback: 'Admin',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _adminDisplayName = displayName;
        _taskDonePercent = _overviewInt(
          overview,
          residentOverview,
          'taskCompletion',
        );
        _medRatePercent = _overviewInt(
          overview,
          residentOverview,
          'medCompliance',
        );
        _missedCount = _overviewInt(
          overview,
          residentOverview,
          'missedMedicationEvents',
        );
        _residentCount = _overviewInt(
          overview,
          residentOverview,
          'totalResidents',
        );
        _activeCaregiverCount = _safeInt(attendance['activeCount']);
        _totalCaregiverHours = _safeDouble(attendance['totalHours']);
        _caregiverTimeSummaries = caregiverTimeSummaries;
        _residentPreview = residents.take(3).toList();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _adminDisplayName = 'Admin';
        _taskDonePercent = 0;
        _medRatePercent = 0;
        _missedCount = 0;
        _residentCount = 0;
        _activeCaregiverCount = 0;
        _totalCaregiverHours = 0;
        _caregiverTimeSummaries = [];
        _residentPreview = [];
      });
    }
  }

  Map<String, int> _overviewFromResidents(
    List<Map<String, dynamic>> residents,
  ) {
    final medicationTotal = residents.fold<int>(
      0,
      (total, resident) =>
          total + _safeInt(resident['todayMedicationEventsTotal']),
    );
    final medicationCompleted = residents.fold<int>(
      0,
      (total, resident) =>
          total + _safeInt(resident['todayMedicationEventsCompleted']),
    );
    final medicationMissed = residents.fold<int>(
      0,
      (total, resident) =>
          total + _safeInt(resident['todayMedicationEventsMissed']),
    );
    final taskTotal = residents.fold<int>(
      0,
      (total, resident) => total + _safeInt(resident['todayCareTasksTotal']),
    );
    final taskCompleted = residents.fold<int>(
      0,
      (total, resident) =>
          total + _safeInt(resident['todayCareTasksCompleted']),
    );

    return {
      'totalResidents': residents.length,
      'missedMedicationEvents': medicationMissed,
      'medCompliance': medicationTotal == 0
          ? 0
          : ((medicationCompleted / medicationTotal) * 100).round(),
      'taskCompletion': taskTotal == 0
          ? 0
          : ((taskCompleted / taskTotal) * 100).round(),
    };
  }

  int _overviewInt(
    Map<String, dynamic> overview,
    Map<String, int> fallback,
    String key,
  ) {
    final value = _safeInt(overview[key]);
    final fallbackValue = fallback[key] ?? 0;
    if (!overview.containsKey(key) || (value == 0 && fallbackValue > 0)) {
      return fallbackValue;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDashboard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isDesktop = width >= 900;
            final horizontalPadding = width < 360
                ? 14.0
                : width < 700
                ? 20.0
                : 32.0;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: width < 700 ? 15 : 24,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 1280 : 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 25),
                      _buildMetricsOverview(),
                      const SizedBox(height: 25),
                      _buildCaregiverTimeTracker(),
                      const SizedBox(height: 25),
                      _buildSectionTitle('Critical Alerts'),
                      const SizedBox(height: 10),
                      _buildCriticalAlertBanner(context),
                      const SizedBox(height: 25),
                      _buildSectionTitle('Quick Actions'),
                      const SizedBox(height: 10),
                      _buildQuickActionsGrid(),
                      const SizedBox(height: 30),
                      _buildResidentOverviewHeader(),
                      if (_residentPreview.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Text(
                            'No residents yet. Create accounts and assign residents to populate this section.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        Column(
                          children: _residentPreview
                              .map(
                                (resident) =>
                                    _buildResidentPreviewCard(resident),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2D0C57),
      ),
    );
  }

  Widget _buildMetricsOverview() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 4
            : constraints.maxWidth >= 260
            ? 2
            : 1;
        return _buildResponsiveWrap(
          columnCount: columns,
          spacing: constraints.maxWidth < 340 ? 10 : 12,
          runSpacing: 12,
          children: [
            _buildAnimatedDonutChart(
              '$_taskDonePercent%',
              'Task Done',
              (_taskDonePercent / 100).clamp(0.0, 1.0),
              const Color(0xFF00C853),
            ),
            _buildAnimatedDonutChart(
              '$_medRatePercent%',
              'Med Rate',
              (_medRatePercent / 100).clamp(0.0, 1.0),
              const Color(0xFF00BFA5),
            ),
            _buildStatBox(
              '$_missedCount',
              'Missed',
              const Color(0xFFFFEBEE),
              const Color(0xFFE53935),
            ),
            _buildStatBox(
              '$_residentCount',
              'Residents',
              const Color(0xFFFFF3E0),
              const Color(0xFFFFA726),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActionsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100
            ? 5
            : width >= 760
            ? 3
            : width >= 420
            ? 2
            : 1;

        return _buildResponsiveWrap(
          columnCount: columns,
          spacing: 15,
          runSpacing: 15,
          children: [
            _buildQuickActionCard(
              Icons.people_alt,
              'All Residents',
              '$_residentCount total',
              const Color(0xFF00BFA5),
              widget.onNavigateToResidents,
            ),
            _buildQuickActionCard(
              Icons.inventory_2,
              'Inventory',
              'Medicine stock',
              const Color(0xFF00BFA5),
              widget.onNavigateToInventory,
            ),
            _buildQuickActionCard(
              Icons.bar_chart,
              'Reports',
              'View analytics',
              const Color(0xFFFFA726),
              widget.onNavigateToReports,
            ),
            _buildQuickActionCard(
              Icons.chat_bubble,
              'Messages',
              'Family updates',
              const Color(0xFF9575CD),
              widget.onNavigateToMessages,
            ),
            _buildQuickActionCard(
              Icons.account_circle,
              'My Profile',
              'Account settings',
              const Color(0xFF00C853),
              widget.onNavigateToProfile,
            ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveWrap({
    required int columnCount,
    required double spacing,
    required double runSpacing,
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableWidth = constraints.maxWidth;
        final itemWidth =
            (usableWidth - (spacing * (columnCount - 1))) / columnCount;

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map(
                (child) => SizedBox(
                  width: itemWidth.isFinite && itemWidth > 0
                      ? itemWidth
                      : usableWidth,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildResidentOverviewHeader() {
    return Row(
      children: [
        Expanded(child: _buildSectionTitle('Resident Overview')),
        TextButton(
          onPressed: widget.onNavigateToResidents,
          child: const Text(
            'See all',
            style: TextStyle(color: Color(0xFF00BFA5)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        final contentWidth = isWide
            ? constraints.maxWidth - 150
            : constraints.maxWidth;

        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greetingForNow(),
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  Text(
                    _adminDisplayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFA726),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    color: Color(0xFFFFA726),
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Admin',
                    style: TextStyle(
                      color: Color(0xFFFFA726),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedDonutChart(
    String percentageText,
    String label,
    double targetValue,
    Color color,
  ) {
    return _buildMetricCard(
      label: label,
      color: color,
      visual: SizedBox(
        height: 62,
        width: 62,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: targetValue),
          duration: const Duration(seconds: 2),
          builder: (context, value, child) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  backgroundColor: color.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      percentageText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required Widget visual,
    required String label,
    required Color color,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 122),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          visual,
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(
    String count,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return _buildMetricCard(
      label: label,
      color: textColor,
      visual: Container(
        height: 62,
        width: 62,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              count,
              style: TextStyle(
                color: textColor,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaregiverTimeTracker() {
    final visibleCaregivers = _caregiverTimeSummaries.take(5).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F7FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.punch_clock,
                  color: Color(0xFF00ACC1),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Caregiver Time Tracking',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    Text(
                      'Today attendance summary',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$_activeCaregiverCount active',
                  style: const TextStyle(
                    color: Color(0xFF00C853),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackTiles = constraints.maxWidth < 300;
              final timedInTile = _buildAttendanceSummaryTile(
                'Timed In',
                '$_activeCaregiverCount',
                Icons.login,
                const Color(0xFF00C853),
              );
              final hoursTile = _buildAttendanceSummaryTile(
                'Total Hours',
                _formatHours(_totalCaregiverHours),
                Icons.timer,
                const Color(0xFFFFA726),
              );

              if (stackTiles) {
                return Column(
                  children: [
                    timedInTile,
                    const SizedBox(height: 12),
                    hoursTile,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: timedInTile),
                  const SizedBox(width: 12),
                  Expanded(child: hoursTile),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (visibleCaregivers.isEmpty)
            const Text(
              'No caregiver attendance yet today.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            )
          else
            ...visibleCaregivers.map(_buildCaregiverTimeRow),
        ],
      ),
    );
  }

  Widget _buildAttendanceSummaryTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2D0C57),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaregiverTimeRow(Map<String, dynamic> caregiver) {
    final name = _safeString(caregiver['caregiverName'], fallback: 'Caregiver');
    final isTimedIn = caregiver['isTimedIn'] == true;
    final hasHours = _safeDouble(caregiver['totalHours']) > 0;
    final status = isTimedIn
        ? 'Timed In'
        : hasHours
        ? 'Timed Out'
        : 'No Shift';
    final statusColor = isTimedIn
        ? const Color(0xFF00C853)
        : hasHours
        ? const Color(0xFF9575CD)
        : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Text(
              _initials(name),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _buildAttendanceMeta(
                      'In ${_formatClockTime(caregiver['timeIn'])}',
                    ),
                    _buildAttendanceMeta(
                      'Out ${_formatClockTime(caregiver['timeOut'])}',
                    ),
                    _buildAttendanceMeta(
                      _formatHours(_safeDouble(caregiver['totalHours'])),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceMeta(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildCriticalAlertBanner(BuildContext context) {
    final hasAlerts = _missedCount > 0;
    final title = hasAlerts ? '$_missedCount Missed Meds' : 'No Active Alerts';
    final subtitle = hasAlerts
        ? 'Tap to review residents that need attention.'
        : 'Everything looks good';
    final iconColor = hasAlerts
        ? const Color(0xFFE53935)
        : const Color(0xFF00C853);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const Scaffold(
              backgroundColor: Color(0xFFF8F9FA),
              body: AdminResidentsListScreen(initialFilterIndex: 2),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: iconColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.error, color: iconColor, size: 28),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 132),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 15),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResidentPreviewCard(Map<String, dynamic> resident) {
    final name = _safeString(resident['name'], fallback: 'Resident');
    final room = _safeString(resident['room']);
    final statusRaw = _safeString(
      resident['overallStatus'],
      fallback: 'STABLE',
    );
    final status = _statusLabel(statusRaw);
    final statusColor = _statusColor(statusRaw);
    final conditions = (resident['conditions'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Text(
                  _initials(name),
                  style: const TextStyle(
                    color: Color(0xFF009688),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      room.isEmpty
                          ? 'Room ${AppBranding.placeholderValue}'
                          : 'Room $room',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: conditions
                  .map(
                    (condition) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        condition,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
