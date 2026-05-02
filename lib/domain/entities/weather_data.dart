class WeatherData {
  final double temperature; // Celsius
  final double windSpeed; // m/s
  final double windDirection; // Degrees (0-360)
  final double radiation; // W/m2
  final double humidity; // %
  final double co2Level; // ppm
  final double lightLevel; // lux

  WeatherData({
    required this.temperature,
    required this.windSpeed,
    required this.windDirection,
    required this.radiation,
    required this.humidity,
    required this.co2Level,
    required this.lightLevel,
  });

  // Factory for empty/initial state
  factory WeatherData.initial() {
    return WeatherData(
      temperature: 0.0,
      windSpeed: 0.0,
      windDirection: 0.0,
      radiation: 0.0,
      humidity: 50.0,
      co2Level: 400.0,
      lightLevel: 0.0,
    );
  }
}
