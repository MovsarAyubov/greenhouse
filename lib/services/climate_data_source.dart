import '../models/weather_data.dart';

abstract class ClimateDataSource {
  Stream<WeatherData> get dataStream;

  // Control methods
  Future<void> setLight(bool on);
  Future<void> setCo2(bool on);
  Future<void> setIrrigationValve(int valveId, bool on);

  void dispose();
}
