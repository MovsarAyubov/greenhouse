import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:greenhouse/domain/entities/operator_pc/operator_models.dart';

class StorageService {
  Database? _db;

  Future<void> init() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = p.join(
      await databaseFactory.getDatabasesPath(),
      'greenhouse_operator.db',
    );
    _db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE telemetry(
              time_utc TEXT NOT NULL,
              sensor_id INTEGER NOT NULL,
              value REAL NOT NULL,
              quality INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE events(
              time_utc TEXT NOT NULL,
              event_id INTEGER PRIMARY KEY,
              severity INTEGER NOT NULL,
              code INTEGER NOT NULL,
              source INTEGER NOT NULL,
              value REAL NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE setpoint_changes(
              time_utc TEXT NOT NULL,
              old_version INTEGER NOT NULL,
              new_version INTEGER NOT NULL,
              user TEXT,
              summary TEXT
            )
          ''');

          await _createSetpointDraftTable(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createSetpointDraftTable(db);
          }
        },
      ),
    );
  }

  Future<void> _createSetpointDraftTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS setpoint_draft(
        id INTEGER PRIMARY KEY CHECK (id = 1),
        time_utc TEXT NOT NULL,
        version_text TEXT NOT NULL,
        user_text TEXT NOT NULL,
        payload_text TEXT NOT NULL
      )
    ''');
  }

