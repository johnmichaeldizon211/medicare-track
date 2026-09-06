import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medicare_tract/core/config/app_branding.dart';
import 'package:medicare_tract/core/models/facility_info.dart';
import 'package:medicare_tract/core/models/notification_preferences.dart';
import 'package:medicare_tract/core/services/facility_info_service.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/logout_helper.dart';
import 'package:medicare_tract/shared/security/password_security_screen.dart';
import 'package:medicare_tract/shared/widgets/notification_preferences_card.dart';

class AdminProfileTab extends StatefulWidget {
  const AdminProfileTab({super.key});

  @override
  State<AdminProfileTab> createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> {
  bool _isLoadingUsers = false;
  String _adminDisplayName = 'Admin';
  String _adminEmail = '';
  String _adminUsername = '';
  int _taskDonePercent = 0;
  int _medRatePercent = 0;
  int _missedCount = 0;
  int _residentCount = 0;
  int _selectedSectionIndex = 0;
  NotificationPreferences _notificationPreferences =
      const NotificationPreferences();
  bool _isSavingNotifications = false;

  final List<Map<String, String>> _caregivers = [];

  final List<Map<String, String>> _families = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadUsers();
    _loadSummary();
  }

  String _displayNameFromUser(Map<String, dynamic> user) {
    final caregiverProfile = _mapFrom(user['caregiverProfile']);
    final familyProfile = _mapFrom(user['familyProfile']);

    if (caregiverProfile != null &&
        (caregiverProfile['displayName'] as String?)?.isNotEmpty == true) {
      return caregiverProfile['displayName'] as String;
    }
    if (familyProfile != null &&
        (familyProfile['contactName'] as String?)?.isNotEmpty == true) {
      return familyProfile['contactName'] as String;
    }
    if ((user['username'] as String?)?.isNotEmpty == true) {
      return user['username'] as String;
    }
    return (user['email'] ?? 'Unknown').toString();
  }

