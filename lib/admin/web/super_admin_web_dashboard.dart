import 'package:flutter/material.dart';

// Importing your actual screen files
import '../dashboard/admin_home_tab.dart';
import '../inventory/medicine_inventory_screen.dart';
import '../message/admin_messages_tab.dart';
import '../profile/admin_profile_tab.dart';
import '../reports/reports_tab.dart';
import '../residents/admin_residents_list_screen.dart';

class _NavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class SuperAdminWebDashboard extends StatefulWidget {
  const SuperAdminWebDashboard({super.key});

  @override
  State<SuperAdminWebDashboard> createState() => _SuperAdminWebDashboardState();
}

class _SuperAdminWebDashboardState extends State<SuperAdminWebDashboard> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = const [
    _NavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
    ),
    _NavItem(
      label: 'Residents',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _NavItem(
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
    _NavItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart,
    ),
    _NavItem(
      label: 'Messages',
      icon: Icons.message_outlined,
      selectedIcon: Icons.message,
    ),
    _NavItem(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    final pages = [
      AdminHomeTab(
        onNavigateToResidents: () => _onItemTapped(1),
        onNavigateToInventory: () => _onItemTapped(2),
        onNavigateToReports: () => _onItemTapped(3),
        onNavigateToMessages: () => _onItemTapped(4),
        onNavigateToProfile: () => _onItemTapped(5),
      ),
      const AdminResidentsListScreen(),
      const MedicineInventoryScreen(),
      const ReportsTab(),
      const AdminMessagesTab(),
      const AdminProfileTab(),
    ];

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F6F9),
        body: Row(
          children: [
            NavigationRail(
              extended: width >= 1200,
              minExtendedWidth: 240,
              backgroundColor: Colors.white,
              elevation: 2,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              useIndicator: true,
              indicatorColor: const Color(0xFFE8F5E9),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              selectedIconTheme: const IconThemeData(
                color: Colors.teal,
                size: 24,
              ),
              unselectedIconTheme: const IconThemeData(
                color: Colors.grey,
                size: 22,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Color(0xFF4A5568),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              leading: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                    ),
                    if (width >= 1200) ...[
                      const SizedBox(width: 12),
                      const Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MedicareTrack',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D0C57),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Lifehouse Nursing Home',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              destinations: List.generate(_navItems.length, (index) {
                final item = _navItems[index];
                return NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                );
              }),
            ),
            const VerticalDivider(
              thickness: 1,
              width: 1,
              color: Color(0xFFE0E0E0),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: IndexedStack(index: _selectedIndex, children: pages),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D0C57),
        title: Text(_navItems[_selectedIndex].label),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'MedicareTrack',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D0C57),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Admin Dashboard',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _navItems.length,
                  itemBuilder: (context, index) {
                    final item = _navItems[index];
                    final selected = index == _selectedIndex;
                    return ListTile(
                      leading: Icon(
                        selected ? item.selectedIcon : item.icon,
                        color: selected ? Colors.teal : Colors.grey,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: selected
                              ? const Color(0xFF2D0C57)
                              : Colors.grey.shade700,
                        ),
                      ),
                      selected: selected,
                      selectedTileColor: const Color(0xFFE8F5E9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () {
                        _onItemTapped(index);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: IndexedStack(index: _selectedIndex, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 4,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: List.generate(_navItems.length, (index) {
          final item = _navItems[index];
          return NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label,
          );
        }),
      ),
    );
  }
}
