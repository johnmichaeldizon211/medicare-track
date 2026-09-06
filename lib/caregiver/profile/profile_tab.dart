import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/models/facility_info.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';
import 'package:medicare_tract/core/services/facility_info_service.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/logout_helper.dart';
import 'package:medicare_tract/shared/security/password_security_screen.dart';
import 'package:medicare_tract/shared/widgets/notification_preferences_card.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final ReportsService _reportsService = ReportsService.instance;
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  bool _isSavingNotifications = false;
  String _displayName = 'Caregiver';
  String _email = '';
  int _residentCount = 0;
  int _tasksDone = 0;
  int _medsLeft = 0;

  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      if (!mounted) return;

      final caregiverProfile =
          profile['caregiverProfile'] as Map<String, dynamic>?;
      final notificationSetting =
          profile['notificationSetting'] as Map<String, dynamic>?;

      setState(() {
        _displayName =
            (caregiverProfile?['displayName'] ??
                    profile['username'] ??
                    profile['email'] ??
                    'Caregiver')
                .toString();
        _email = (profile['email'] ?? '').toString();
        _notificationPreferences = NotificationPreferences.fromMap(
          notificationSetting,
        );
      });

      await _loadSummary(profile);
    } catch (_) {
      // keep static fallback values if profile API is unavailable
    }
  }

  Future<void> _loadSummary(Map<String, dynamic> profile) async {
    try {
      final performance = await _reportsService.getCaregiverPerformance();
      final userId = (profile['id'] ?? '').toString();
      final normalizedDisplayName = _displayName.trim().toLowerCase();
      Map<String, dynamic>? matched;

      for (final entry in performance) {
        final item = Map<String, dynamic>.from(entry as Map);
        final caregiverId = (item['caregiverId'] ?? '').toString();
        final caregiverName = (item['caregiverName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if ((userId.isNotEmpty && caregiverId == userId) ||
            (normalizedDisplayName.isNotEmpty &&
                caregiverName == normalizedDisplayName)) {
          matched = item;
          break;
        }
      }

      if (!mounted) return;

      setState(() {
        _residentCount = _safeInt(matched?['assignedResidents']);
        _tasksDone = _safeInt(matched?['tasksDone']);
        final medicationsTotal = _safeInt(matched?['medicationsTotal']);
        final medicationsGiven = _safeInt(matched?['medicationsGiven']);
        final medicationsMissed = _safeInt(matched?['medicationsMissed']);
        final remaining =
            medicationsTotal - medicationsGiven - medicationsMissed;
        _medsLeft = remaining < 0 ? 0 : remaining;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _residentCount = 0;
        _tasksDone = 0;
        _medsLeft = 0;
      });
    }
  }

  Future<void> _saveNotifications(NotificationPreferences preferences) async {
    final previous = _notificationPreferences;
    setState(() {
      _notificationPreferences = preferences;
      _isSavingNotifications = true;
    });
    try {
      await ProfileService.instance.updateNotifications(preferences);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _notificationPreferences = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _notificationPreferences = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save notification settings.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingNotifications = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth > 700 ? 24.0 : 20.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 45,
                      backgroundColor: Color(0xFFE0F2F1),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        color: Color(0xFF00BFA5),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      _displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Caregiver / Nurse',
                        style: TextStyle(
                          color: Color(0xFF00BFA5),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    LayoutBuilder(
                      builder: (context, inner) {
                        final cards = [
                          _buildSummaryBox(
                            _residentCount.toString(),
                            'Residents',
                            const Color(0xFFE8F5E9),
                            const Color(0xFF00C853),
                          ),
                          _buildSummaryBox(
                            _tasksDone.toString(),
                            'Tasks Done',
                            const Color(0xFFE0F2F1),
                            const Color(0xFF00BFA5),
                          ),
                          _buildSummaryBox(
                            _medsLeft.toString(),
                            'Meds Left',
                            const Color(0xFFFFF3E0),
                            const Color(0xFFFFA726),
                          ),
                        ];

                        if (inner.maxWidth < 420) {
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: cards,
                          );
                        }

                        return Row(
                          children: [
                            for (final card in cards)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: card,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    _buildSectionHeader('Account Details'),
                    Container(
                      decoration: _cardDecoration(),
                      child: Column(
                        children: [
                          _buildInfoTile(
                            Icons.person_outline,
                            'Full Name',
                            _displayName,
                          ),
                          _buildDivider(),
                          _buildInfoTile(
                            Icons.email_outlined,
                            'Email',
                            _email.isEmpty
                                ? AppBranding.placeholderValue
                                : _email,
                          ),
                          _buildDivider(),
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.vpn_key_outlined,
                                color: Color(0xFFFFA726),
                                size: 20,
                              ),
                            ),
                            title: const Text(
                              'Password & Security',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.grey,
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PasswordSecurityScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),
                    _buildSectionHeader('Facility Information'),
                    StreamBuilder<FacilityInfo>(
                      stream: FacilityInfoService.instance.watchFacilityInfo(),
                      initialData: FacilityInfoService.instance.current,
                      builder: (context, snapshot) {
                        final facilityInfo =
                            snapshot.data ??
                            FacilityInfoService.instance.current;
                        final contact = facilityInfo.contactNumber.isEmpty
                            ? AppBranding.placeholderValue
                            : facilityInfo.contactNumber;
                        final supportEmail = facilityInfo.email.isEmpty
                            ? AppBranding.placeholderValue
                            : facilityInfo.email;

                        return Container(
                          decoration: _cardDecoration(),
                          child: Column(
                            children: [
                              _buildInfoTile(
                                Icons.business_outlined,
                                'Facility',
                                facilityInfo.name,
                              ),
                              _buildDivider(),
                              _buildInfoTile(
                                Icons.phone_outlined,
                                'Facility Contact',
                                contact,
                              ),
                              _buildDivider(),
                              _buildInfoTile(
                                Icons.support_agent_outlined,
                                'Support Email',
                                supportEmail,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 25),
                    _buildSectionHeader('Notifications'),
                    NotificationPreferencesCard(
                      preferences: _notificationPreferences,
                      isSaving: _isSavingNotifications,
                      activeColor: const Color(0xFF00BFA5),
                      onChanged: _saveNotifications,
                    ),
                    const SizedBox(height: 35),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => confirmSignOut(context),
                        icon: const Icon(
                          Icons.logout,
                          color: Color(0xFFE53935),
                        ),
                        label: const Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          backgroundColor: const Color(
                            0xFFFFEBEE,
                          ).withValues(alpha: 0.5),
                          side: const BorderSide(
                            color: Color(0xFFE53935),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      AppBranding.appVersion,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
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
    );
  }

  Widget _buildSummaryBox(
    String count,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D0C57),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2F1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF00BFA5), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      color: Color(0xFFEEEEEE),
      indent: 60,
      endIndent: 20,
    );
  }
}
