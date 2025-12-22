import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/climate_repository.dart';
import '../../services/serial_data_source.dart';
import 'climate_event.dart';
import 'climate_state.dart';

class ClimateBloc extends Bloc<ClimateEvent, ClimateState> {
  final ClimateRepository _repository;
  StreamSubscription? _weatherSubscription;

  ClimateBloc({required ClimateRepository repository})
    : _repository = repository,
      super(ClimateInitial()) {
    on<StartClimateUpdates>(_onStartClimateUpdates);
    on<ClimateUpdated>(_onClimateUpdated);
    on<ConnectToHardware>(_onConnectToHardware);
  }

  void _onStartClimateUpdates(
    StartClimateUpdates event,
    Emitter<ClimateState> emit,
  ) async {
    emit(ClimateLoading());
    await emit.forEach(
      _repository.weatherStream,
      onData: (weather) => ClimateLoaded(weather),
      onError: (error, stackTrace) => ClimateError(error.toString()),
    );
  }

  void _onConnectToHardware(
    ConnectToHardware event,
    Emitter<ClimateState> emit,
  ) {
    _repository.switchDataSource(SerialDataSource(portName: event.portName));
  }

  void _onClimateUpdated(ClimateUpdated event, Emitter<ClimateState> emit) {
    emit(ClimateLoaded(event.weather));
  }

  @override
  Future<void> close() {
    _weatherSubscription?.cancel();
    return super.close();
  }
}