  Future<void> logSnapshot(List<SensorPoint> sensors) async {
    final db = _db;
    if (db == null) {
      return;
    }
    final batch = db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final s in sensors) {
      batch.insert('telemetry', {
        'time_utc': now,
        'sensor_id': s.id,
        'value': s.value,
        'quality': s.quality.index,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> logEvent(EventItem event) async {
    final db = _db;
    if (db == null) {
      return;
    }
    await db.insert('events', {
      'time_utc': event.timestamp.toUtc().toIso8601String(),
      'event_id': event.eventId,
      'severity': event.severity.index,
      'code': event.code,
      'source': event.source,
      'value': event.value,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> logSetpointChange({
    required int oldVersion,
    required int newVersion,
    required String user,
    required String summary,
  }) async {
    final db = _db;
    if (db == null) {
      return;
    }
    await db.insert('setpoint_changes', {
      'time_utc': DateTime.now().toUtc().toIso8601String(),
      'old_version': oldVersion,
      'new_version': newVersion,
      'user': user,
      'summary': summary,
    });
  }

<<<<<<< HEAD:lib/data/services/operator_pc/storage_service.dart
=======
  Future<void> saveSetpointDraft(LocalSetpointDraft draft) async {
    final db = _db;
    if (db == null) {
      return;
    }
    await db.insert('setpoint_draft', {
      'id': 1,
      'time_utc': (draft.savedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'version_text': draft.versionText,
      'user_text': draft.userText,
      'payload_text': draft.payloadText,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LocalSetpointDraft?> loadSetpointDraft() async {
    final db = _db;
    if (db == null) {
      return null;
    }
    final rows = await db.query(
      'setpoint_draft',
      where: 'id = ?',
      whereArgs: const [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final savedAtText = row['time_utc'] as String?;
    return LocalSetpointDraft(
      versionText: (row['version_text'] as String?) ?? '',
      userText: (row['user_text'] as String?) ?? '',
      payloadText: (row['payload_text'] as String?) ?? '',
      savedAt: savedAtText == null ? null : DateTime.tryParse(savedAtText),
    );
  }

>>>>>>> client_transport_topology:lib/operator_pc/services/storage_service.dart
  Future<List<Map<String, Object?>>> telemetryBetween(
    DateTime from,
    DateTime to,
  ) async {
    final db = _db;
    if (db == null) {
      return <Map<String, Object?>>[];
    }
    return db.query(
      'telemetry',
      where: 'time_utc >= ? AND time_utc <= ?',
      whereArgs: [from.toUtc().toIso8601String(), to.toUtc().toIso8601String()],
      orderBy: 'time_utc ASC, sensor_id ASC',
    );
  }

  Future<List<Map<String, Object?>>> eventsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final db = _db;
    if (db == null) {
      return <Map<String, Object?>>[];
    }
    return db.query(
      'events',
      where: 'time_utc >= ? AND time_utc <= ?',
      whereArgs: [from.toUtc().toIso8601String(), to.toUtc().toIso8601String()],
      orderBy: 'event_id ASC',
    );
  }

  Future<String> exportCsv({
    required DateTime from,
    required DateTime to,
    required ({int blockNo, int channelIndex})? Function(int sensorId)
    resolveSensor,
    required String Function(int channelIndex) channelNameByIndex,
    required String Function(int source) decodeSource,
  }) async {
    final telemetry = await telemetryBetween(from, to);
    final events = await eventsBetween(from, to);

    final outDir = Directory(p.join(Directory.current.path, 'exports'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath = p.join(outDir.path, 'report_$stamp.csv');
    final sb = StringBuffer();

    sb.writeln(
      'section,TimeUtc,sensor_id,BlockNo,ChannelName,Value,Quality,event_id,severity,code,source,source_decoded',
    );
    for (final row in telemetry) {
      final sensorId = (row['sensor_id'] as int?) ?? -1;
      final mapped = sensorId >= 0 ? resolveSensor(sensorId) : null;
      final blockNo = mapped?.blockNo ?? -1;
      final channelName = mapped == null
          ? 'UNKNOWN'
          : channelNameByIndex(mapped.channelIndex);
      sb.writeln(
        'telemetry,${row['time_utc']},$sensorId,$blockNo,$channelName,${row['value']},${row['quality']},,,,,',
      );
    }
    for (final row in events) {
      final source = (row['source'] as int?) ?? -1;
      sb.writeln(
        'event,${row['time_utc']},,,,,${row['value']},,${row['event_id']},${row['severity']},${row['code']},$source,${decodeSource(source)}',
      );
    }

    await File(outPath).writeAsString(sb.toString());
    return outPath;
  }

  Future<String> exportXlsx({
    required DateTime from,
    required DateTime to,
    required ({int blockNo, int channelIndex})? Function(int sensorId)
    resolveSensor,
    required String Function(int channelIndex) channelNameByIndex,
    required String Function(int source) decodeSource,
  }) async {
    final telemetry = await telemetryBetween(from, to);
    final events = await eventsBetween(from, to);

    final excel = Excel.createExcel();
    final telemetrySheet = excel['telemetry'];
    final eventSheet = excel['events'];

    telemetrySheet.appendRow([
      TextCellValue('TimeUtc'),
      TextCellValue('SensorId'),
      TextCellValue('BlockNo'),
      TextCellValue('ChannelName'),
      TextCellValue('Value'),
      TextCellValue('Quality'),
    ]);

    for (final row in telemetry) {
      final sensorId = (row['sensor_id'] as int?) ?? -1;
      final mapped = sensorId >= 0 ? resolveSensor(sensorId) : null;
      final blockNo = mapped?.blockNo ?? -1;
      final channelName = mapped == null
          ? 'UNKNOWN'
          : channelNameByIndex(mapped.channelIndex);
      telemetrySheet.appendRow([
        TextCellValue(row['time_utc'].toString()),
        IntCellValue(sensorId),
        IntCellValue(blockNo),
        TextCellValue(channelName),
        DoubleCellValue((row['value'] as num?)?.toDouble() ?? 0),
        IntCellValue((row['quality'] as int?) ?? 0),
      ]);
    }

    eventSheet.appendRow([
      TextCellValue('time_utc'),
      TextCellValue('event_id'),
      TextCellValue('severity'),
      TextCellValue('code'),
      TextCellValue('source'),
      TextCellValue('source_decoded'),
      TextCellValue('value'),
    ]);

    for (final row in events) {
      final source = (row['source'] as int?) ?? -1;
      eventSheet.appendRow([
        TextCellValue(row['time_utc'].toString()),
        IntCellValue((row['event_id'] as int?) ?? 0),
        IntCellValue((row['severity'] as int?) ?? 0),
        IntCellValue((row['code'] as int?) ?? 0),
        IntCellValue(source),
        TextCellValue(decodeSource(source)),
        DoubleCellValue((row['value'] as num?)?.toDouble() ?? 0),
      ]);
    }

    final outDir = Directory(p.join(Directory.current.path, 'exports'));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final outPath = p.join(outDir.path, 'report_$stamp.xlsx');
    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('XLSX encode failed');
    }
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  Future<void> dispose() async {
    await _db?.close();
  }
}
