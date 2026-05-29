import 'package:intl/intl.dart';

class RecordedStopEvent {
  final DateTime arrivalTimeActual;
  final DateTime arrivalTimePlanned;
  final DateTime departureTimeActual;
  final DateTime departureTimePlanned;
  final String stopId;
  final String stopName;
  final String lineId;
  final String directionId;
  final String tripId; // Using 'Umlauf' or similar as proxy for tripId
  final bool isArrivalProductive;
  final bool isDepartureProductive;
  final int? arrivalDelaySeconds;
  final int? departureDelaySeconds;

  RecordedStopEvent({
    required this.arrivalTimeActual,
    required this.arrivalTimePlanned,
    required this.departureTimeActual,
    required this.departureTimePlanned,
    required this.stopId,
    required this.stopName,
    required this.lineId,
    required this.directionId,
    required this.tripId,
    required this.isArrivalProductive,
    required this.isDepartureProductive,
    this.arrivalDelaySeconds,
    this.departureDelaySeconds,
  });

  static final _dateFormat = DateFormat('dd.MM.yyyy HH:mm:ss');

  factory RecordedStopEvent.fromCsv(List<dynamic> row) {
    // Mapping based on my analysis of the CSV structure
    DateTime parseDate(String value) => _dateFormat.parse(value.toString());

    int? parseInt(dynamic value) {
      if (value == null || value.toString().isEmpty) return null;
      return int.tryParse(value.toString());
    }

    bool parseBool(dynamic value) {
      return value.toString().toLowerCase() == 'ja';
    }

    return RecordedStopEvent(
      arrivalTimeActual: parseDate(row[0]),
      arrivalTimePlanned: parseDate(row[2]),
      departureTimeActual: parseDate(row[3]),
      departureTimePlanned: parseDate(row[5]),
      isArrivalProductive: parseBool(row[6]),
      isDepartureProductive: parseBool(row[7]),
      stopId: row[13].toString(),
      stopName: row[14].toString(),
      lineId: row[16].toString(),
      directionId: row[18].toString(),
      tripId: row[20].toString(), // Umlauf
      departureDelaySeconds: parseInt(row[21]),
      arrivalDelaySeconds: parseInt(row[22]),
    );
  }
}
