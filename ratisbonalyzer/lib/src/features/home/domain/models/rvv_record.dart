import 'package:intl/intl.dart';

class RvvRecord {
  final DateTime arrivalDoor;
  final DateTime arrivalHalt;
  final DateTime arrivalPlan;
  final DateTime departureDoor;
  final DateTime departureHalt;
  final DateTime departurePlan;
  final bool arrivalProductive;
  final bool departureProductive;
  final DateTime operationDay;
  final String tripStartCode;
  final String tripStartName;
  final String tripEndCode;
  final String tripEndName;
  final String stopCode;
  final String stopName;
  final String haltPoint;
  final String line;
  final int direction;
  final String branch;
  final String rotation;
  final int? scheduleDeviationDeparture;
  final int? scheduleDeviationArrival;
  final int cumulativeDistance;
  final int cumulativeTravelTime;

  RvvRecord({
    required this.arrivalDoor,
    required this.arrivalHalt,
    required this.arrivalPlan,
    required this.departureDoor,
    required this.departureHalt,
    required this.departurePlan,
    required this.arrivalProductive,
    required this.departureProductive,
    required this.operationDay,
    required this.tripStartCode,
    required this.tripStartName,
    required this.tripEndCode,
    required this.tripEndName,
    required this.stopCode,
    required this.stopName,
    required this.haltPoint,
    required this.line,
    required this.direction,
    required this.branch,
    required this.rotation,
    this.scheduleDeviationDeparture,
    this.scheduleDeviationArrival,
    required this.cumulativeDistance,
    required this.cumulativeTravelTime,
  });

  static final _dateTimeFmt = DateFormat('dd.MM.yyyy HH:mm:ss');
  static final _dateFmt = DateFormat('dd.MM.yyyy');

  static DateTime _parseDateTime(String s) => _dateTimeFmt.parse(s.trim());
  static DateTime _parseDate(String s) => _dateFmt.parse(s.trim());
  static bool _parseBool(String s) => s.trim().toLowerCase() == 'ja';
  static int? _parseOptionalInt(String s) {
    final trimmed = s.trim().replaceAll('.', '');
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  static int _parseGermanInt(String s) {
    // German thousands separator: "3.912" means 3912
    final trimmed = s.trim().replaceAll('.', '');
    if (trimmed.isEmpty) return 0;
    return int.parse(trimmed);
  }

  factory RvvRecord.fromCsvRow(List row) {
    final r = row.map((e) => e.toString()).toList();
    return RvvRecord(
      arrivalDoor: _parseDateTime(r[0]),
      arrivalHalt: _parseDateTime(r[1]),
      arrivalPlan: _parseDateTime(r[2]),
      departureDoor: _parseDateTime(r[3]),
      departureHalt: _parseDateTime(r[4]),
      departurePlan: _parseDateTime(r[5]),
      arrivalProductive: _parseBool(r[6]),
      departureProductive: _parseBool(r[7]),
      operationDay: _parseDate(r[8]),
      tripStartCode: r[9].trim(),
      tripStartName: r[10].trim(),
      tripEndCode: r[11].trim(),
      tripEndName: r[12].trim(),
      stopCode: r[13].trim(),
      stopName: r[14].trim(),
      haltPoint: r[15].trim(),
      line: r[16].trim(),
      // index 17 ignored
      direction: int.parse(r[18].trim()),
      branch: r[19].trim(),
      rotation: r[20].trim(),
      scheduleDeviationDeparture: _parseOptionalInt(r[21]),
      scheduleDeviationArrival: _parseOptionalInt(r[22]),
      cumulativeDistance: _parseGermanInt(r[23]),
      cumulativeTravelTime: _parseGermanInt(r[24]),
    );
  }
}
