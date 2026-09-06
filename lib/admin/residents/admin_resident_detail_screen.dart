import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/message/admin_messages_tab.dart';
import 'package:medicare_tract/admin/residents/admin_care_tasks_screen.dart';
import 'package:medicare_tract/admin/residents/admin_medication_list_screen.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';

class AdminResidentDetailScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String assignedCaregiver;
  final String room;
  final String age;
  final List<String> conditions;
  final int medicationCount;
  final int careTaskCount;
  final String overallStatus;

  const AdminResidentDetailScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.assignedCaregiver,
    required this.room,
    required this.age,
    required this.conditions,
    required this.medicationCount,
    required this.careTaskCount,
    required this.overallStatus,
  });

  @override
  State<AdminResidentDetailScreen> createState() =>
      _AdminResidentDetailScreenState();
}

class _AdminResidentDetailScreenState extends State<AdminResidentDetailScreen> {
  late String _currentCaregiver;
  String? _currentCaregiverId;
  late int _medicationCount;
  late int _careTaskCount;
  String _medicalNotes = "No medical notes available yet.";
  List<String> _conditions = const [];
  Map<String, dynamic>? _familyProfile;
  bool _isLoadingResident = true;
  String? _residentError;

  final ProfileService _profileService = ProfileService.instance;
  final ResidentService _residentService = ResidentService.instance;
  bool _isLoadingCaregivers = true;
  bool _isAssigningCaregiver = false;
  String? _caregiverError;
  final List<_CaregiverOption> _availableCaregivers = [];

  @override
  void initState() {
    super.initState();
    _currentCaregiver = widget.assignedCaregiver;
    _medicationCount = widget.medicationCount;
    _careTaskCount = widget.careTaskCount;
    _conditions = widget.conditions;
    _loadResidentDetail();
    _loadCaregivers();
  }

