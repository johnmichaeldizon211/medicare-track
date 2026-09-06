import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medicare_tract/core/services/inventory_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class MedicineInventoryScreen extends StatefulWidget {
  const MedicineInventoryScreen({super.key});

  @override
  State<MedicineInventoryScreen> createState() =>
      _MedicineInventoryScreenState();
}

class _MedicineInventoryScreenState extends State<MedicineInventoryScreen> {
  final InventoryService _inventoryService = InventoryService.instance;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyItemIds = {};
  static const int _expirationAlertWindowDays =
      InventoryService.expirationAlertWindowDays;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _safeInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<Map<String, dynamic>> get _filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _items;
    }

    return _items.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      return name.contains(query);
    }).toList();
  }

  int get _totalStock =>
      _items.fold(0, (sum, item) => sum + _safeInt(item['count']));

  int get _lowStockCount =>
      _items.where((item) => _safeInt(item['count']) <= 5).length;

  int get _expiryAlertCount =>
      _items.where(_hasExpiredOrExpiringSoonMedicine).length;

  int get _expiredCount => _items.where(_isExpiredMedicine).length;

  int get _expiringSoonCount => _items.where(_isExpiringSoonMedicine).length;

  bool get _hasExpiryAlerts => _expiryAlertCount > 0;

  List<Map<String, dynamic>> get _expiryAlertItems =>
      _items.where(_hasExpiredOrExpiringSoonMedicine).toList();

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _inventoryService.getMedicineInventory();
      if (!mounted) {
        return;
      }
      final loadedItems = items
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _items = loadedItems;
        _isLoading = false;
      });
      _syncExpirationAlerts(loadedItems);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load medicine inventory right now.';
        _isLoading = false;
      });
    }
  }

  void _replaceItem(Map<String, dynamic> updatedItem) {
    setState(() {
      final updatedId = (updatedItem['id'] ?? '').toString();
      final index = _items.indexWhere(
        (item) => (item['id'] ?? '').toString() == updatedId,
      );
      if (index >= 0) {
        _items[index] = updatedItem;
      } else {
        _items.insert(0, updatedItem);
      }
      _items.sort((a, b) {
        final expiryCompare = _expirySortRank(a).compareTo(_expirySortRank(b));
        if (expiryCompare != 0) {
          return expiryCompare;
        }
        final expiryDateA = _expirationDateFrom(a['expirationDate']);
        final expiryDateB = _expirationDateFrom(b['expirationDate']);
        if (expiryDateA != null && expiryDateB != null) {
          final dateCompare = expiryDateA.compareTo(expiryDateB);
          if (dateCompare != 0) {
            return dateCompare;
          }
        }
        final countCompare = _safeInt(
          a['count'],
        ).compareTo(_safeInt(b['count']));
        if (countCompare != 0) {
          return countCompare;
        }
        return (a['name'] ?? '').toString().compareTo(
          (b['name'] ?? '').toString(),
        );
      });
    });
  }

  Future<void> _addMedicine() async {
    final result = await _showMedicineDialog();
    if (result == null || !mounted) {
      return;
    }

    try {
      final item = await _inventoryService.createMedicine(
        name: result.name,
        count: result.count,
        expirationDate: result.expirationDate,
      );
      if (!mounted) {
        return;
      }
      _replaceItem(item);
      _syncExpirationAlerts([item]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine added to inventory.')),
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to add medicine.')));
    }
  }

  Future<void> _adjustMedicine(Map<String, dynamic> item, int delta) async {
    final itemId = (item['id'] ?? '').toString();
    if (itemId.isEmpty || _busyItemIds.contains(itemId)) {
      return;
    }

    setState(() => _busyItemIds.add(itemId));
    try {
      final updated = await _inventoryService.adjustMedicine(
        id: itemId,
        delta: delta,
      );
      if (!mounted) {
        return;
      }
      _replaceItem(updated);
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
        const SnackBar(content: Text('Failed to update medicine count.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busyItemIds.remove(itemId));
      }
    }
  }

  Future<void> _openAdjustmentDialog({
    required Map<String, dynamic> item,
    required bool isAdding,
  }) async {
    final amount = await _showAdjustmentDialog(
      itemName: (item['name'] ?? 'Medicine').toString(),
      currentCount: _safeInt(item['count']),
      isAdding: isAdding,
    );
    if (amount == null) {
      return;
    }

    await _adjustMedicine(item, isAdding ? amount : -amount);
  }

  Future<_MedicineFormResult?> _showMedicineDialog({
    String? initialName,
    int? initialCount,
    DateTime? initialExpirationDate,
  }) async {
    return showDialog<_MedicineFormResult>(
      context: context,
      builder: (_) => _AddMedicineDialog(
        initialName: initialName,
        initialCount: initialCount ?? 0,
        initialExpirationDate: initialExpirationDate,
      ),
    );
  }

  Future<void> _editMedicine(Map<String, dynamic> item) async {
    final itemId = (item['id'] ?? '').toString();
    final initialName = (item['name'] ?? '').toString();
    final initialCount = _safeInt(item['count']);
    final initialExpirationDate = _expirationDateFrom(item['expirationDate']);

    final result = await _showMedicineDialog(
      initialName: initialName,
      initialCount: initialCount,
      initialExpirationDate: initialExpirationDate,
    );
    if (result == null) return;

    try {
      final updated = await _inventoryService.updateMedicine(
        id: itemId,
        name: result.name,
        count: result.count,
        expirationDate: result.expirationDate,
      );
      if (!mounted) return;
      _replaceItem(updated);
      _syncExpirationAlerts([updated]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medicine updated.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update medicine.')),
      );
    }
  }

  Future<void> _deleteMedicine(Map<String, dynamic> item) async {
    final itemId = (item['id'] ?? '').toString();
    if (itemId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete medicine'),
        content: const Text('Are you sure you want to delete this medicine?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busyItemIds.add(itemId));
    try {
      await _inventoryService.deleteMedicine(id: itemId);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => (i['id'] ?? '').toString() == itemId);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medicine deleted.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete medicine.')),
      );
    } finally {
      if (mounted) setState(() => _busyItemIds.remove(itemId));
    }
  }

  Future<int?> _showAdjustmentDialog({
    required String itemName,
    required int currentCount,
    required bool isAdding,
  }) async {
    return showDialog<int>(
      context: context,
      builder: (_) => _StockAdjustmentDialog(
        itemName: itemName,
        currentCount: currentCount,
        isAdding: isAdding,
      ),
    );
  }

  void _syncExpirationAlerts(List<Map<String, dynamic>> items) {
    unawaited(
      _inventoryService.syncExpirationAlerts(items: items).catchError((_) => 0),
    );
  }

  DateTime? _expirationDateFrom(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  int? _daysUntilExpiration(Map<String, dynamic> item) {
    final expirationDate = _expirationDateFrom(item['expirationDate']);
    if (expirationDate == null) {
      return null;
    }
    return expirationDate.difference(_today()).inDays;
  }

  bool _isExpiredMedicine(Map<String, dynamic> item) {
    final days = _daysUntilExpiration(item);
    return days != null && days < 0;
  }

  bool _isExpiringSoonMedicine(Map<String, dynamic> item) {
    final days = _daysUntilExpiration(item);
    return days != null && days >= 0 && days <= _expirationAlertWindowDays;
  }

  bool _hasExpiredOrExpiringSoonMedicine(Map<String, dynamic> item) {
    final days = _daysUntilExpiration(item);
    return days != null && days <= _expirationAlertWindowDays;
  }

  int _expirySortRank(Map<String, dynamic> item) {
    if (_isExpiredMedicine(item)) {
      return 0;
    }
    if (_isExpiringSoonMedicine(item)) {
      return 1;
    }
    if (_expirationDateFrom(item['expirationDate']) != null) {
      return 2;
    }
    return 3;
  }

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  String _expirationDateLabel(Map<String, dynamic> item) {
    final expirationDate = _expirationDateFrom(item['expirationDate']);
    if (expirationDate == null) {
      return 'No expiry date';
    }
    return 'Exp: ${_formatDate(expirationDate)}';
  }

  String _expirationStatusLabel(Map<String, dynamic> item) {
    final days = _daysUntilExpiration(item);
    if (days == null) {
      return 'No Expiry';
    }
    if (days < 0) {
      return 'Expired';
    }
    if (days == 0) {
      return 'Expires Today';
    }
    if (days <= _expirationAlertWindowDays) {
      return 'Expiring Soon';
    }
    return 'Valid';
  }

  Color _expirationStatusColor(Map<String, dynamic> item) {
    final days = _daysUntilExpiration(item);
    if (days == null) {
      return Colors.grey;
    }
    if (days < 0) {
      return const Color(0xFFE53935);
    }
    if (days <= _expirationAlertWindowDays) {
      return const Color(0xFFFFA726);
    }
    return const Color(0xFF00C853);
  }

  @override
  Widget build(BuildContext context) {
    final displayedItems = _filteredItems;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 360
              ? 14.0
              : width < 700
              ? 20.0
              : 32.0;

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: RefreshIndicator(
                  onRefresh: _loadInventory,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: width < 700 ? 20 : 24),
                            _buildHeader(),
                            const SizedBox(height: 18),
                            _buildSummaryGrid(),
                            if (_hasExpiryAlerts) ...[
                              const SizedBox(height: 12),
                              _buildExpiryAlertBanner(),
                            ],
                            const SizedBox(height: 18),
                            _buildSearchBar(),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ),
                      ..._buildInventorySlivers(displayedItems),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildInventorySlivers(
    List<Map<String, dynamic>> displayedItems,
  ) {
    if (_isLoading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: InlineLoading(message: 'Loading inventory...'),
        ),
      ];
    }

    if (_errorMessage != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView.error(
            title: 'Could not load inventory',
            message: _errorMessage!,
            onAction: _loadInventory,
          ),
        ),
      ];
    }

    if (displayedItems.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView.empty(
            icon: Icons.inventory_2_outlined,
            title: 'No medicine found',
            message: _searchController.text.trim().isEmpty
                ? 'Add medicine stock to start tracking inventory.'
                : 'Try another search term.',
          ),
        ),
      ];
    }

    return [
      SliverLayoutBuilder(
        builder: (context, constraints) {
          if (constraints.crossAxisExtent < 700) {
            return SliverList.builder(
              itemCount: displayedItems.length,
              itemBuilder: (context, index) {
                return _buildMedicineCard(displayedItems[index]);
              },
            );
          }

          return SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 304,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
            ),
            itemCount: displayedItems.length,
            itemBuilder: (context, index) {
              return _buildMedicineCard(displayedItems[index], isGrid: true);
            },
          );
        },
      ),
    ];
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final title = const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Medicine Inventory',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
            Text(
              'Facility stock control',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        );
        final addButton = ElevatedButton.icon(
          onPressed: _addMedicine,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFA726),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), addButton],
          );
        }

        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 12),
            addButton,
          ],
        );
      },
    );
  }

  Widget _buildSummaryGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 820
            ? 4
            : width >= 300
            ? 2
            : 1;
        final spacing = width < 340 ? 10.0 : 12.0;
        final tileWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: tileWidth,
              child: _buildSummaryTile(
                icon: Icons.medication_outlined,
                label: 'Medicine Types',
                value: '${_items.length}',
                color: const Color(0xFF00BFA5),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _buildSummaryTile(
                icon: Icons.inventory_2_outlined,
                label: 'Total Stock',
                value: '$_totalStock',
                color: const Color(0xFFFFA726),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _buildSummaryTile(
                icon: Icons.warning_amber_rounded,
                label: 'Low Stock',
                value: '$_lowStockCount',
                color: const Color(0xFFE53935),
              ),
            ),
            SizedBox(
              width: tileWidth,
              child: _buildSummaryTile(
                icon: Icons.event_busy_outlined,
                label: 'Expiry Alerts',
                value: '$_expiryAlertCount',
                color: const Color(0xFFD81B60),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiryAlertBanner() {
    final alertItems = _expiryAlertItems;
    final firstAlert = alertItems.first;
    final firstName = (firstAlert['name'] ?? 'Medicine').toString();
    final days = _daysUntilExpiration(firstAlert);
    final detail = _expiredCount > 0
        ? '$_expiredCount expired, $_expiringSoonCount expiring within '
              '$_expirationAlertWindowDays days'
        : '$_expiringSoonCount expiring within '
              '$_expirationAlertWindowDays days';
    final firstDetail = days == null
        ? ''
        : days < 0
        ? '$firstName already expired.'
        : days == 0
        ? '$firstName expires today.'
        : '$firstName expires in $days day${days == 1 ? '' : 's'}.';
    final alertColor = _expiredCount > 0
        ? const Color(0xFFE53935)
        : const Color(0xFFFFA726);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alertColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alertColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: alertColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.notification_important, color: alertColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medicine expiry alert',
                  style: TextStyle(
                    color: alertColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: Color(0xFF2D0C57),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (firstDetail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    firstDetail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
        decoration: InputDecoration(
          hintText: 'Search medicine...',
          hintStyle: const TextStyle(color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchController.text.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildMedicineCard(Map<String, dynamic> item, {bool isGrid = false}) {
    final itemId = (item['id'] ?? '').toString();
    final name = (item['name'] ?? 'Medicine').toString();
    final count = _safeInt(item['count']);
    final busy = _busyItemIds.contains(itemId);
    final lowStock = count <= 5;
    final stockStatusColor = lowStock
        ? const Color(0xFFE53935)
        : const Color(0xFF00C853);
    final expiryStatusColor = _expirationStatusColor(item);
    final hasExpiryAttention = _hasExpiredOrExpiringSoonMedicine(item);
    final borderColor = hasExpiryAttention
        ? expiryStatusColor.withValues(alpha: 0.35)
        : Colors.grey.withValues(alpha: 0.2);

    return Container(
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
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
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.medication_liquid,
                  color: Color(0xFF00BFA5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _buildInventoryChip(
                          lowStock ? 'Low Stock' : 'In Stock',
                          stockStatusColor,
                        ),
                        _buildInventoryChip(
                          _expirationStatusLabel(item),
                          expiryStatusColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 78),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        '$count',
                        maxLines: 1,
                        style: TextStyle(
                          color: stockStatusColor,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'count',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<int>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onSelected: (v) {
                      if (v == 1) {
                        _editMedicine(item);
                      } else if (v == 2) {
                        _deleteMedicine(item);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 1, child: Text('Edit')),
                      const PopupMenuItem(value: 2, child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, color: expiryStatusColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _expirationDateLabel(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: expiryStatusColor,
                    fontSize: 12,
                    fontWeight: hasExpiryAttention
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildRoundAdjustButton(
                icon: Icons.remove,
                color: const Color(0xFFE53935),
                tooltip: 'Subtract 1',
                onPressed: busy || count == 0
                    ? null
                    : () => _adjustMedicine(item, -1),
              ),
              const SizedBox(width: 10),
              _buildRoundAdjustButton(
                icon: Icons.add,
                color: const Color(0xFF00BFA5),
                tooltip: 'Add 1',
                onPressed: busy ? null : () => _adjustMedicine(item, 1),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 300;
              final addButton = _buildStockActionButton(
                label: 'Add Stock',
                icon: Icons.add_box_outlined,
                color: const Color(0xFF00BFA5),
                onPressed: busy
                    ? null
                    : () => _openAdjustmentDialog(item: item, isAdding: true),
              );
              final removeButton = _buildStockActionButton(
                label: 'Remove Stock',
                icon: Icons.indeterminate_check_box_outlined,
                color: const Color(0xFFE53935),
                onPressed: busy || count == 0
                    ? null
                    : () => _openAdjustmentDialog(item: item, isAdding: false),
              );

              if (!useTwoColumns) {
                return Column(
                  children: [
                    addButton,
                    const SizedBox(height: 8),
                    removeButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: addButton),
                  const SizedBox(width: 8),
                  Expanded(child: removeButton),
                ],
              );
            },
          ),
          if (busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildRoundAdjustButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 42,
      height: 42,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: color,
        style: IconButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.1),
          disabledForegroundColor: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildInventoryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStockActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _AddMedicineDialog extends StatefulWidget {
  final String? initialName;
  final int initialCount;
  final DateTime? initialExpirationDate;

  const _AddMedicineDialog({
    this.initialName,
    this.initialCount = 0,
    this.initialExpirationDate,
  });

  @override
  State<_AddMedicineDialog> createState() => _AddMedicineDialogState();
}

class _AddMedicineDialogState extends State<_AddMedicineDialog> {
  final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _countController = TextEditingController();

  DateTime? _selectedExpirationDate;
  String? _nameError;
  String? _countError;
  String? _expirationError;

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    _countController.text = widget.initialCount.toString();
    _selectedExpirationDate = widget.initialExpirationDate;
  }

  void _submit() {
    final name = _nameController.text.trim();
    final count = int.tryParse(_countController.text.trim());

    setState(() {
      _nameError = name.isEmpty ? 'Enter medicine name' : null;
      _countError = count == null ? 'Enter count' : null;
      _expirationError = _selectedExpirationDate == null
          ? 'Select expiration date'
          : null;
    });

    if (_nameError != null ||
        _countError != null ||
        _expirationError != null ||
        count == null ||
        _selectedExpirationDate == null) {
      return;
    }

    Navigator.of(context).pop(
      _MedicineFormResult(
        name: name,
        count: count,
        expirationDate: _selectedExpirationDate!,
      ),
    );
  }

  Future<void> _pickExpirationDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _selectedExpirationDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(today.year - 10, today.month, today.day),
      lastDate: DateTime(today.year + 10, today.month, today.day),
      helpText: 'Select expiration date',
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _selectedExpirationDate = DateTime(picked.year, picked.month, picked.day);
      _expirationError = null;
    });
  }

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        widget.initialName == null ? 'Add Medicine' : 'Edit Medicine',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Medicine name',
                prefixIcon: const Icon(Icons.medication_outlined),
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Initial count',
                prefixIcon: const Icon(Icons.inventory_2_outlined),
                errorText: _countError,
              ),
              onChanged: (_) {
                if (_countError != null) {
                  setState(() => _countError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _pickExpirationDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Expiration date',
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  errorText: _expirationError,
                ),
                child: Text(
                  _selectedExpirationDate == null
                      ? 'Select date'
                      : _formatDate(_selectedExpirationDate!),
                  style: TextStyle(
                    color: _selectedExpirationDate == null
                        ? Colors.grey
                        : Colors.black87,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFA726),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  final String itemName;
  final int currentCount;
  final bool isAdding;

  const _StockAdjustmentDialog({
    required this.itemName,
    required this.currentCount,
    required this.isAdding,
  });

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  final TextEditingController _amountController = TextEditingController(
    text: '1',
  );

  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_amountController.text.trim());

    setState(() {
      if (amount == null || amount <= 0) {
        _amountError = 'Enter amount';
      } else if (!widget.isAdding && amount > widget.currentCount) {
        _amountError = 'Amount is more than current stock';
      } else {
        _amountError = null;
      }
    });

    if (_amountError != null || amount == null) {
      return;
    }

    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = widget.isAdding
        ? const Color(0xFF00BFA5)
        : const Color(0xFFE53935);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(widget.isAdding ? 'Add Stock' : 'Remove Stock'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.itemName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D0C57),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current count: ${widget.currentCount}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixIcon: const Icon(Icons.add_box_outlined),
              errorText: _amountError,
            ),
            onChanged: (_) {
              if (_amountError != null) {
                setState(() => _amountError = null);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: actionColor,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.isAdding ? 'Add' : 'Remove'),
        ),
      ],
    );
  }
}

class _MedicineFormResult {
  final String name;
  final int count;
  final DateTime expirationDate;

  const _MedicineFormResult({
    required this.name,
    required this.count,
    required this.expirationDate,
  });
}
