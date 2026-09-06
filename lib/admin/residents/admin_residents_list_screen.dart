import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/residents/admin_resident_detail_screen.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class AdminResidentsListScreen extends StatefulWidget {
  final int initialFilterIndex;

  const AdminResidentsListScreen({super.key, this.initialFilterIndex = 0});

  @override
  State<AdminResidentsListScreen> createState() =>
      _AdminResidentsListScreenState();
}

class _AdminResidentsListScreenState extends State<AdminResidentsListScreen> {
  late int _selectedFilterIndex;
  final List<String> _filters = [
    "All",
    "Unassigned",
    "Needs Attention",
    "Stable",
  ];

  final ResidentService _residentService = ResidentService.instance;
  final ProfileService _profileService = ProfileService.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _residents = [];
  List<Map<String, String>> _caregivers = [];

  @override
  void initState() {
    super.initState();
    _selectedFilterIndex = widget.initialFilterIndex
        .clamp(0, _filters.length - 1)
        .toInt();
    _searchController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final residents = await _residentService.getResidents();
      final caregivers = await _profileService.listAdminUsers(
        role: 'CAREGIVER',
      );
      if (!mounted) return;

      setState(() {
        _residents = mapListFrom(residents);
        _caregivers = mapListFrom(caregivers).map((item) {
          final caregiverProfile = asStringMap(item['caregiverProfile']);
          final displayName =
              (caregiverProfile?['displayName'] ??
                      item['username'] ??
                      item['email'] ??
                      'Caregiver')
                  .toString();
          return {'id': (item['id'] ?? '').toString(), 'name': displayName};
        }).toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load residents right now.';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredResidents {
    final query = _searchController.text.trim().toLowerCase();
    return _residents.where((resident) {
      final name = (resident["name"] ?? "").toString().toLowerCase();
      final room = (resident["room"] ?? "").toString().toLowerCase();
      if (query.isNotEmpty && !name.contains(query) && !room.contains(query)) {
        return false;
      }

      final status = (resident["overallStatus"] ?? "").toString().toUpperCase();
      final assigned = listFrom(resident["assignedCaregivers"]).isNotEmpty;

      if (_selectedFilterIndex == 1) return !assigned;
      if (_selectedFilterIndex == 2) return status == "NEEDS_ATTENTION";
      if (_selectedFilterIndex == 3) return status == "STABLE";
      return true;
    }).toList();
  }

  String _statusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case "NEEDS_ATTENTION":
        return "Needs Attention";
      case "CRITICAL":
        return "Critical";
      case "STABLE":
      default:
        return "Stable";
    }
  }

  Color _statusColor(String status) {
    if (status == "Stable") return const Color(0xFF00C853);
    if (status == "Critical") return const Color(0xFFE53935);
    return const Color(0xFFFFA726);
  }

