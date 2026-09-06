import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/models/facility_info.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';
import 'package:medicare_tract/core/navigation/auth_navigation.dart';
import 'package:medicare_tract/core/services/facility_info_service.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/session_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/core/utils/logout_helper.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';
import 'package:medicare_tract/shared/security/password_security_screen.dart';
import 'package:medicare_tract/shared/widgets/notification_preferences_card.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _displayName = 'Family Member';
  String _email = '';
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  bool _isSavingNotifications = false;
  bool _isDeletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      if (!mounted) {
        return;
      }

      final familyProfile = asStringMap(profile['familyProfile']);
      final notificationSetting = asStringMap(profile['notificationSetting']);
      setState(() {
        _displayName =
            (familyProfile?['contactName'] ??
                    profile['username'] ??
                    profile['email'] ??
                    'Family Member')
                .toString();
        _email = (profile['email'] ?? '').toString();
        _notificationPreferences = NotificationPreferences.fromMap(
          notificationSetting,
        );
      });
    } catch (_) {
      // use UI fallback values if API fails
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
      if (!mounted) {
        return;
      }
      setState(() => _notificationPreferences = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
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

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
            'This will deactivate your login and sign you out of Medicare Track.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeletingAccount = true);
    try {
      await ProfileService.instance.deleteMyAccount();
      await SessionService.instance.clear();
      if (!mounted) {
        return;
      }
      goToEntryScreen(context);
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
        const SnackBar(content: Text('Unable to delete account right now.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth > 700 ? 24 : 20,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      CircleAvatar(
                        radius: 40,
                        backgroundColor: const Color(0xFFE0F2F1),
                        child: Text(
                          initialsForName(_displayName, fallback: 'F'),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00BFA5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFA5),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          "Family Member",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Personal Info",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D0C57),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildDetailRow(
                              Icons.person_outline,
                              "Full Name",
                              _displayName,
                              const Color(0xFF00BFA5),
                            ),
                            const Divider(height: 30),
                            _buildDetailRow(
                              Icons.email_outlined,
                              "Email",
                              _email.isEmpty
                                  ? AppBranding.placeholderValue
                                  : _email,
                              const Color(0xFF00BFA5),
                            ),
                            const Divider(height: 30),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const PasswordSecurityScreen(),
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFFFFA726,
                                          ).withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.lock_outline,
                                          color: Color(0xFFFFA726),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      const Text(
                                        "Password & Security",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Notifications",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      NotificationPreferencesCard(
                        preferences: _notificationPreferences,
                        isSaving: _isSavingNotifications,
                        activeColor: const Color(0xFF00BFA5),
                        onChanged: _saveNotifications,
                      ),
                      const SizedBox(height: 25),

                      StreamBuilder<FacilityInfo>(
                        stream: FacilityInfoService.instance
                            .watchFacilityInfo(),
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
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Facility Information",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D0C57),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildDetailRow(
                                  Icons.business,
                                  "Facility",
                                  facilityInfo.name,
                                  const Color(0xFF9575CD),
                                ),
                                const Divider(height: 30),
                                _buildDetailRow(
                                  Icons.phone_outlined,
                                  "Contact",
                                  contact,
                                  const Color(0xFF9575CD),
                                ),
                                const Divider(height: 30),
                                _buildDetailRow(
                                  Icons.support_agent_outlined,
                                  "Support Email",
                                  supportEmail,
                                  const Color(0xFF9575CD),
                                ),
                                const Divider(height: 30),
                                _buildDetailRow(
                                  Icons.info_outline,
                                  "App Version",
                                  AppBranding.appVersion,
                                  Colors.grey,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => confirmSignOut(context),
                          icon: const Icon(
                            Icons.logout,
                            color: Color(0xFFE53935),
                          ),
                          label: const Text(
                            "Sign Out",
                            style: TextStyle(
                              color: Color(0xFFE53935),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            side: const BorderSide(color: Color(0xFFE53935)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _isDeletingAccount
                              ? null
                              : _confirmDeleteAccount,
                          icon: _isDeletingAccount
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_outline,
                                  color: Color(0xFFE53935),
                                ),
                          label: const Text(
                            "Delete Account",
                            style: TextStyle(
                              color: Color(0xFFE53935),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
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

  // --- HELPER WIDGETS ---

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String subtitle,
    Color iconBg,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBg.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconBg, size: 20),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
