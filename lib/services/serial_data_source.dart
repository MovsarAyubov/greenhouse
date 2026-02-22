import 'dart:async';
import '../models/weather_data.dart';
import 'climate_data_source.dart';
import 'modbus_service.dart';

class SerialDataSource implements ClimateDataSource {
  final _controller = StreamController<WeatherData>();
  final ModbusService _modbusService = ModbusService();
  final String portName;

  @override
  Stream<WeatherData> get dataStream => _controller.stream;

  SerialDataSource({required this.portName}) {
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _modbusService.connect(portName);
      print('Connected to Modbus RTU on $portName');

      // Start polling loop
      Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (_controller.isClosed) {
          timer.cancel();
          return;
        }

        // try {
        //   // Read 4 registers starting at address 0
        //   // 0: Temp, 1: Humidity, 2: CO2, 3: Light
        //   final registers = await _modbusService.readHoldingRegisters(0, 3);

        //   if (registers.length >= 3) {
        //     final data = WeatherData(
        //       // temperature: registers[0] / 10.0, // e.g. 255 -> 25.5
        //       lightLevel: 0,
        //       temperature: 0,
        //       // humidity: registers[1] / 1.0,
        //       humidity: 0,
        //       co2Level: 0,
        //       windSpeed: 0, // Not reading wind yet
        //       windDirection: 0,
        //       radiation: 0,
        //     );
        //     _controller.add(data);
        //   }
        // } catch (e) {
        //   print('Polling error: $e');
        // }
      });
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  @override
  Future<void> setLight(bool on) async {
    // Address 100 for Light
    await _modbusService.writeCoil(0, on);
    print('Serial: Light set to $on');
  }

  @override
  Future<void> setCo2(bool on) async {
    // Address 101 for CO2 Valve
    await _modbusService.writeCoil(2, on);
    print('Serial: CO2 set to $on');
  }

  @override
  Future<void> setIrrigationValve(int valveId, bool on) async {
    // Address 200 + valveId for Irrigation Valves
    // Assuming valveId is a small integer (1, 2, 3...)
    // If it's a large hash, we might need a mapping, but for now:
    final address = 200 + (valveId % 100);
    print('Serial: Setting Valve $valveId (Addr $address) to $on');
    await _modbusService.writeCoil(address, on);
  }

  @override
  void dispose() {
    _modbusService.dispose();
    _controller.close();
  }
}
