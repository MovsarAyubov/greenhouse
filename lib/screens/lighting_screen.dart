import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/lighting_control_card.dart';

class LightingScreen extends StatelessWidget {
  const LightingScreen({super.key});

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
              // Header
              Column(
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
                    'Освещение',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(children: [const LightingControlCard()]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
