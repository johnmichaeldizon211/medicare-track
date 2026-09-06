import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/dashboard/admin_home_tab.dart';
import 'package:medicare_tract/admin/inventory/medicine_inventory_screen.dart';
import 'package:medicare_tract/admin/message/admin_messages_tab.dart';
import 'package:medicare_tract/admin/profile/admin_profile_tab.dart';
import 'package:medicare_tract/admin/reports/reports_tab.dart';
import 'package:medicare_tract/admin/residents/admin_residents_list_screen.dart';
import 'package:medicare_tract/admin/web/super_admin_web_dashboard.dart'; // Import web dashboard

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
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
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wider screens get the persistent sidebar; compact screens keep bottom tabs.
        if (constraints.maxWidth > 800) {
          return const SuperAdminWebDashboard();
        }

        // Mobile Layout (Bottom Navigation Bar)
        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: IndexedStack(index: _selectedIndex, children: _pages),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade300, width: 0.5),
              ),
            ),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              selectedItemColor: const Color(0xFFFFA726),
              unselectedItemColor: Colors.grey.shade400,
              showUnselectedLabels: true,
              iconSize: 28,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_filled),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt),
                  label: 'Residents',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2),
                  label: 'Inventory',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bar_chart),
                  label: 'Reports',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble),
                  label: 'Messages',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.account_circle),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
