import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/widgets/resident_list_card.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class ResidentsListScreen extends StatefulWidget {
  final int initialFilterIndex;
  const ResidentsListScreen({super.key, this.initialFilterIndex = 0});

  @override
  State<ResidentsListScreen> createState() => _ResidentsListScreenState();
}

class _ResidentsListScreenState extends State<ResidentsListScreen> {
  late int _selectedFilterIndex;
  final TextEditingController _searchController = TextEditingController();
  final ResidentService _residentService = ResidentService.instance;
  final List<String> _filters = [
    'All',
    'Medical Updates',
    'Stable',
    'Need Attention',
    'Critical',
  ];

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _residents = [];

  @override
  void initState() {
    super.initState();
    _selectedFilterIndex = widget.initialFilterIndex;
    _searchController.addListener(() => setState(() {}));
    _loadResidents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadResidents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _residentService.getResidents();
      if (!mounted) return;
      setState(() {
        _residents = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
      final name = (resident['name'] ?? '').toString().toLowerCase();
      final room = (resident['room'] ?? '').toString().toLowerCase();
      if (query.isNotEmpty && !name.contains(query) && !room.contains(query)) {
        return false;
      }

      final status = (resident['overallStatus'] ?? '').toString().toUpperCase();
      final medCount = (resident['medicationCount'] as num?)?.toInt() ?? 0;

      if (_selectedFilterIndex == 1) {
        return medCount > 0;
      }
      if (_selectedFilterIndex == 2) {
        return status == 'STABLE';
      }
      if (_selectedFilterIndex == 3) {
        return status == 'NEEDS_ATTENTION';
      }
      if (_selectedFilterIndex == 4) {
        return status == 'CRITICAL';
      }
      return true;
    }).toList();
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'NEEDS_ATTENTION':
        return 'Needs Attention';
      case 'CRITICAL':
        return 'Critical';
      case 'STABLE':
      default:
        return 'Stable';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _filteredResidents;

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth > 700 ? 24.0 : 20.0;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildSearchBar(),
                    const SizedBox(height: 20),
                    _buildFilters(),
                    const SizedBox(height: 15),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadResidents,
                        child: _isLoading
                            ? const InlineLoading(message: 'Loading residents...')
                            : _errorMessage != null
                                ? StatusView.error(
                                    title: 'Could not load residents',
                                    message: _errorMessage!,
                                    onAction: _loadResidents,
                                  )
                                : displayList.isEmpty
                                    ? const StatusView.empty(
                                        icon: Icons.people_outline,
                                        title: 'No residents found',
                                        message: 'Try another filter or search term.',
                                      )
                                    : ListView.builder(
                                        itemCount: displayList.length,
                                        itemBuilder: (context, index) {
                                          final resident = displayList[index];
                                          final residentId = (resident['id'] ?? '').toString();
                                          final medCount =
                                              (resident['medicationCount'] as num?)?.toInt() ?? 0;
                                          final taskCount =
                                              (resident['careTaskCount'] as num?)?.toInt() ?? 0;
                                          final status = _statusLabel(
                                            (resident['overallStatus'] ?? '').toString(),
                                          );

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: ResidentListCard(
                                              residentId: residentId,
                                              name: (resident['name'] ?? '').toString(),
                                              room: (resident['room'] ?? '').toString(),
                                              age: (resident['age'] ?? '').toString(),
                                              conditions: ((resident['conditions'] as List<dynamic>? ?? const [])
                                                      .map((e) => e.toString())
                                                      .toList())
                                                  .cast<String>(),
                                              medStatus: '$medCount meds',
                                              taskStatus: '$taskCount tasks',
                                              overallStatus: status,
                                              onViewDetails: () {},
                                            ),
                                          );
                                        },
                                      ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Residents',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFA726),
                ),
              ),
              Text(
                'All facility residents',
                style: TextStyle(color: Colors.grey, fontSize: 14),
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
          child: const Text(
            'Caregiver',
            style: TextStyle(
              color: Color(0xFFFFA726),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
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
          hintText: 'Search',
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
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedFilterIndex = index;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 15),
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? const Color(0xFF00BFA5) : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                _filters[index],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? const Color(0xFF00BFA5) : Colors.grey,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
