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

  factory RvvRecord.fromCsvLongRows(List<List<dynamic>> chunk) {
    final firstRow = chunk[0].map((e) => e.toString()).toList();
    final len = firstRow.length;

    // Detect if "Haltestelle" columns are missing (length 21 vs 23)
    final bool hasHaltestelleColumns = len >= 23;

    final String rawHaltPoint = hasHaltestelleColumns ? firstRow[15] : firstRow[13];
    final String line = hasHaltestelleColumns ? firstRow[16] : firstRow[14];
    final int direction = int.parse(hasHaltestelleColumns ? firstRow[18].trim() : firstRow[16].trim());
    final String branch = hasHaltestelleColumns ? firstRow[19].trim() : firstRow[17].trim();
    final String rotation = hasHaltestelleColumns ? firstRow[20].trim() : firstRow[18].trim();

    // Metric is always the last two columns
    final int metricNameIdx = len - 2;
    final int metricValIdx = len - 1;

    String? deviationDepartureStr;
    String? deviationArrivalStr;
    String? distStr;
    String? travelTimeStr;

    for (final row in chunk) {
      final metricName = row[metricNameIdx].toString().trim();
      final metricVal = row[metricValIdx].toString();
      if (metricName == 'Fahrplan-Abw. Abfahrt (Tür) AVG  {s}') {
        deviationDepartureStr = metricVal;
      } else if (metricName == 'Fahrplan-Abw. Ankunft (Tür) AVG {s}') {
        deviationArrivalStr = metricVal;
      } else if (metricName == 'CUMSUM(Distanz PLAN) {m}') {
        distStr = metricVal;
      } else if (metricName == 'CUMSUM(Fahrzeit IST) {s}') {
        travelTimeStr = metricVal;
      }
    }

    // Resolve stopCode and stopName
    String stopCode;
    String stopName;

    if (hasHaltestelleColumns) {
      stopCode = firstRow[13].trim();
      stopName = firstRow[14].trim();
    } else {
      // Extract stopCode from haltPoint (e.g. "KILL (99)" -> "KILL")
      final hp = rawHaltPoint.trim();
      final parenIdx = hp.indexOf('(');
      stopCode = parenIdx != -1 ? hp.substring(0, parenIdx).trim() : hp;

      // Fallback/Inferred stopName:
      // Try to find the name from the Fahrtbeginn or Fahrtende in the firstRow
      final startCode = firstRow[9].trim();
      final startName = firstRow[10].trim();
      final endCode = firstRow[11].trim();
      final endName = firstRow[12].trim();

      if (stopCode == startCode) {
        stopName = startName;
      } else if (stopCode == endCode) {
        stopName = endName;
      } else {
        stopName = _mapStopCodeToName(stopCode);
      }
    }

    return RvvRecord(
      arrivalDoor: _parseDateTime(firstRow[0]),
      arrivalHalt: _parseDateTime(firstRow[1]),
      arrivalPlan: _parseDateTime(firstRow[2]),
      departureDoor: _parseDateTime(firstRow[3]),
      departureHalt: _parseDateTime(firstRow[4]),
      departurePlan: _parseDateTime(firstRow[5]),
      arrivalProductive: _parseBool(firstRow[6]),
      departureProductive: _parseBool(firstRow[7]),
      operationDay: _parseDate(firstRow[8]),
      tripStartCode: firstRow[9].trim(),
      tripStartName: firstRow[10].trim(),
      tripEndCode: firstRow[11].trim(),
      tripEndName: firstRow[12].trim(),
      stopCode: stopCode,
      stopName: stopName,
      haltPoint: rawHaltPoint.trim(),
      line: line,
      direction: direction,
      branch: branch,
      rotation: rotation,
      scheduleDeviationDeparture: deviationDepartureStr != null ? _parseOptionalInt(deviationDepartureStr) : null,
      scheduleDeviationArrival: deviationArrivalStr != null ? _parseOptionalInt(deviationArrivalStr) : null,
      cumulativeDistance: distStr != null ? _parseGermanInt(distStr) : 0,
      cumulativeTravelTime: travelTimeStr != null ? _parseGermanInt(travelTimeStr) : 0,
    );
  }

  static String _mapStopCodeToName(String code) {
    switch (code.toUpperCase()) {
      case 'KILL': return 'Killermannstraße';
      case 'DEIN': return 'Deiningerstraße';
      case 'ANNA': return 'Annahofstraße';
      case 'KLOS': return 'An den Klostergründen';
      case 'PRUE': return 'Prüfening';
      case 'RENW': return 'Rennweg';
      case 'RENP': return 'Rennplatz';
      case 'LILI': return 'Lilienthalstraße';
      case 'BURG': return 'Michael-Burgau-Straße';
      case 'MARG': return 'Margaretenau/KH Barmh. Brüder';
      case 'LESS': return 'Lessingstraße';
      case 'GOET': return 'Goethestraße';
      case 'TAXI': return 'Taxisstraße';
      case 'APLZ': return 'Arnulfsplatz';
      case 'KEPL': return 'Keplerstraße';
      case 'FISH': return 'Fischmarkt';
      case 'THUN': return 'Thundorferstraße';
      case 'DPLZ': return 'Dachauplatz';
      case 'SPLZ': return 'Stobäusplatz';
      case 'HBF': return 'Hauptbahnhof';
      case 'POMM': return 'Pommernstraße';
      case 'MECK': return 'Mecklenburger Straße';
      case 'BERL': return 'Berliner Straße';
      case 'OSTP': return 'Ostpreußenstraße';
      case 'AUSS': return 'Aussiger Straße';
      case 'MEME': return 'Memeler Straße';
      case 'SAND': return 'Sandgasse';
      case 'SUDE': return 'Sudetendeutsche Straße';
      case 'NORD': return 'Nordgaustraße';
      case 'DONA': return 'Donaustaufer Straße';
      case 'WEC': return 'Weichs/DEZ';
      case 'WEIS': return 'Weißenburgstraße';
      case 'ARGO': return 'Argonnenstraße';
      default: return code;
    }
  }
}
