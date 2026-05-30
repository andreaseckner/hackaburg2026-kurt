import 'dart:isolate';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/rvv_record.dart';

class RvvRecordService {
  /// Scans the AssetManifest and returns a list of CSV filenames in assets/rec/
  Future<List<String>> listAllRecFiles() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final recPaths = assetManifest
        .listAssets()
        .where((key) => key.startsWith('assets/rec/') && key.endsWith('.csv'))
        .toList();

    // Extract filenames and sort them
    final filenames = recPaths.map((path) => path.split('/').last).toList();
    filenames.sort();
    return filenames;
  }

  /// Checks if a file is already cached in Hive
  Future<bool> isFileCached(String filename) async {
    final metaBox = await Hive.openBox('rvv_records_meta');
    return metaBox.get('$filename:cached', defaultValue: false) as bool;
  }

  /// Returns the unique operation days for a given file from Hive
  Future<List<DateTime>> getDaysForFile(String filename) async {
    final metaBox = await Hive.openBox('rvv_records_meta');
    final dayStrings = metaBox.get('$filename:days') as List<dynamic>?;
    if (dayStrings == null) return [];

    final days = dayStrings.map((s) => DateTime.parse(s.toString())).toList();
    days.sort();
    return days;
  }

  /// Loads records for a specific file and day from the Hive lazy box
  Future<List<RvvRecord>> getRecordsForDay(String filename, DateTime day) async {
    final dataBox = await Hive.openLazyBox('rvv_records_data');
    final key = '$filename:${day.toIso8601String()}';
    final list = await dataBox.get(key);
    if (list == null) return [];
    return List<RvvRecord>.from(list);
  }

  /// Loads, parses, and caches the CSV file in a background Isolate
  Future<void> cacheFile(String filename, String assetPath) async {
    final metaBox = await Hive.openBox('rvv_records_meta');
    final isCached = metaBox.get('$filename:cached', defaultValue: false) as bool;
    if (isCached) return;

    // Read the CSV data from assets
    final rawData = await rootBundle.loadString(assetPath);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Parse and group (use background Isolate if not on Web)
    final Map<String, List<RvvRecord>> grouped;
    if (kIsWeb) {
      grouped = _parseCsvAndGroup(data);
    } else {
      grouped = await Isolate.run(() => _parseCsvAndGroup(data));
    }

    // Save to Hive LazyBox
    final dataBox = await Hive.openLazyBox('rvv_records_data');

    for (final entry in grouped.entries) {
      final key = '$filename:${entry.key}';
      await dataBox.put(key, entry.value);
    }

    // Save metadata
    final dayStrings = grouped.keys.toList()..sort();
    await metaBox.put('$filename:days', dayStrings);
    await metaBox.put('$filename:cached', true);
  }
}

/// Helper function that runs in the background Isolate to parse and group CSV data.
Map<String, List<RvvRecord>> _parseCsvAndGroup(String csvContent) {
  final rows = const CsvToListConverter(eol: '\n').convert(
    csvContent,
    shouldParseNumbers: false,
  );

  if (rows.length <= 1) return {};

  final header = rows[0];
  final isLongFormat = header.length < 25;

  final records = <RvvRecord>[];

  if (isLongFormat) {
    final dataRows = rows
        .skip(1)
        .where((row) => row.isNotEmpty && row[0].toString().trim().isNotEmpty)
        .toList();
    for (int i = 0; i < dataRows.length; i += 4) {
      if (i + 4 > dataRows.length) break;
      final chunk = dataRows.sublist(i, i + 4);
      try {
        records.add(RvvRecord.fromCsvLongRows(chunk));
      } catch (e) {
        // Skip malformed row
      }
    }
  } else {
    for (final row in rows.skip(1)) {
      if (row.isEmpty || row[0].toString().trim().isEmpty) continue;
      try {
        records.add(RvvRecord.fromCsvRow(row));
      } catch (e) {
        // Skip malformed row
      }
    }
  }

  // Group by operation day string
  final grouped = <String, List<RvvRecord>>{};
  for (final rec in records) {
    final dayKey = rec.operationDay.toIso8601String();
    grouped.putIfAbsent(dayKey, () => []).add(rec);
  }
  return grouped;
}
