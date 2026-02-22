// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../blocs/climate/climate_bloc.dart';
import '../blocs/climate/climate_state.dart';
import '../blocs/climate/climate_event.dart';
import '../widgets/sensor_card.dart';
import '../widgets/connection_settings_dialog.dart';
import '../theme/app_theme.dart';

class ExternalClimateScreen extends StatelessWidget {
  const ExternalClimateScreen({super.key});

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Greenhouse Control',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: AppTheme.textGrey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'External Climate',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) =>
                              const ConnectionSettingsDialog(),
                        ).then((portName) {
                          if (portName != null) {
                            context.read<ClimateBloc>().add(
                              ConnectToHardware(portName),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Connecting to $portName...'),
                              ),
                            );
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Dashboard Grid
              Expanded(
                child: BlocBuilder<ClimateBloc, ClimateState>(
                  builder: (context, state) {
                    if (state is ClimateLoading || state is ClimateInitial) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is ClimateLoaded) {
                      final data = state.weather;
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          // Responsive grid count
                          int crossAxisCount = constraints.maxWidth > 900
                              ? 4
                              : (constraints.maxWidth > 600 ? 2 : 1);

                          return GridView.count(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                            childAspectRatio: 1.3,
                            children: [
                              SensorCard(
                                title: 'Temperature',
                                value: data.temperature.toString(),
                                unit: '°C',
                                icon: FontAwesomeIcons.temperatureHalf,
                                iconColor: Colors.orange,
                              ),
                              SensorCard(
                                title: 'Wind Speed',
                                value: data.windSpeed.toString(),
                                unit: 'm/s',
                                icon: FontAwesomeIcons.wind,
                                iconColor: Colors.blue,
                              ),
                              SensorCard(
                                title: 'Wind Direction',
                                value: data.windDirection.toString(),
                                unit: '°',
                                icon: FontAwesomeIcons.compass,
                                iconColor: Colors.purple,
                              ),
                              SensorCard(
                                title: 'Solar Radiation',
                                value: data.radiation.toString(),
                                unit: 'W/m²',
                                icon: FontAwesomeIcons.sun,
                                iconColor: Colors.amber,
                              ),
                            ],
                          );
                        },
                      );
                    } else if (state is ClimateError) {
                      return Center(child: Text('Error: ${state.message}'));
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
