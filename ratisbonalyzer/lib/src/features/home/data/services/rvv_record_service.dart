import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/rvv_record.dart';

class RvvRecordService {
  /// Loads all CSV files from assets/rec/ and returns a map of filename -> records.
  Future<Map<String, List<RvvRecord>>> loadAllRecFiles() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final recPaths = assetManifest
        .listAssets()
        .where((key) => key.startsWith('assets/rec/') && key.endsWith('.csv'))
        .toList();

    final result = <String, List<RvvRecord>>{};

    for (final path in recPaths) {
      final filename = path.split('/').last;
      final records = await parseFile(path);
      result[filename] = records;
    }

    return result;
  }

  /// Parses a single CSV asset file into a list of RvvRecord.
  Future<List<RvvRecord>> parseFile(String assetPath) async {
    final data = await rootBundle.loadString(assetPath);
    final rows = const CsvToListConverter().convert(
      data,
      shouldParseNumbers: false,
      eol: '\n',
    );

    if (rows.length <= 1) return [];

    // Skip header row
    return rows.skip(1).map((row) => RvvRecord.fromCsvRow(row)).toList();
  }
}
