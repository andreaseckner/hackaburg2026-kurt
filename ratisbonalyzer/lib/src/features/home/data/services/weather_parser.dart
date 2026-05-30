import 'package:csv/csv.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/weather_record.dart';

class WeatherParser {
  static Map<DateTime, WeatherRecord> parseWeather(String csvContent) {
    final data = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(
      data,
      shouldParseNumbers: false,
    );

    if (rows.isEmpty) return {};

    final Map<DateTime, WeatherRecord> weatherMap = {};

    // Skip header and parse rows
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 2) continue; // Basic validation

      try {
        final timeStr = row[0].toString();
        // Parse time: e.g. "2023-10-08 00:00:00"
        final time = DateTime.parse('${timeStr.trim().replaceAll(' ', 'T')}Z');

        double? parseDouble(dynamic value) {
          if (value == null || value.toString().isEmpty) return null;
          return double.tryParse(value.toString());
        }

        int? parseInt(dynamic value) {
          if (value == null || value.toString().isEmpty) return null;
          return int.tryParse(value.toString());
        }

        final record = WeatherRecord(
          time: time,
          temp: parseDouble(row[1]) ?? 0.0,
          dwpt: parseDouble(row[2]),
          rhum: parseDouble(row[3]),
          prcp: parseDouble(row[4]),
          snow: parseDouble(row[5]),
          wdir: parseDouble(row[6]),
          wspd: parseDouble(row[7]),
          wpgt: parseDouble(row[8]),
          pres: parseDouble(row[9]),
          tsun: parseDouble(row[10]),
          coco: parseInt(row[11]),
        );

        // Store with UTC hour truncated key
        final key = DateTime.utc(time.year, time.month, time.day, time.hour);
        weatherMap[key] = record;
      } catch (_) {
        // Skip malformed rows
      }
    }

    return weatherMap;
  }
}
