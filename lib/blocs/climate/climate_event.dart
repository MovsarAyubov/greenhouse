import 'package:equatable/equatable.dart';
import '../../models/weather_data.dart';

abstract class ClimateEvent extends Equatable {
  const ClimateEvent();

  @override
  List<Object> get props => [];
}

class StartClimateUpdates extends ClimateEvent {}

class ConnectToHardware extends ClimateEvent {
  final String portName;
  const ConnectToHardware(this.portName);
  @override
  List<Object> get props => [portName];
}

class ClimateUpdated extends ClimateEvent {
  final WeatherData weather;

  const ClimateUpdated(this.weather);

  @override
  List<Object> get props => [weather];
}
