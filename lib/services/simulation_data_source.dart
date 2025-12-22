import 'dart:async';
import 'dart:math';
import '../models/weather_data.dart';
import 'climate_data_source.dart';

class SimulationDataSource implements ClimateDataSource {
  final _controller = StreamController<WeatherData>();
  Timer? _simulationTimer;
  WeatherData _currentData = WeatherData.initial();

  @override
  Stream<WeatherData> get dataStream => _controller.stream;

  SimulationDataSource() {
    _startSimulation();
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final random = Random();

      // Smooth random walk for temperature
      double newTemp = _currentData.temperature + (random.nextDouble() - 0.5);
      newTemp = newTemp.clamp(15.0, 35.0);
      if (_currentData.temperature == 0) newTemp = 22.0;

      // Random wind
      double newWindSpeed = random.nextDouble() * 10;
      double newWindDir = random.nextDouble() * 360;

      // Radiation
      double newRadiation = 500 + (random.nextDouble() * 100);

      // Simulate other values
      double newHumidity = (_currentData.humidity + (random.nextDouble() - 0.5))
          .clamp(30.0, 90.0);
      double newCo2 = (_currentData.co2Level + (random.nextDouble() * 10 - 5))
          .clamp(400.0, 1200.0);
      double newLight =
          (_currentData.lightLevel + (random.nextDouble() * 50 - 25)).clamp(
            0.0,
            2000.0,
          );
      if (newLight == 0 && newRadiation > 0) {
        newLight = 500.0; // Sync roughly with radiation
      }

      _currentData = WeatherData(
        temperature: double.parse(newTemp.toStringAsFixed(1)),
        windSpeed: double.parse(newWindSpeed.toStringAsFixed(1)),
        windDirection: double.parse(newWindDir.toStringAsFixed(0)),
        radiation: double.parse(newRadiation.toStringAsFixed(0)),
        humidity: double.parse(newHumidity.toStringAsFixed(1)),
        co2Level: double.parse(newCo2.toStringAsFixed(0)),
        lightLevel: double.parse(newLight.toStringAsFixed(0)),
      );

      _controller.add(_currentData);
    });
  }

  @override
  Future<void> setLight(bool on) async {
    print('Simulation: Light set to $on');
    // In a real sim, we might update _currentData.lightLevel
  }

  @override
  Future<void> setCo2(bool on) async {
    print('Simulation: CO2 set to $on');
  }

  @override
  Future<void> setIrrigationValve(int valveId, bool on) async {
    print('Simulation: Valve $valveId set to $on');
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _controller.close();
  }
}
