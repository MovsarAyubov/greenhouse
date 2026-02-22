// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:greenhouse/screens/lighting_screen.dart';
import '../theme/app_theme.dart';
import 'external_climate_screen.dart';
import 'internal_climate_screen.dart';
import 'irrigation_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<_NavigationItem> _navigationItems = [
    _NavigationItem(
      icon: FontAwesomeIcons.cloudSun,
      label: 'External Climate',
      screen: const ExternalClimateScreen(),
    ),
    _NavigationItem(
      icon: FontAwesomeIcons.temperatureHalf,
      label: 'Internal Climate',
      screen: const InternalClimateScreen(),
    ),
    _NavigationItem(
      icon: FontAwesomeIcons.lightbulb,
      label: 'Lighting',
      screen: const LightingScreen(),
    ),
    _NavigationItem(
      icon: FontAwesomeIcons.droplet,
      label: 'Irrigation',
      screen: const IrrigationScreen(),
    ),
    _NavigationItem(
      icon: FontAwesomeIcons.fire,
      label: 'Boiler',
      screen: const _PlaceholderScreen(title: 'Boiler Control'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Navigation Rail
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              selectedIconTheme: const IconThemeData(
                color: AppTheme.primaryGreen,
                size: 28,
              ),
              unselectedIconTheme: IconThemeData(
                color: AppTheme.textGrey.withOpacity(0.6),
                size: 24,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: AppTheme.textGrey.withOpacity(0.6),
                fontSize: 12,
              ),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const FaIcon(
                        FontAwesomeIcons.seedling,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SCADA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              destinations: _navigationItems
                  .map(
                    (item) => NavigationRailDestination(
                      icon: FaIcon(item.icon),
                      selectedIcon: FaIcon(item.icon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
          ),

          // Main Content
          Expanded(child: _navigationItems[_selectedIndex].screen),
        ],
      ),
    );
  }
}

class _NavigationItem {
  final IconData icon;
  final String label;
  final Widget screen;

  _NavigationItem({
    required this.icon,
    required this.label,
    required this.screen,
  });
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;

  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Greenhouse Control',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: AppTheme.textGrey),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: const FaIcon(
                          FontAwesomeIcons.wrench,
                          size: 48,
                          color: AppTheme.textGrey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Coming Soon',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This section is under development',
                        style: TextStyle(color: AppTheme.textGrey),
                      ),
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
}
