import 'package:equatable/equatable.dart';
import '../../models/weather_data.dart';

abstract class ClimateState extends Equatable {
  const ClimateState();

  @override
  List<Object> get props => [];
}

class ClimateInitial extends ClimateState {}

class ClimateLoading extends ClimateState {}

class ClimateLoaded extends ClimateState {
  final WeatherData weather;

  const ClimateLoaded(this.weather);

  @override
  List<Object> get props => [weather];
}

class ClimateError extends ClimateState {
  final String message;

  const ClimateError(this.message);

  @override
  List<Object> get props => [message];
}