  Map<String, dynamic>? _mapFrom(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String _textFrom(dynamic value) => (value ?? '').toString();

  String _conditionsTextFrom(dynamic value) {
    final conditions = value is List ? value : const [];
    return conditions
        .map((condition) {
          if (condition is Map) {
            return _textFrom(condition['name']).trim();
          }
          return condition.toString().trim();
        })
        .where((condition) => condition.isNotEmpty)
        .toSet()
        .join(', ');
  }

  String _assignedResidentsTextFrom(dynamic value) {
    final assignments = value is List ? value : const [];
    return assignments
        .map((assignment) {
          final assignmentMap = _mapFrom(assignment);
          final resident = _mapFrom(assignmentMap?['resident']);
          if (resident == null) {
            return '';
          }
          final name = _textFrom(resident['name']).trim();
          final room = _textFrom(resident['room']).trim();
          if (name.isEmpty) {
            return '';
          }
          return room.isEmpty ? name : '$name, Room $room';
        })
        .where((resident) => resident.isNotEmpty)
        .join(', ');
  }

  Map<String, String> _adminUserCardFromUser(
    Map<String, dynamic> user, {
    required bool isCaregiver,
  }) {
    final caregiverProfile = _mapFrom(user['caregiverProfile']);
    final familyProfile = _mapFrom(user['familyProfile']);
    final resident = _mapFrom(familyProfile?['resident']);

    return <String, String>{
      'id': _textFrom(user['id']),
      'name': _displayNameFromUser(user),
      'email': _textFrom(user['email']),
      'status': _textFrom(user['status']).isEmpty
          ? 'ACTIVE'
          : _textFrom(user['status']),
      'primaryContactNumber': isCaregiver
          ? _textFrom(caregiverProfile?['contactNumber'])
          : _textFrom(familyProfile?['contactNumber']),
      'secondaryContactNumber': _textFrom(
        familyProfile?['secondaryContactNumber'],
      ),
      'address': isCaregiver
          ? _textFrom(caregiverProfile?['address'])
          : _textFrom(familyProfile?['address']),
      'relationship': _textFrom(familyProfile?['relationship']),
      'residentName': _textFrom(resident?['name']),
      'residentRoom': _textFrom(resident?['room']),
      'residentAge': _textFrom(resident?['age']),
      'residentBirthday': _textFrom(resident?['birthday']),
      'residentGender': _textFrom(resident?['gender']),
      'residentAddress': _textFrom(resident?['address']),
      'residentConditions': _conditionsTextFrom(resident?['conditions']),
      'assignedResidents': _assignedResidentsTextFrom(
        user['residentAssignments'],
      ),
    };
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.instance.getProfile();
      if (!mounted) {
        return;
      }

      setState(() {
        _adminDisplayName = _displayNameFromUser(profile);
        _adminEmail = (profile['email'] ?? '').toString();
        _adminUsername = (profile['username'] ?? '').toString();
        _notificationPreferences = NotificationPreferences.fromMap(
          profile['notificationSetting'] as Map<String, dynamic>?,
        );
      });
    } catch (_) {
      // keep static fallback data if API is unavailable
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final caregivers = await ProfileService.instance.listAdminUsers(
        role: 'CAREGIVER',
        includeInactive: true,
      );
      final families = await ProfileService.instance.listAdminUsers(
        role: 'FAMILY',
        includeInactive: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _caregivers
          ..clear()
          ..addAll(
            caregivers.map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              return _adminUserCardFromUser(map, isCaregiver: true);
            }),
          );
        _families
          ..clear()
          ..addAll(
            families.map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              return _adminUserCardFromUser(map, isCaregiver: false);
            }),
          );
      });
    } catch (_) {
      // keep the lists empty when the backend is unavailable
    } finally {
      if (mounted) {
        setState(() => _isLoadingUsers = false);
      }
    }
  }

  int _safeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await ProfileService.instance.getAdminOverview();
      if (!mounted) {
        return;
      }

      setState(() {
        _taskDonePercent = _safeInt(summary['taskCompletion']);
        _medRatePercent = _safeInt(summary['medCompliance']);
        _missedCount = _safeInt(summary['missedMedicationEvents']);
        _residentCount = _safeInt(summary['totalResidents']);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _taskDonePercent = 0;
        _medRatePercent = 0;
        _missedCount = 0;
        _residentCount = 0;
      });
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
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
      _showSnackBar(e.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _notificationPreferences = previous);
      _showSnackBar('Unable to save notification settings.');
    } finally {
      if (mounted) {
        setState(() => _isSavingNotifications = false);
      }
    }
  }

  void _showEditProfileSheet() {
    final usernameController = TextEditingController(text: _adminUsername);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final sheetNavigator = Navigator.of(sheetContext);
        bool isSaving = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final mediaQuery = MediaQuery.of(sheetContext);
            final screenWidth = mediaQuery.size.width;
            final isMobile = screenWidth < 600;
            final isTablet = screenWidth >= 600 && screenWidth < 1024;
            final sideInset = isMobile
                ? 12.0
                : isTablet
                ? 24.0
                : 32.0;
            final contentPadding = isMobile ? 18.0 : 24.0;
            final maxSheetWidth = isMobile
                ? double.infinity
                : isTablet
                ? 520.0
                : 460.0;
            final maxSheetHeight =
                (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32)
                    .clamp(220.0, 420.0)
                    .toDouble();

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sideInset,
                  16,
                  sideInset,
                  mediaQuery.viewInsets.bottom + (isMobile ? 8 : 24),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxSheetWidth,
                      maxHeight: maxSheetHeight,
                    ),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(isMobile ? 24 : 20),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(contentPadding),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: usernameController,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final username = usernameController.text
                                            .trim();
                                        if (username.isEmpty) {
                                          _showSnackBar(
                                            'Username cannot be empty.',
                                          );
                                          return;
                                        }

                                        setSheetState(() => isSaving = true);
                                        try {
                                          await ProfileService.instance
                                              .updateProfile({
                                                'username': username,
                                              });
                                          if (!mounted) {
                                            return;
                                          }
                                          if (sheetNavigator.canPop()) {
                                            sheetNavigator.pop();
                                          }
                                          await _loadProfile();
                                          _showSnackBar('Profile updated.');
                                        } on ApiException catch (e) {
                                          _showSnackBar(e.message);
                                        } catch (_) {
                                          _showSnackBar(
                                            'Failed to update profile.',
                                          );
                                        } finally {
                                          if (sheetContext.mounted) {
                                            setSheetState(
                                              () => isSaving = false,
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => usernameController.dispose());
  }

  Future<void> _showEditFacilityInfoSheet(FacilityInfo facilityInfo) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FacilityInfoSheet(facilityInfo: facilityInfo),
    );

    if (!mounted || updated != true) {
      return;
    }

    _showSnackBar(
      'Facility details updated.',
      backgroundColor: const Color(0xFF00C853),
    );
  }

  bool _isDisabledAccount(Map<String, String> user) {
    return (user['status'] ?? 'ACTIVE').toUpperCase() == 'DEACTIVATED';
  }

  // --- LOGIC: Account Status Confirmation Dialog ---
  void _confirmStatusChange(
    String name,
    bool isCaregiver,
    int index, {
    String? userId,
    required bool enable,
  }) {
    final actionLabel = enable ? 'Enable' : 'Disable';
    final actionPastTense = enable ? 'enabled' : 'disabled';
    final actionColor = enable
        ? const Color(0xFF00C853)
        : const Color(0xFFE53935);
    showDialog(
      context: context,
      builder: (dialogContext) {
        final dialogNavigator = Navigator.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                enable ? Icons.check_circle_outline : Icons.block,
                color: actionColor,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text("$actionLabel Account")),
            ],
          ),
          content: Text(
            enable
                ? "Enable $name? They will regain access to the Medicare Track app."
                : "Disable $name? They will lose access to the Medicare Track app until an admin enables the account.",
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (userId != null && userId.isNotEmpty) {
                    if (enable) {
                      await ProfileService.instance.activateUser(userId);
                    } else {
                      await ProfileService.instance.deactivateUser(userId);
                    }
                  }

                  if (!mounted) {
                    return;
                  }

                  setState(() {
                    final targetList = isCaregiver ? _caregivers : _families;
                    final nextStatus = enable ? 'ACTIVE' : 'DEACTIVATED';
                    if (isCaregiver) {
                      _caregivers[index]['status'] = nextStatus;
                    } else {
                      _families[index]['status'] = nextStatus;
                    }
                    targetList[index]['status'] = nextStatus;
                  });
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar(
                    '$name has been $actionPastTense.',
                    backgroundColor: actionColor,
                  );
                  await _loadUsers();
                } on ApiException catch (e) {
                  if (!mounted) {
                    return;
                  }
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar(e.message);
                } catch (_) {
                  if (!mounted) {
                    return;
                  }
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar('Failed to update user status.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: actionColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- LOGIC: Delete Account Confirmation Dialog ---
  void _confirmDeleteAccount(
    String name,
    bool isCaregiver,
    int index, {
    String? userId,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final dialogNavigator = Navigator.of(dialogContext);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.delete_forever, color: Color(0xFFE53935)),
              SizedBox(width: 10),
              Expanded(child: Text("Delete Account")),
            ],
          ),
          content: Text(
            "Permanently delete $name? This will remove the account and purge their related records. This action cannot be undone.",
          ),
          actions: [
            TextButton(
              onPressed: () => dialogNavigator.pop(),
              child: const Text(
                "Cancel",
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (userId != null && userId.isNotEmpty) {
                    await ProfileService.instance.deleteUser(userId);
                  }

                  if (!mounted) {
                    return;
                  }

                  setState(() {
                    if (isCaregiver) {
                      _caregivers.removeAt(index);
                    } else {
                      _families.removeAt(index);
                    }
                  });
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar(
                    '$name has been deleted.',
                    backgroundColor: const Color(0xFFE53935),
                  );
                  await _loadSummary();
                } on ApiException catch (e) {
                  if (!mounted) {
                    return;
                  }
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar(e.message);
                } catch (_) {
                  if (!mounted) {
                    return;
                  }
                  if (dialogNavigator.canPop()) {
                    dialogNavigator.pop();
                  }
                  _showSnackBar('Failed to delete user.');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "Delete Permanently",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // --- LOGIC: Interactive Admin Account Bottom Sheets ---
  Future<void> _showCreateCaregiverAccountBottomSheet() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateCaregiverSheet(),
    );

    if (!mounted || created == null) {
      return;
    }

    await _handleCreatedAccount(created, isCaregiver: true);
  }

  Future<void> _showCreateFamilyAccountBottomSheet() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateFamilySheet(),
    );

    if (!mounted || created == null) {
      return;
    }

    await _handleCreatedAccount(created, isCaregiver: false);
  }

  Future<void> _handleCreatedAccount(
    Map<String, dynamic> created, {
    required bool isCaregiver,
  }) async {
    final user = Map<String, dynamic>.from(created);
    setState(() {
      final targetList = isCaregiver ? _caregivers : _families;
      targetList.insert(
        0,
        _adminUserCardFromUser(user, isCaregiver: isCaregiver),
      );
    });

    _showSnackBar(
      'Created ${isCaregiver ? 'caregiver' : 'family'} account successfully. Use ${user['email']} and the password you entered.',
      backgroundColor: const Color(0xFF00C853),
    );
    await _loadUsers();
    await _loadSummary();
  }

  Future<void> _showEditAccountBottomSheet(
    Map<String, String> user, {
    required bool isCaregiver,
    required int index,
  }) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAccountSheet(user: user, isCaregiver: isCaregiver),
    );

    if (!mounted || updated == null) {
      return;
    }

    setState(() {
      final targetList = isCaregiver ? _caregivers : _families;
      if (index >= 0 && index < targetList.length) {
        targetList[index] = _adminUserCardFromUser(
          updated,
          isCaregiver: isCaregiver,
        );
      }
    });

    _showSnackBar(
      'Updated ${isCaregiver ? 'caregiver' : 'family'} account.',
      backgroundColor: const Color(0xFF00C853),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isDesktop = width >= 900;
          final horizontalPadding = width < 360
              ? 14.0
              : width < 700
              ? 20.0
              : 32.0;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isDesktop ? 1120 : 900),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  children: [
                    SizedBox(height: width < 700 ? 20 : 24),
                    CircleAvatar(
                      radius: width < 360 ? 34 : 40,
                      backgroundColor: const Color(0xFFFFE0B2),
                      child: Text(
                        _adminDisplayName.isEmpty
                            ? 'A'
                            : _adminDisplayName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFA726),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _adminDisplayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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
                        color: const Color(0xFFFFA726),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        "Admin",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 520 : double.infinity,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              _buildSectionTab(
                                title: "Profile account",
                                index: 0,
                              ),
                              _buildSectionTab(
                                title: "Create accounts",
                                index: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _selectedSectionIndex == 0
                          ? _buildProfileAccountTab()
                          : _buildCreateAccountsTab(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTab({required String title, required int index}) {
    final isSelected = _selectedSectionIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSectionIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black87 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 1: PROFILE ACCOUNT ---
  Widget _buildProfileAccountTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  "Account Details",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFA726),
                  ),
                ),
              ),
              // Added an Edit Button for realism!
              TextButton.icon(
                onPressed: _showEditProfileSheet,
                icon: const Icon(
                  Icons.edit,
                  size: 14,
                  color: Color(0xFF00BFA5),
                ),
                label: const Text(
                  "Edit",
                  style: TextStyle(color: Color(0xFF00BFA5)),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildDetailRow(
                  Icons.person,
                  "Full Name",
                  _adminDisplayName,
                  const Color(0xFF00BFA5),
                ),
                const Divider(height: 30),
                _buildDetailRow(
                  Icons.shield,
                  "Role",
                  "Admin",
                  const Color(0xFF00BFA5),
                ),
                const Divider(height: 30),

                // --- INTERACTIVE PASSWORD ROW ---
                GestureDetector(
                  onTap: () {
                    // SUCCESSFULLY LINKED TO SHARED SECURITY FLOW
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PasswordSecurityScreen(),
                      ),
                    );
                  },
                  child: Container(
                    color: Colors
                        .transparent, // Ensures the whole row is clickable
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
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
                                  Icons.vpn_key,
                                  color: Color(0xFFFFA726),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 15),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Password and security",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      "********",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),

          const Text(
            "Notifications",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          NotificationPreferencesCard(
            preferences: _notificationPreferences,
            isSaving: _isSavingNotifications,
            activeColor: const Color(0xFFFFA726),
            onChanged: _saveNotifications,
          ),
          const SizedBox(height: 25),

          const Text(
            "Today's Summary",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _buildSummaryGrid(),
          const SizedBox(height: 25),

          StreamBuilder<FacilityInfo>(
            stream: FacilityInfoService.instance.watchFacilityInfo(),
            initialData: FacilityInfoService.instance.current,
            builder: (context, snapshot) {
              final facilityInfo =
                  snapshot.data ?? FacilityInfoService.instance.current;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      "Facility Details",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit facility details',
                    onPressed: () => _showEditFacilityInfoSheet(facilityInfo),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Color(0xFF00BFA5),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          StreamBuilder<FacilityInfo>(
            stream: FacilityInfoService.instance.watchFacilityInfo(),
            initialData: FacilityInfoService.instance.current,
            builder: (context, snapshot) {
              final facilityInfo =
                  snapshot.data ?? FacilityInfoService.instance.current;
              final contact = facilityInfo.contactNumber.isEmpty
                  ? AppBranding.placeholderValue
                  : facilityInfo.contactNumber;
              final email = facilityInfo.email.isEmpty
                  ? AppBranding.placeholderValue
                  : facilityInfo.email;
              final address = facilityInfo.address.trim();

              return Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.business,
                      "Facility",
                      facilityInfo.name,
                      const Color(0xFF00BFA5),
                    ),
                    const Divider(height: 30),
                    _buildDetailRow(
                      Icons.phone_outlined,
                      "Contact",
                      contact,
                      const Color(0xFF00BFA5),
                    ),
                    const Divider(height: 30),
                    _buildDetailRow(
                      Icons.email_outlined,
                      "Support Email",
                      email,
                      const Color(0xFFFFA726),
                    ),
                    if (address.isNotEmpty) ...[
                      const Divider(height: 30),
                      _buildDetailRow(
                        Icons.location_on_outlined,
                        "Address",
                        address,
                        const Color(0xFF9575CD),
                      ),
                    ],
                    const Divider(height: 30),
                    _buildDetailRow(
                      Icons.verified_user,
                      "App Version",
                      AppBranding.appVersion,
                      const Color(0xFFFFA726),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 30),

          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width >= 900
                    ? 360
                    : double.infinity,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => confirmSignOut(context),
                  icon: const Icon(Icons.logout, color: Color(0xFFE53935)),
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
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // --- TAB 2: CREATE ACCOUNTS ---
  Widget _buildCreateAccountsTab() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop)
            Row(
              children: [
                Expanded(
                  child: _buildCreateAccountButton(
                    icon: Icons.person_add_alt_1,
                    title: "Create Caregiver Account",
                    onPressed: _showCreateCaregiverAccountBottomSheet,
                    color: const Color(0xFFFFA726),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCreateAccountButton(
                    icon: Icons.family_restroom,
                    title: "Create Family Account",
                    onPressed: _showCreateFamilyAccountBottomSheet,
                    color: const Color(0xFF9575CD),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _buildCreateAccountButton(
                  icon: Icons.person_add_alt_1,
                  title: "Create Caregiver Account",
                  onPressed: _showCreateCaregiverAccountBottomSheet,
                  color: const Color(0xFFFFA726),
                ),
                const SizedBox(height: 12),
                _buildCreateAccountButton(
                  icon: Icons.family_restroom,
                  title: "Create Family Account",
                  onPressed: _showCreateFamilyAccountBottomSheet,
                  color: const Color(0xFF9575CD),
                ),
              ],
            ),
          const SizedBox(height: 30),

          // Admin Section
          _buildRoleHeader(Icons.shield, "Admin", const Color(0xFFFFA726)),
          _buildUserTile(
            _adminDisplayName,
            _adminEmail.isEmpty ? AppBranding.placeholderValue : _adminEmail,
            isYou: true,
          ),
          const SizedBox(height: 20),

          // Dynamic Caregivers Section
          _buildRoleHeader(
            Icons.medical_services,
            "Caregivers (${_caregivers.length})",
            const Color(0xFF00BFA5),
          ),
          if (_caregivers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 20),
              child: Text(
                _isLoadingUsers
                    ? "Loading caregivers..."
                    : "No caregivers registered.",
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...List.generate(_caregivers.length, (index) {
              final isDisabled = _isDisabledAccount(_caregivers[index]);
              return _buildUserTile(
                _caregivers[index]["name"]!,
                _caregivers[index]["email"]!,
                isDisabled: isDisabled,
                onToggleStatus: () => _confirmStatusChange(
                  _caregivers[index]["name"]!,
                  true,
                  index,
                  userId: _caregivers[index]["id"],
                  enable: isDisabled,
                ),
                onEdit: () => _showEditAccountBottomSheet(
                  _caregivers[index],
                  isCaregiver: true,
                  index: index,
                ),
                onDelete: () => _confirmDeleteAccount(
                  _caregivers[index]["name"]!,
                  true,
                  index,
                  userId: _caregivers[index]["id"],
                ),
              );
            }),
          const SizedBox(height: 10),

          // Dynamic Family Section
          _buildRoleHeader(
            Icons.family_restroom,
            "Family Members (${_families.length})",
            const Color(0xFF9575CD),
          ),
          if (_families.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 20),
              child: Text(
                _isLoadingUsers
                    ? "Loading family users..."
                    : "No family members registered.",
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...List.generate(_families.length, (index) {
              final isDisabled = _isDisabledAccount(_families[index]);
              return _buildUserTile(
                _families[index]["name"]!,
                _families[index]["email"]!,
                isDisabled: isDisabled,
                onToggleStatus: () => _confirmStatusChange(
                  _families[index]["name"]!,
                  false,
                  index,
                  userId: _families[index]["id"],
                  enable: isDisabled,
                ),
                onEdit: () => _showEditAccountBottomSheet(
                  _families[index],
                  isCaregiver: false,
                  index: index,
                ),
                onDelete: () => _confirmDeleteAccount(
                  _families[index]["name"]!,
                  false,
                  index,
                  userId: _families[index]["id"],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildCreateAccountButton({
    required IconData icon,
    required String title,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String title,
    String subtitle,
    Color iconBg,
  ) {
    return Row(
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
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

  Widget _buildSummaryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 700
            ? 4
            : width >= 360
            ? 2
            : 1;
        const spacing = 8.0;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: _buildSummaryBox(
                "${_taskDonePercent.clamp(0, 100)}%",
                "Task Done",
                const Color(0xFFE8F5E9),
                const Color(0xFF00C853),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildSummaryBox(
                "${_medRatePercent.clamp(0, 100)}%",
                "Med Rate",
                const Color(0xFFE0F2F1),
                const Color(0xFF00BFA5),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildSummaryBox(
                _missedCount.toString(),
                "Missed",
                const Color(0xFFFFEBEE),
                const Color(0xFFE53935),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildSummaryBox(
                _residentCount.toString(),
                "Residents",
                const Color(0xFFFFF3E0),
                const Color(0xFFFFA726),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryBox(
    String value,
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
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleHeader(IconData icon, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(
    String name,
    String email, {
    bool isYou = false,
    bool isDisabled = false,
    VoidCallback? onToggleStatus,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    final statusColor = isDisabled
        ? const Color(0xFFE53935)
        : const Color(0xFF00C853);
    final statusBg = isDisabled
        ? const Color(0xFFFFEBEE)
        : const Color(0xFFE8F5E9);
    final toggleLabel = isDisabled ? 'Enable' : 'Disable';
    final toggleIcon = isDisabled ? Icons.check_circle_outline : Icons.block;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFF8F9FA),
            child: Text(
              name.isEmpty ? "?" : name[0],
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  email,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (isDisabled) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Disabled',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isYou)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Text(
                "You",
                style: TextStyle(
                  color: Color(0xFFFFA726),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: onToggleStatus,
                  icon: Icon(toggleIcon, size: 16),
                  label: Text(toggleLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: statusColor,
                    side: BorderSide(color: statusColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Account actions',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'toggle') {
                      onToggleStatus?.call();
                    } else if (value == 'edit') {
                      onEdit?.call();
                    } else if (value == 'delete') {
                      onDelete?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Color(0xFF00BFA5),
                          ),
                          SizedBox(width: 10),
                          Text('Edit Account'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(toggleIcon, size: 18, color: statusColor),
                          const SizedBox(width: 10),
                          Text('$toggleLabel Account'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_forever,
                            size: 18,
                            color: Color(0xFFE53935),
                          ),
                          SizedBox(width: 10),
                          Text('Delete Account'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FacilityInfoSheet extends StatefulWidget {
  final FacilityInfo facilityInfo;

  const _FacilityInfoSheet({required this.facilityInfo});

  @override
  State<_FacilityInfoSheet> createState() => _FacilityInfoSheetState();
}

class _FacilityInfoSheetState extends State<_FacilityInfoSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _contactController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.facilityInfo.name);
    _contactController = TextEditingController(
      text: widget.facilityInfo.contactNumber,
    );
    _emailController = TextEditingController(text: widget.facilityInfo.email);
    _addressController = TextEditingController(
      text: widget.facilityInfo.address,
    );
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Facility name cannot be empty.');
      return;
    }

    if (email.isNotEmpty && !email.contains('@')) {
      _showSnackBar('Enter a valid support email.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FacilityInfoService.instance.updateFacilityInfo(
        FacilityInfo(
          id: widget.facilityInfo.id,
          name: name,
          contactNumber: _contactController.text.trim(),
          email: email,
          address: _addressController.text.trim(),
        ),
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _showSnackBar(e.message);
    } catch (_) {
      _showSnackBar('Failed to update facility details.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final height = mediaQuery.size.height;
    final isMobile = width < 600;
    final isTablet = width >= 600 && width < 1024;
    final horizontalInset = isMobile ? 12.0 : 32.0;
    final contentPadding = isMobile ? 18.0 : 24.0;
    final maxSheetWidth = isMobile
        ? double.infinity
        : isTablet
        ? 560.0
        : 520.0;
    final availableHeight =
        height -
        mediaQuery.viewInsets.bottom -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        24;
    final maxSheetHeight = (availableHeight * (isMobile ? 0.96 : 0.9))
        .clamp(360.0, isMobile ? height : 680.0)
        .toDouble();

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        horizontalInset,
        12,
        horizontalInset,
        mediaQuery.viewInsets.bottom + (isMobile ? 8 : 24),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxSheetWidth,
            maxHeight: maxSheetHeight,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(isMobile ? 24 : 18),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.all(contentPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Facility Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Facility Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Official Contact Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Support / Admin Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _addressController,
                    minLines: isMobile ? 2 : 3,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Facility Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Saving...' : 'Save'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: const Color(0xFF00BFA5),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditAccountSheet extends StatefulWidget {
  final Map<String, String> user;
  final bool isCaregiver;

  const _EditAccountSheet({required this.user, required this.isCaregiver});

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _primaryContactController;
  late final TextEditingController _secondaryContactController;
  late final TextEditingController _addressController;
  late final TextEditingController _relationshipController;
  late final TextEditingController _residentNameController;
  late final TextEditingController _residentRoomController;
  late final TextEditingController _residentBirthdayController;
  late final TextEditingController _residentAgeController;
  late final TextEditingController _residentAddressController;
  late final TextEditingController _residentConditionsController;
  bool _isSaving = false;
  String _residentGender = 'Male';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.user['name']);
    _emailController = TextEditingController(text: widget.user['email']);
    _primaryContactController = TextEditingController(
      text: widget.user['primaryContactNumber'],
    );
    _secondaryContactController = TextEditingController(
      text: widget.user['secondaryContactNumber'],
    );
    _addressController = TextEditingController(text: widget.user['address']);
    _relationshipController = TextEditingController(
      text: widget.user['relationship'],
    );
    _residentNameController = TextEditingController(
      text: widget.user['residentName'],
    );
    _residentRoomController = TextEditingController(
      text: widget.user['residentRoom'],
    );
    _residentBirthdayController = TextEditingController(
      text: widget.user['residentBirthday'],
    );
    _residentAgeController = TextEditingController(
      text: widget.user['residentAge'],
    );
    _residentAddressController = TextEditingController(
      text: widget.user['residentAddress'],
    );
    _residentConditionsController = TextEditingController(
      text: widget.user['residentConditions'],
    );
    final gender = (widget.user['residentGender'] ?? '').trim();
    if (gender == 'Female') {
      _residentGender = 'Female';
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _primaryContactController.dispose();
    _secondaryContactController.dispose();
    _addressController.dispose();
    _relationshipController.dispose();
    _residentNameController.dispose();
    _residentRoomController.dispose();
    _residentBirthdayController.dispose();
    _residentAgeController.dispose();
    _residentAddressController.dispose();
    _residentConditionsController.dispose();
    super.dispose();
  }

  List<String> _parseConditions(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _selectBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00BFA5),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) {
      return;
    }

    final now = DateTime.now();
    var age = now.year - picked.year;
    if (now.month < picked.month ||
        (now.month == picked.month && now.day < picked.day)) {
      age--;
    }

    setState(() {
      _residentBirthdayController.text =
          '${picked.month}/${picked.day}/${picked.year}';
      _residentAgeController.text = age.toString();
    });
  }

  Future<void> _submit() async {
    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final primaryContactNumber = _primaryContactController.text.trim();
    final secondaryContactNumber = _secondaryContactController.text.trim();
    final address = _addressController.text.trim();
    final relationship = _relationshipController.text.trim();
    final residentName = _residentNameController.text.trim();
    final residentRoom = _residentRoomController.text.trim();
    final residentAge = int.tryParse(_residentAgeController.text.trim());

    if (fullName.isEmpty || email.isEmpty) {
      setState(() => _errorMessage = 'Full name and email are required.');
      return;
    }
    if (primaryContactNumber.isNotEmpty && primaryContactNumber.length < 7) {
      setState(() => _errorMessage = 'Primary contact number must be valid.');
      return;
    }
    if (secondaryContactNumber.isNotEmpty &&
        secondaryContactNumber.length < 7) {
      setState(() => _errorMessage = 'Secondary contact number must be valid.');
      return;
    }
    if (!widget.isCaregiver &&
        (primaryContactNumber.isEmpty ||
            relationship.isEmpty ||
            residentName.isEmpty ||
            residentRoom.isEmpty ||
            residentAge == null ||
            residentAge <= 0)) {
      setState(
        () => _errorMessage = 'Please complete family resident details.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final updatedUser = await ProfileService.instance.updateAdminUser(
        userId: widget.user['id'] ?? '',
        email: email,
        fullName: fullName,
        primaryContactNumber: primaryContactNumber,
        secondaryContactNumber: widget.isCaregiver
            ? null
            : secondaryContactNumber,
        address: address,
        relationship: widget.isCaregiver ? null : relationship,
        resident: widget.isCaregiver
            ? null
            : {
                'name': residentName,
                'room': residentRoom,
                'age': residentAge,
                'birthday': _residentBirthdayController.text.trim(),
                'gender': _residentGender,
                'address': _residentAddressController.text.trim(),
                'conditions': _parseConditions(
                  _residentConditionsController.text,
                ),
              },
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(Map<String, dynamic>.from(updatedUser));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to update account.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF00BFA5),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInputField(
    String label,
    String hint,
    IconData icon,
    TextEditingController controller, {
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          onTap: onTap,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00BFA5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ['Male', 'Female'].map((gender) {
          final isSelected = _residentGender == gender;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _residentGender = gender),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  gender,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.black87 : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assignedResidents = (widget.user['assignedResidents'] ?? '').trim();

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 25,
            right: 25,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Edit ${widget.isCaregiver ? 'Caregiver' : 'Family'} Account",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 25),
                _buildSectionTitle("Profile Details"),
                _buildInputField(
                  "Full Name",
                  "Enter full name",
                  Icons.person_outline,
                  _fullNameController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Email",
                  "Enter email",
                  Icons.email_outlined,
                  _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Primary Contact Number",
                  "Enter primary contact number",
                  Icons.phone_outlined,
                  _primaryContactController,
                  keyboardType: TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                if (!widget.isCaregiver) ...[
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Secondary Contact Number (Optional)",
                    "Secondary Contact Number (Optional)",
                    Icons.phone_in_talk_outlined,
                    _secondaryContactController,
                    keyboardType: TextInputType.number,
                    textCapitalization: TextCapitalization.none,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Relationship",
                    "e.g. Daughter, Grandson",
                    Icons.people_outline,
                    _relationshipController,
                  ),
                ],
                const SizedBox(height: 15),
                _buildInputField(
                  "Address",
                  "Optional address",
                  Icons.home_outlined,
                  _addressController,
                ),
                if (widget.isCaregiver) ...[
                  const SizedBox(height: 25),
                  _buildSectionTitle("Assigned Residents"),
                  Text(
                    assignedResidents.isEmpty
                        ? "No residents currently assigned."
                        : assignedResidents,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 25),
                  _buildSectionTitle("Resident Details"),
                  _buildInputField(
                    "Resident Full Name",
                    "Enter resident name",
                    Icons.person_outline,
                    _residentNameController,
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Room",
                    "e.g. 101",
                    Icons.meeting_room_outlined,
                    _residentRoomController,
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Birthday",
                    "MM/DD/YYYY",
                    Icons.calendar_month_outlined,
                    _residentBirthdayController,
                    readOnly: true,
                    onTap: _selectBirthday,
                    textCapitalization: TextCapitalization.none,
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Age",
                    "0",
                    Icons.cake_outlined,
                    _residentAgeController,
                    keyboardType: TextInputType.number,
                    textCapitalization: TextCapitalization.none,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    "Gender",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  _buildGenderToggle(),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Resident Address",
                    "Optional resident address",
                    Icons.location_on_outlined,
                    _residentAddressController,
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(
                    "Medical Conditions / Diseases",
                    "e.g. Hypertension, Type 2 Diabetes",
                    Icons.medical_information_outlined,
                    _residentConditionsController,
                    maxLines: 2,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 20),
                    label: const Text(
                      "Save Changes",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00BFA5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Center(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateCaregiverSheet extends StatefulWidget {
  const _CreateCaregiverSheet();

  @override
  State<_CreateCaregiverSheet> createState() => _CreateCaregiverSheetState();
}

class _CreateCaregiverSheetState extends State<_CreateCaregiverSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fullName = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (fullName.isEmpty ||
        email.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(
        () => _errorMessage = 'Password and confirm password do not match.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final createdUser = await ProfileService.instance.createCaregiver(
        name: fullName,
        email: email,
        username: username,
        password: password,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(Map<String, dynamic>.from(createdUser));
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = 'Failed to create caregiver account.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildInputField(
    String label,
    String hint,
    IconData icon,
    TextEditingController controller, {
    bool isPassword = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: isPassword
              ? TextCapitalization.none
              : TextCapitalization.words,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFFFA726)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 25,
            right: 25,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Add New Account",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Use this form for caregiver accounts.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 25),
                _buildInputField(
                  "Full Name",
                  "e.g. Nurse Maria Cruz",
                  Icons.person_outline,
                  _nameController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Email",
                  "e.g. maria@gmail.com",
                  Icons.email_outlined,
                  _emailController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Username",
                  "e.g. nurse.maria",
                  Icons.account_circle_outlined,
                  _usernameController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Password",
                  "Enter password",
                  Icons.lock_outline,
                  _passwordController,
                  isPassword: true,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Confirm Password",
                  "Retype password",
                  Icons.lock_outline,
                  _confirmPasswordController,
                  isPassword: true,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.person_add, size: 20),
                    label: const Text(
                      "Create Caregiver Account",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA726),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Center(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateFamilySheet extends StatefulWidget {
  const _CreateFamilySheet();

  @override
  State<_CreateFamilySheet> createState() => _CreateFamilySheetState();
}

class _CreateFamilySheetState extends State<_CreateFamilySheet> {
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _secondaryContactNumberController =
      TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _residentNameController = TextEditingController();
  final TextEditingController _residentRoomController = TextEditingController(
    text: '101',
  );
  final TextEditingController _residentBirthdayController =
      TextEditingController();
  final TextEditingController _residentAgeController = TextEditingController();
  final TextEditingController _residentAddressController =
      TextEditingController();
  final TextEditingController _residentConditionsController =
      TextEditingController();

  bool _isSaving = false;
  String _residentGender = 'Male';
  String? _errorMessage;

  @override
  void dispose() {
    _contactNameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _relationshipController.dispose();
    _contactNumberController.dispose();
    _secondaryContactNumberController.dispose();
    _addressController.dispose();
    _residentNameController.dispose();
    _residentRoomController.dispose();
    _residentBirthdayController.dispose();
    _residentAgeController.dispose();
    _residentAddressController.dispose();
    _residentConditionsController.dispose();
    super.dispose();
  }

  List<String> _parseConditions(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _selectBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1960),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF9575CD),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) {
      return;
    }
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    var age = now.year - picked.year;
    if (now.month < picked.month ||
        (now.month == picked.month && now.day < picked.day)) {
      age--;
    }

    setState(() {
      _residentBirthdayController.text =
          '${picked.month}/${picked.day}/${picked.year}';
      _residentAgeController.text = age.toString();
    });
  }

  Future<void> _submit() async {
    final contactName = _contactNameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final relationship = _relationshipController.text.trim();
    final contactNumber = _contactNumberController.text.trim();
    final secondaryContactNumber = _secondaryContactNumberController.text
        .trim();
    final address = _addressController.text.trim();
    final residentName = _residentNameController.text.trim();
    final residentRoom = _residentRoomController.text.trim();
    final residentBirthday = _residentBirthdayController.text.trim();
    final residentAge = int.tryParse(_residentAgeController.text.trim());
    final residentAddress = _residentAddressController.text.trim();
    final residentConditions = _parseConditions(
      _residentConditionsController.text,
    );

    if (contactName.isEmpty ||
        email.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        relationship.isEmpty ||
        contactNumber.isEmpty ||
        residentName.isEmpty ||
        residentRoom.isEmpty ||
        residentAge == null) {
      setState(() => _errorMessage = 'Please fill in all required fields.');
      return;
    }

    if (contactNumber.length < 7) {
      setState(() => _errorMessage = 'Contact number must be valid.');
      return;
    }

    if (secondaryContactNumber.isNotEmpty &&
        secondaryContactNumber.length < 7) {
      setState(() => _errorMessage = 'Secondary contact number must be valid.');
      return;
    }

    if (residentAge <= 0) {
      setState(() => _errorMessage = 'Resident age must be valid.');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(
        () => _errorMessage = 'Password and confirm password do not match.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final createdUser = await ProfileService.instance.createFamilyAccount(
        email: email,
        username: username,
        password: password,
        contactName: contactName,
        relationship: relationship,
        contactNumber: contactNumber,
        secondaryContactNumber: secondaryContactNumber.isEmpty
            ? null
            : secondaryContactNumber,
        address: address,
        residentName: residentName,
        residentRoom: residentRoom,
        residentAge: residentAge,
        residentBirthday: residentBirthday,
        residentGender: _residentGender,
        residentAddress: residentAddress,
        residentConditions: residentConditions,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(Map<String, dynamic>.from(createdUser));
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = 'Failed to create family account.');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF9575CD),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInputField(
    String label,
    String hint,
    IconData icon,
    TextEditingController controller, {
    bool isPassword = false,
    bool readOnly = false,
    VoidCallback? onTap,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.words,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          onTap: onTap,
          obscureText: isPassword,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          autocorrect: false,
          enableSuggestions: !isPassword,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: Colors.grey),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF9575CD)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: ['Male', 'Female'].map((gender) {
          final isSelected = _residentGender == gender;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _residentGender = gender),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  gender,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.black87 : Colors.grey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 20,
            left: 25,
            right: 25,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Add Family Account",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Create the family login and resident profile here.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 25),
                _buildSectionTitle("Login Details"),
                _buildInputField(
                  "Email",
                  "e.g. family@gmail.com",
                  Icons.email_outlined,
                  _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Username",
                  "e.g. dela.cruz.family",
                  Icons.account_circle_outlined,
                  _usernameController,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Password",
                  "Enter password",
                  Icons.lock_outline,
                  _passwordController,
                  isPassword: true,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Confirm Password",
                  "Retype password",
                  Icons.lock_outline,
                  _confirmPasswordController,
                  isPassword: true,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 25),
                _buildSectionTitle("Family Contact"),
                _buildInputField(
                  "Full Name",
                  "e.g. Ana Dela Cruz",
                  Icons.person_outline,
                  _contactNameController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Relationship",
                  "e.g. Daughter, Grandson",
                  Icons.people_outline,
                  _relationshipController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Primary Contact Number",
                  "Enter primary contact number",
                  Icons.phone_outlined,
                  _contactNumberController,
                  keyboardType: TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Secondary Contact Number (Optional)",
                  "Secondary Contact Number (Optional)",
                  Icons.phone_in_talk_outlined,
                  _secondaryContactNumberController,
                  keyboardType: TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Address",
                  "Optional address",
                  Icons.home_outlined,
                  _addressController,
                ),
                const SizedBox(height: 25),
                _buildSectionTitle("Resident Details"),
                _buildInputField(
                  "Resident Full Name",
                  "Enter resident name",
                  Icons.person_outline,
                  _residentNameController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Room",
                  "e.g. 101",
                  Icons.meeting_room_outlined,
                  _residentRoomController,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Birthday",
                  "MM/DD/YYYY",
                  Icons.calendar_month_outlined,
                  _residentBirthdayController,
                  readOnly: true,
                  onTap: _selectBirthday,
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Age",
                  "0",
                  Icons.cake_outlined,
                  _residentAgeController,
                  keyboardType: TextInputType.number,
                  textCapitalization: TextCapitalization.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                ),
                const SizedBox(height: 15),
                const Text(
                  "Gender",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                _buildGenderToggle(),
                const SizedBox(height: 15),
                _buildInputField(
                  "Resident Address",
                  "Optional resident address",
                  Icons.location_on_outlined,
                  _residentAddressController,
                ),
                const SizedBox(height: 15),
                _buildInputField(
                  "Medical Conditions / Diseases",
                  "e.g. Hypertension, Type 2 Diabetes",
                  Icons.medical_information_outlined,
                  _residentConditionsController,
                  maxLines: 2,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.family_restroom, size: 20),
                    label: const Text(
                      "Create Family Account",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9575CD),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Center(
                    child: Text(
                      "Cancel",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
