import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'theme/app_theme.dart';
import 'services/climate_repository.dart';
import 'services/simulation_data_source.dart';
import 'blocs/climate/climate_bloc.dart';
import 'blocs/climate/climate_event.dart';
import 'blocs/co2/co2_bloc.dart';
import 'blocs/co2/co2_event.dart';
import 'blocs/lighting/lighting_bloc.dart';
import 'blocs/lighting/lighting_event.dart';
import 'screens/main_screen.dart';
import 'services/irrigation_repository.dart';
import 'blocs/irrigation/irrigation_bloc.dart';
import 'blocs/irrigation/irrigation_event.dart';

void main() {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Use SimulationDataSource by default.
  // To use RS-485, replace with: SerialDataSource()
  final climateRepository = ClimateRepository(
    dataSource: SimulationDataSource(),
  );
  final irrigationRepository = IrrigationRepository(
    climateRepository: climateRepository,
  );

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: climateRepository),
        RepositoryProvider.value(value: irrigationRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ClimateBloc>(
            create: (context) =>
                ClimateBloc(repository: context.read<ClimateRepository>())
                  ..add(StartClimateUpdates()),
          ),
          BlocProvider<Co2Bloc>(
            create: (context) =>
                Co2Bloc(repository: climateRepository)..add(LoadCo2Schedules()),
          ),
          BlocProvider(
            create: (context) =>
                LightingBloc(repository: climateRepository)
                  ..add(LoadLightingSchedules()),
          ),
          BlocProvider(
            create: (context) =>
                IrrigationBloc(repository: context.read<IrrigationRepository>())
                  ..add(LoadIrrigationData()),
          ),
        ],
        child: const GreenhouseApp(),
      ),
    ),
  );
}

class GreenhouseApp extends StatelessWidget {
  const GreenhouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Greenhouse SCADA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainScreen(),
    );
  }
}