  String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'R' : trimmed.substring(0, 1).toUpperCase();
  }

  Future<void> _assignCaregiver({
    required String residentId,
    required String caregiverId,
    required String caregiverName,
  }) async {
    try {
      await _residentService.assignCaregiver(
        residentId: residentId,
        caregiverId: caregiverId,
      );
      if (!mounted) return;

      setState(() {
        for (final resident in _residents) {
          if ((resident["id"] ?? '').toString() == residentId) {
            resident["assignedCaregivers"] = <Map<String, dynamic>>[
              {"id": caregiverId, "name": caregiverName},
            ];
            break;
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver assigned successfully.')),
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
    }
  }

  Future<void> _unassignCaregiver({required String residentId}) async {
    try {
      await _residentService.unassignCaregiver(residentId: residentId);
      if (!mounted) return;

      setState(() {
        for (final resident in _residents) {
          if ((resident["id"] ?? '').toString() == residentId) {
            resident["assignedCaregivers"] = <Map<String, dynamic>>[];
            break;
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caregiver unassigned successfully.')),
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
    }
  }

  Future<void> _showCaregiverSelectionSheet({
    required String residentId,
    required String residentName,
    required String? assignedCaregiverId,
    required String assignedCaregiverName,
    required bool isAssigned,
  }) async {
    if (residentId.isEmpty) return;

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
                        residentName,
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
                          subtitle: Text(assignedCaregiverName),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _unassignCaregiver(residentId: residentId);
                          },
                        ),
                        const Divider(height: 1),
                      ],
                      if (_caregivers.isEmpty)
                        const ListTile(
                          leading: Icon(Icons.person_off_outlined),
                          title: Text('No caregivers available'),
                        )
                      else
                        ..._caregivers.map((caregiver) {
                          final caregiverId = caregiver['id'] ?? '';
                          final isCurrent =
                              caregiverId.isNotEmpty &&
                              caregiverId == assignedCaregiverId;

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
                              caregiver['name'] ?? 'Caregiver',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: isCurrent
                                ? const Text('Currently assigned')
                                : null,
                            enabled: !isCurrent && caregiverId.isNotEmpty,
                            onTap: isCurrent || caregiverId.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(sheetContext);
                                    _assignCaregiver(
                                      residentId: residentId,
                                      caregiverId: caregiverId,
                                      caregiverName:
                                          caregiver['name'] ?? 'Caregiver',
                                    );
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

  @override
  Widget build(BuildContext context) {
    final displayedResidents = _filteredResidents;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 360
              ? 14.0
              : width < 700
              ? 20.0
              : 32.0;

          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1120),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: width < 700 ? 20 : 24),
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildSearchBar(),
                  const SizedBox(height: 20),
                  _buildFilters(),
                  const SizedBox(height: 15),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      child: _buildResidentContent(displayedResidents),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResidentContent(List<Map<String, dynamic>> displayedResidents) {
    if (_isLoading) {
      return const InlineLoading(message: 'Loading residents...');
    }

    if (_errorMessage != null) {
      return StatusView.error(
        title: 'Could not load residents',
        message: _errorMessage!,
        onAction: _loadData,
      );
    }

    if (displayedResidents.isEmpty) {
      return const StatusView.empty(
        icon: Icons.people_outline,
        title: 'No residents found',
        message: 'Try another filter or search term.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: displayedResidents.length,
            itemBuilder: (context, index) {
              return _buildAdminResidentCard(
                displayedResidents[index],
                context,
              );
            },
          );
        }

        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            mainAxisExtent: 292,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: displayedResidents.length,
          itemBuilder: (context, index) {
            return _buildAdminResidentCard(
              displayedResidents[index],
              context,
              isGrid: true,
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (Navigator.canPop(context))
                Padding(
                  padding: const EdgeInsets.only(right: 15, top: 4),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black87,
                      size: 20,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Residents",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFA726),
                      ),
                    ),
                    Text(
                      "Total facility overview",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
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
                "Admin",
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
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: "Search residents...",
          hintStyle: TextStyle(color: Colors.grey),
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_filters.length, (index) {
          final isSelected = _selectedFilterIndex == index;
          Color activeColor = (index == 1)
              ? const Color(0xFFFFA726)
              : const Color(0xFF00BFA5);
          if (index == 2) {
            activeColor = const Color(0xFFE53935);
          }

          return GestureDetector(
            onTap: () => setState(() => _selectedFilterIndex = index),
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? activeColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                _filters[index],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? activeColor : Colors.grey,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAdminResidentCard(
    Map<String, dynamic> resident,
    BuildContext context, {
    bool isGrid = false,
  }) {
    final status = _statusLabel((resident["overallStatus"] ?? "").toString());
    final statusColor = _statusColor(status);
    final statusBgColor = statusColor.withValues(alpha: 0.12);

    final assignedCaregivers = mapListFrom(resident["assignedCaregivers"]);
    final isAssigned = assignedCaregivers.isNotEmpty;
    final assignedCaregiverId = isAssigned
        ? (assignedCaregivers.first["id"] ?? "").toString()
        : null;
    final assignedName = isAssigned
        ? (assignedCaregivers.first["name"] ?? "Assigned").toString()
        : "Unassigned";
    final residentId = (resident["id"] ?? "").toString();

    final todayMedicationEventsTotal =
        (resident["todayMedicationEventsTotal"] as num?)?.toInt() ?? 0;
    final todayMedicationEventsCompleted =
        (resident["todayMedicationEventsCompleted"] as num?)?.toInt() ?? 0;
    final todayCareTasksTotal =
        (resident["todayCareTasksTotal"] as num?)?.toInt() ?? 0;
    final todayCareTasksCompleted =
        (resident["todayCareTasksCompleted"] as num?)?.toInt() ?? 0;
    final totalScheduled = todayMedicationEventsTotal + todayCareTasksTotal;
    final totalCompleted =
        todayMedicationEventsCompleted + todayCareTasksCompleted;
    final progress = totalScheduled == 0
        ? 0.0
        : (totalCompleted / totalScheduled).clamp(0.0, 1.0).toDouble();
    final completionLabel = totalScheduled == 0
        ? 'N/A'
        : '${(progress * 100).toInt()}%';

    final assignColor = isAssigned
        ? const Color(0xFF00C853)
        : const Color(0xFFFFA726);
    final assignBgColor = isAssigned
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFF3E0);

    final assignmentButtonUI = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
      decoration: BoxDecoration(
        color: assignBgColor,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: assignColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAssigned ? Icons.person : Icons.person_add_alt_1,
            size: 16,
            color: assignColor,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              assignedName,
              style: TextStyle(
                color: assignColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: assignColor),
        ],
      ),
    );

    return Container(
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        mainAxisAlignment: isGrid
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFE0F2F1),
                    child: Text(
                      _initial((resident["name"] ?? "").toString()),
                      style: const TextStyle(
                        color: Color(0xFF009688),
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (resident["name"] ?? "").toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Room ${(resident["room"] ?? "").toString()} - Age ${(resident["age"] ?? "").toString()}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: (stringListFrom(resident["conditions"]).map(
                            (cond) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  cond.toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          )).toList(),
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
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 340;

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                "Daily Completion",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                softWrap: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              completionLabel,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress > 0.7
                                  ? const Color(0xFF00C853)
                                  : const Color(0xFFFFA726),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          "Daily Completion",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress > 0.7
                                  ? const Color(0xFF00C853)
                                  : const Color(0xFFFFA726),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 48,
                        child: Text(
                          completionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          Column(
            children: [
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stackActions = constraints.maxWidth < 320;
                  final detailsButton = _buildCardActionButton(
                    icon: Icons.visibility_outlined,
                    label: 'View Details',
                    color: const Color(0xFF00BFA5),
                    backgroundColor: Colors.white,
                    borderColor: const Color(0xFF00BFA5),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminResidentDetailScreen(
                            residentId: residentId,
                            residentName: (resident["name"] ?? "").toString(),
                            assignedCaregiver: assignedName,
                            room: (resident["room"] ?? "").toString(),
                            age: (resident["age"] ?? "").toString(),
                            conditions: stringListFrom(resident["conditions"]),
                            medicationCount:
                                (resident["medicationCount"] as num?)
                                    ?.toInt() ??
                                0,
                            careTaskCount:
                                (resident["careTaskCount"] as num?)?.toInt() ??
                                0,
                            overallStatus: status,
                          ),
                        ),
                      );
                      if (!context.mounted) return;
                      await _loadData();
                    },
                  );
                  final assignmentButton = Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(25),
                      onTap: () => _showCaregiverSelectionSheet(
                        residentId: residentId,
                        residentName: (resident["name"] ?? "").toString(),
                        assignedCaregiverId: assignedCaregiverId,
                        assignedCaregiverName: assignedName,
                        isAssigned: isAssigned,
                      ),
                      child: assignmentButtonUI,
                    ),
                  );

                  if (stackActions) {
                    return Column(
                      children: [
                        detailsButton,
                        const SizedBox(height: 10),
                        assignmentButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: detailsButton),
                      const SizedBox(width: 10),
                      Expanded(child: assignmentButton),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color backgroundColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(25),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
