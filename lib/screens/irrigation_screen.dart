import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/irrigation/irrigation_bloc.dart';
import '../blocs/irrigation/irrigation_event.dart';
import '../blocs/irrigation/irrigation_state.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_card.dart';

class IrrigationScreen extends StatefulWidget {
  const IrrigationScreen({super.key});

  @override
  State<IrrigationScreen> createState() => _IrrigationScreenState();
}

class _IrrigationScreenState extends State<IrrigationScreen> {
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
                        'Irrigation System',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDark,
                            ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      context.read<IrrigationBloc>().add(EmergencyStopAll());
                    },
                    icon: const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.red,
                      size: 32,
                    ),
                    tooltip: 'Emergency Stop All',
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Content
              Expanded(
                child: BlocBuilder<IrrigationBloc, IrrigationState>(
                  builder: (context, state) {
                    if (state is IrrigationLoading ||
                        state is IrrigationInitial) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is IrrigationLoaded) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          // Responsive layout: Row on wide screens, Column on narrow
                          if (constraints.maxWidth > 900) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: MachineCard(
                                    machine: state.machines[0],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: MachineCard(
                                    machine: state.machines[1],
                                  ),
                                ),
                              ],
                            );
                          } else {
                            return SingleChildScrollView(
                              child: Column(
                                children: [
                                  MachineCard(machine: state.machines[0]),
                                  const SizedBox(height: 24),
                                  MachineCard(machine: state.machines[1]),
                                ],
                              ),
                            );
                          }
                        },
                      );
                    } else if (state is IrrigationError) {
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
