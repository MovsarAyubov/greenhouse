import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/topology_models.dart';
import 'topology_uploader.dart';

class TopologyStoreSnapshot {
  const TopologyStoreSnapshot({
    required this.manifest,
    required this.blob,
    required this.blobCrc32,
    required this.manifestError,
    required this.blobError,
    required this.semanticCatalogPath,
    required this.semanticCatalogError,
  });

  final TopologyManifest? manifest;
  final Uint8List? blob;
  final int? blobCrc32;
  final String? manifestError;
  final String? blobError;
  final String? semanticCatalogPath;
  final String? semanticCatalogError;

  bool get hasManifest => manifest != null;
  bool get hasBlob => blob != null;
  bool get hasSemanticCatalog =>
      semanticCatalogPath != null && semanticCatalogError == null;

  static const TopologyStoreSnapshot empty = TopologyStoreSnapshot(
    manifest: null,
    blob: null,
    blobCrc32: null,
    manifestError: null,
    blobError: null,
    semanticCatalogPath: null,
    semanticCatalogError: null,
  );
}

class TopologyStore {
  Future<TopologyStoreSnapshot> load({
    required String manifestPath,
    required String blobPath,
    required String semanticCatalogPath,
  }) async {
    TopologyManifest? manifest;
    Uint8List? blob;
    int? blobCrc32;
    String? manifestError;
    String? blobError;
    String? loadedSemanticCatalogPath;
    String? semanticCatalogError;

    final normalizedManifestPath = _normalizePath(manifestPath);
    if (normalizedManifestPath.isNotEmpty) {
      try {
        final file = File(normalizedManifestPath);
        final raw = await file.readAsString();
        final json = jsonDecode(raw);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('topology manifest root must be an object');
        }
        final manifestMap = Map<String, dynamic>.from(json);
        final resolvedSemanticCatalogPath = _resolveSemanticCatalogPath(
          manifestPath: normalizedManifestPath,
          requestedSemanticCatalogPath: semanticCatalogPath,
        );
        if (resolvedSemanticCatalogPath != null) {
          try {
            final semanticFile = File(resolvedSemanticCatalogPath);
            final semanticRaw = await semanticFile.readAsString();
            final semanticJson = jsonDecode(semanticRaw);
            if (semanticJson is! Map<String, dynamic>) {
              throw const FormatException(
                'semantic catalog root must be an object',
              );
            }
            _mergeSemanticCatalog(
              manifestMap: manifestMap,
              semanticCatalog: Map<String, dynamic>.from(semanticJson),
            );
            loadedSemanticCatalogPath = resolvedSemanticCatalogPath;
          } catch (e) {
            semanticCatalogError = e.toString();
          }
        }
        manifest = TopologyManifest.fromJson(manifestMap);
      } catch (e) {
        manifestError = e.toString();
      }
    }

    final normalizedBlobPath = _normalizePath(blobPath);
    if (normalizedBlobPath.isNotEmpty) {
      try {
        final file = File(normalizedBlobPath);
        final bytes = await file.readAsBytes();
        blob = Uint8List.fromList(bytes);
        blobCrc32 = Crc32.compute(blob);
      } catch (e) {
        blobError = e.toString();
      }
    }

    return TopologyStoreSnapshot(
      manifest: manifest,
      blob: blob,
      blobCrc32: blobCrc32,
      manifestError: manifestError,
      blobError: blobError,
      semanticCatalogPath: loadedSemanticCatalogPath,
      semanticCatalogError: semanticCatalogError,
    );
  }
}

String _normalizePath(String path) {
  var normalized = path.trim();
  if (normalized.length >= 2 &&
      normalized.startsWith('"') &&
      normalized.endsWith('"')) {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}

String? _resolveSemanticCatalogPath({
  required String manifestPath,
  required String requestedSemanticCatalogPath,
}) {
  final normalizedRequested = _normalizePath(requestedSemanticCatalogPath);
  if (normalizedRequested.isNotEmpty) {
    return normalizedRequested;
  }
  final manifestFile = File(manifestPath);
  final directory = manifestFile.parent;
  final name = manifestFile.uri.pathSegments.isEmpty
      ? manifestFile.path
      : manifestFile.uri.pathSegments.last;
  final candidates = <String>[
    if (name.contains('_topology.'))
      '${directory.path}${Platform.pathSeparator}${name.replaceFirst('_topology.', '_semantics.')}',
    '${directory.path}${Platform.pathSeparator}semantics.json',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return null;
}

void _mergeSemanticCatalog({
  required Map<String, dynamic> manifestMap,
  required Map<String, dynamic> semanticCatalog,
}) {
  final pointsList = manifestMap['points'];
  final semanticPoints = semanticCatalog['points'];
  if (pointsList is! List || semanticPoints is! Map) {
    return;
  }

  final pointPatches = <int, Map<String, String>>{};
  for (final entry in semanticPoints.entries) {
    final value = entry.value;
    if (value is! Map) {
      continue;
    }
    final pointJson = Map<String, dynamic>.from(value);
    final pointId = pointJson['point_id'];
    if (pointId is! int) {
      continue;
    }
    final semanticName = _semanticAliasFromCatalogKey(entry.key.toString());
    final label = pointJson['label']?.toString().trim();
    pointPatches[pointId] = <String, String>{
      if (semanticName != null && semanticName.isNotEmpty)
        'semantic_name': semanticName,
      if (label != null && label.isNotEmpty) 'label': label,
    };
  }

  for (var index = 0; index < pointsList.length; index++) {
    final item = pointsList[index];
    if (item is! Map) {
      continue;
    }
    final pointMap = Map<String, dynamic>.from(item);
    final pointId = pointMap['point_id'];
    if (pointId is! int) {
      continue;
    }
    final patch = pointPatches[pointId];
    if (patch == null || patch.isEmpty) {
      continue;
    }
    patch.forEach((key, value) {
      if ((pointMap[key] == null || pointMap[key].toString().trim().isEmpty)) {
        pointMap[key] = value;
      }
    });
    pointsList[index] = pointMap;
  }
}

String? _semanticAliasFromCatalogKey(String key) {
  final normalized = key.trim().toLowerCase();
  if (normalized.isEmpty || !normalized.contains('.')) {
    return null;
  }
  final semantic = normalized.split('.').last;
  switch (semantic) {
    case 'air_temp':
      return 'air_temperature';
    case 'air_hum':
      return 'air_humidity';
    case 'out_temp':
      return 'outside_temperature';
    case 'out_hum':
      return 'outside_humidity';
    case 'wind_dir':
      return 'wind_direction';
    case 'solar_rad':
      return 'solar_radiation';
    case 'baro_press':
      return 'barometric_pressure';
    default:
      return semantic;
  }
}