  Future<void> _loadResidentDetail() async {
    try {
      final detail = await _residentService.getResidentDetail(
        widget.residentId,
      );
      if (!mounted) return;
      setState(() {
        _conditions = _conditionLabels(detail['conditions']);
        _familyProfile = _asMap(detail['familyProfile']);
        final notes = (detail['medicalNotes'] ?? '').toString().trim();
        _medicalNotes = notes.isEmpty
            ? "No medical notes available yet."
            : notes;
        final medications = listFrom(detail['medications']);
        final careTasks = listFrom(detail['careTasks']);
        final assignments = mapListFrom(detail['assignments']);
        if (assignments.isEmpty) {
          _currentCaregiver = 'Unassigned';
          _currentCaregiverId = null;
        } else {
          final assignment = assignments.first;
          final caregiver = _asMap(assignment['caregiver']);
          final caregiverProfile = _asMap(caregiver?['caregiverProfile']);
          final caregiverName =
              (caregiverProfile?['displayName'] ??
                      caregiver?['username'] ??
                      caregiver?['email'] ??
                      '')
                  .toString()
                  .trim();
          _currentCaregiver = caregiverName.isEmpty
              ? widget.assignedCaregiver
              : caregiverName;
          _currentCaregiverId =
              (assignment['caregiverId'] ?? caregiver?['id'] ?? '')
                  .toString()
                  .trim();
          if (_currentCaregiverId?.isEmpty == true) {
            _currentCaregiverId = null;
          }
        }
        _medicationCount = medications.length;
        _careTaskCount = careTasks.length;
        _isLoadingResident = false;
        _residentError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingResident = false;
        _residentError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingResident = false;
        _residentError = 'Unable to load resident details.';
      });
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    return asStringMap(value);
  }

  List<String> _conditionLabels(dynamic raw) {
    return stringListFrom(raw);
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'C' : trimmed.substring(0, 1).toUpperCase();
  }

  String _familyContactDetail() {
    final profile = _familyProfile;
    if (_isLoadingResident) {
      return 'Loading family contact...';
    }
    if (profile == null) {
      return 'Family contact not available';
    }
    final name = (profile['contactName'] ?? '').toString().trim();
    final relationship = (profile['relationship'] ?? '').toString().trim();
    final phone = (profile['contactNumber'] ?? '').toString().trim();
    final secondaryPhone = (profile['secondaryContactNumber'] ?? '')
        .toString()
        .trim();
    final parts = <String>[
      if (name.isNotEmpty) name,
      if (relationship.isNotEmpty) relationship,
      if (phone.isNotEmpty) 'Primary: $phone',
      if (secondaryPhone.isNotEmpty) 'Secondary: $secondaryPhone',
    ];
    return parts.isEmpty ? 'Family contact not available' : parts.join('\n');
  }

  Future<void> _loadCaregivers() async {
    try {
      final caregivers = await _profileService.listAdminUsers(
        role: 'CAREGIVER',
      );
      if (!mounted) return;

      setState(() {
        _availableCaregivers.clear();
        _availableCaregivers.addAll(
          mapListFrom(caregivers).map((item) {
            final caregiverProfile = asStringMap(item['caregiverProfile']);
            final displayName =
                (caregiverProfile?['displayName'] ??
                        item['name'] ??
                        item['username'] ??
                        item['email'] ??
                        'Caregiver')
                    .toString()
                    .trim();
            return _CaregiverOption(
              id: (item['id'] ?? '').toString(),
              name: displayName.isEmpty ? 'Caregiver' : displayName,
            );
          }),
        );
        _isLoadingCaregivers = false;
        _caregiverError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingCaregivers = false;
        _caregiverError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCaregivers = false;
        _caregiverError = 'Unable to load registered caregivers.';
      });
    }
  }

  Future<void> _assignCaregiver(_CaregiverOption caregiver) async {
    setState(() {
      _isAssigningCaregiver = true;
    });
    try {
      await _residentService.assignCaregiver(
        residentId: widget.residentId,
        caregiverId: caregiver.id,
      );
      if (!mounted) return;
      setState(() {
        _currentCaregiver = caregiver.name;
        _currentCaregiverId = caregiver.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${caregiver.name} assigned to ${widget.residentName}!',
          ),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to assign caregiver.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningCaregiver = false;
        });
      }
    }
  }

  Future<void> _unassignCaregiver() async {
    setState(() {
      _isAssigningCaregiver = true;
    });
    try {
      await _residentService.unassignCaregiver(residentId: widget.residentId);
      if (!mounted) return;
      setState(() {
        _currentCaregiver = 'Unassigned';
        _currentCaregiverId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Caregiver unassigned from ${widget.residentName}.'),
          backgroundColor: const Color(0xFF00C853),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to unassign caregiver.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningCaregiver = false;
        });
      }
    }
  }

  Future<void> _showCaregiverSelectionSheet() async {
    final isAssigned = _currentCaregiver.toLowerCase() != 'unassigned';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAssigned ? 'Change caregiver' : 'Assign caregiver',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.residentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (isAssigned) ...[
                        ListTile(
                          leading: const Icon(
                            Icons.person_remove_outlined,
                            color: Color(0xFFFF5252),
                          ),
                          title: const Text(
                            'Unassign caregiver',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(_currentCaregiver),
                          enabled: !_isAssigningCaregiver,
                          onTap: _isAssigningCaregiver
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  _unassignCaregiver();
                                },
                        ),
                        const Divider(height: 1),
                      ],
                      if (_isLoadingCaregivers)
                        const ListTile(
                          leading: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00BFA5),
                            ),
                          ),
                          title: Text('Loading caregivers...'),
                        )
                      else if (_caregiverError != null)
                        ListTile(
                          leading: const Icon(
                            Icons.error_outline,
                            color: Color(0xFFE53935),
                          ),
                          title: Text(_caregiverError!),
                        )
                      else if (_availableCaregivers.isEmpty)
                        const ListTile(
                          leading: Icon(Icons.person_off_outlined),
                          title: Text('No registered caregivers available'),
                        )
                      else
                        ..._availableCaregivers.map((caregiver) {
                          final isCurrent =
                              caregiver.id.isNotEmpty &&
                              caregiver.id == _currentCaregiverId;

                          return ListTile(
                            leading: Icon(
                              isCurrent
                                  ? Icons.check_circle
                                  : Icons.person_outline,
                              color: isCurrent
                                  ? const Color(0xFF00C853)
                                  : const Color(0xFF00BFA5),
                            ),
                            title: Text(
                              caregiver.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: isCurrent
                                ? const Text('Currently assigned')
                                : null,
                            enabled:
                                !isCurrent &&
                                !_isAssigningCaregiver &&
                                caregiver.id.isNotEmpty,
                            onTap:
                                isCurrent ||
                                    _isAssigningCaregiver ||
                                    caregiver.id.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(sheetContext);
                                    _assignCaregiver(caregiver);
                                  },
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditNotesDialog() {
    TextEditingController notesController = TextEditingController(
      text: _medicalNotes,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFF00BFA5)),
            SizedBox(width: 10),
            Text(
              "Edit Medical Notes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: TextField(
            controller: notesController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: "Enter updated medical notes here...",
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFF00BFA5)),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _medicalNotes = notesController.text;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Medical notes updated successfully!"),
                  backgroundColor: Color(0xFF00C853),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              "Save Notes",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFE53935);
      case 'NEEDS ATTENTION':
      case 'NEEDS_ATTENTION':
        return const Color(0xFFFFA726);
      case 'STABLE':
      default:
        return const Color(0xFF00C853);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE0F2F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(bottom: 25),
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 35,
                        backgroundColor: Color(0xFF00BFA5),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.residentName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Room ${widget.room.isEmpty ? '-' : widget.room} - Age ${widget.age.isEmpty ? '-' : widget.age}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(widget.overallStatus),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          widget.overallStatus,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatColumn(_medicationCount.toString(), "Meds"),
                          _StatColumn(_careTaskCount.toString(), "Tasks"),
                          const _StatColumn("0", "Unread Msgs"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAssignmentStatusCard(),
                      if (_residentError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _residentError!,
                          style: const TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 25),

                      LayoutBuilder(
                        builder: (context, inner) {
                          final cards = [
                            _buildActionButton(
                              Icons.add_box,
                              "Medications",
                              "$_medicationCount created",
                              const Color(0xFF00BFA5),
                              () async {
                                final medicationCount =
                                    await Navigator.push<int>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AdminMedicationListScreen(
                                              residentId: widget.residentId,
                                              residentName: widget.residentName,
                                            ),
                                      ),
                                    );
                                if (medicationCount != null && mounted) {
                                  setState(
                                    () => _medicationCount = medicationCount,
                                  );
                                }
                              },
                            ),
                            _buildActionButton(
                              Icons.assignment_outlined,
                              "Care Tasks",
                              "$_careTaskCount assigned",
                              Colors.grey,
                              () async {
                                final taskCount = await Navigator.push<int>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminCareTasksScreen(
                                      residentId: widget.residentId,
                                      residentName: widget.residentName,
                                      assignedCaregiver: _currentCaregiver,
                                    ),
                                  ),
                                );
                                if (taskCount != null && mounted) {
                                  setState(() => _careTaskCount = taskCount);
                                }
                              },
                            ),
                            _buildActionButton(
                              Icons.chat_bubble_outline,
                              "Messages",
                              "No unread",
                              const Color(0xFF9575CD),
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => Scaffold(
                                      backgroundColor: const Color(0xFFF8F9FA),
                                      appBar: AppBar(
                                        backgroundColor: Colors.transparent,
                                        elevation: 0,
                                        leading: IconButton(
                                          icon: const Icon(
                                            Icons.arrow_back_ios,
                                            color: Colors.black87,
                                            size: 20,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context),
                                        ),
                                      ),
                                      body: const AdminMessagesTab(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ];

                          if (inner.maxWidth < 420) {
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: cards,
                            );
                          }

                          return Row(
                            children: [
                              for (final card in cards)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: card,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 25),

                      const Text(
                        "Medical Conditions",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoadingResident)
                        const Text(
                          "Loading medical conditions...",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else if (_conditions.isEmpty)
                        const Text(
                          "No medical conditions listed yet.",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: _conditions
                              .map(_buildConditionChip)
                              .toList(),
                        ),
                      const SizedBox(height: 25),

                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.note_alt_outlined,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      "Medical Notes",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  onPressed: _showEditNotesDialog,
                                  icon: const Icon(
                                    Icons.edit_square,
                                    color: Color(0xFF00BFA5),
                                  ),
                                  tooltip: "Edit Notes",
                                ),
                              ],
                            ),
                            Text(
                              _medicalNotes,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const Divider(height: 30),
                            _buildContactRow(
                              Icons.contact_phone_outlined,
                              "Emergency Contact",
                              _familyContactDetail(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentStatusCard() {
    final bool isUnassigned = _currentCaregiver.toLowerCase() == "unassigned";

    final bool noAvailableCaregivers =
        !_isLoadingCaregivers && _availableCaregivers.isEmpty;
    final String statusMessage = _caregiverError != null
        ? _caregiverError!
        : _isLoadingCaregivers
        ? 'Loading caregivers...'
        : noAvailableCaregivers
        ? 'No registered caregivers available.'
        : 'No caregiver has claimed this resident.';

    if (isUnassigned) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFFFA726)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFFA726),
              size: 30,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Unassigned",
                    style: TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusMessage,
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showCaregiverSelectionSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFFA726)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isLoadingCaregivers
                            ? 'Loading...'
                            : _availableCaregivers.isEmpty
                            ? 'No caregivers'
                            : _isAssigningCaregiver
                            ? 'Assigning...'
                            : 'Assign',
                        style: const TextStyle(
                          color: Color(0xFFFFA726),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFFFFA726),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _showCaregiverSelectionSheet,
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFF00BFA5).withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE0F2F1),
                  child: Text(
                    _initial(_currentCaregiver),
                    style: const TextStyle(
                      color: Color(0xFF00BFA5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Assigned Caregiver",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        _currentCaregiver,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_circle_outlined,
                  color: Color(0xFF00BFA5),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildActionButton(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withValues(alpha: 0.5)),
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
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00BFA5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Color(0xFF00BFA5), size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF00BFA5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF00BFA5), size: 20),
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
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaregiverOption {
  final String id;
  final String name;

  _CaregiverOption({required this.id, required this.name});
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
