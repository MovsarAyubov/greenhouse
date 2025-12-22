import 'dart:async'; // Added for StreamController and StreamSubscription
import 'climate_data_source.dart';
import '../models/weather_data.dart';

class ClimateRepository {
  ClimateDataSource _dataSource;
  final _streamController = StreamController<WeatherData>.broadcast();
  StreamSubscription? _subscription;

  Stream<WeatherData> get weatherStream => _streamController.stream;

  ClimateRepository({required ClimateDataSource dataSource})
    : _dataSource = dataSource {
    _subscribeToSource();
  }

  void switchDataSource(ClimateDataSource newSource) {
    _subscription?.cancel();
    _dataSource.dispose();
    _dataSource = newSource;
    _subscribeToSource();
  }

  void _subscribeToSource() {
    _subscription = _dataSource.dataStream.listen((data) {
      _streamController.add(data);
    });
  }

  Future<void> setLight(bool on) => _dataSource.setLight(on);
  Future<void> setCo2(bool on) => _dataSource.setCo2(on);
  Future<void> setIrrigationValve(int valveId, bool on) =>
      _dataSource.setIrrigationValve(valveId, on);

  void dispose() {
    _subscription?.cancel();
    _streamController.close();
    _dataSource.dispose();
  }
}
