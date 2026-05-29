import 'package:csv/csv.dart';
import 'package:rvv_analyzer/gtfs/models/recorded_stop_event.dart';

class RecordedDataParser {
  static List<RecordedStopEvent> parseRecording(String csvContent) {
    // The CSV uses \n as line delimiter and default , as field delimiter
    // Note: csv 8.0.0 uses Csv().decode() instead of CsvToListConverter
    final rows = Csv(
      lineDelimiter: '\n',
      dynamicTyping: false,
    ).decode(csvContent);

    if (rows.isEmpty) return [];

    // Skip header and parse rows
    return rows
        .skip(1)
        .where((row) => row.length >= 21) // Basic validation
        .map((row) {
          try {
            return RecordedStopEvent.fromCsv(row);
          } catch (e) {
            // Log or skip malformed rows
            return null;
          }
        })
        .whereType<RecordedStopEvent>()
        .toList();
  }
}
