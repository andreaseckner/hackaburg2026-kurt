import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:ratisbonalyzer/src/core/assets.gen.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/gtfs_models.dart';

class GtfsService {
  Future<List<Stop>> loadStops() async {
    final rawData = await rootBundle.loadString(Assets.gtfs.stops);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(data, shouldParseNumbers: false);
    
    // Find column indices
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idIdx = header.indexOf('stop_id');
    final nameIdx = header.indexOf('stop_name');
    final latIdx = header.indexOf('stop_lat');
    final lonIdx = header.indexOf('stop_lon');

    return rows.skip(1).where((row) => row.length > idIdx && row.length > nameIdx && row.length > latIdx && row.length > lonIdx).map((row) {
      return Stop(
        id: row[idIdx].toString(),
        name: row[nameIdx].toString(),
        position: LatLng(
          double.parse(row[latIdx].toString()),
          double.parse(row[lonIdx].toString()),
        ),
      );
    }).toList();
  }

  Future<List<RouteInfo>> loadRoutes() async {
    final rawData = await rootBundle.loadString(Assets.gtfs.routes);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(data, shouldParseNumbers: false);
    
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idIdx = header.indexOf('route_id');
    final shortNameIdx = header.indexOf('route_short_name');
    final longNameIdx = header.indexOf('route_long_name');
    final colorIdx = header.indexOf('route_color');

    return rows.skip(1).where((row) => row.length > idIdx && row.length > shortNameIdx && row.length > longNameIdx).map((row) {
      return RouteInfo(
        id: row[idIdx].toString(),
        shortName: row[shortNameIdx].toString(),
        longName: row[longNameIdx].toString(),
        color: (colorIdx != -1 && row.length > colorIdx) ? row[colorIdx].toString() : null,
      );
    }).toList();
  }

  Future<List<Trip>> loadTrips() async {
    final rawData = await rootBundle.loadString(Assets.gtfs.trips);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(data, shouldParseNumbers: false);
    
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final idIdx = header.indexOf('trip_id');
    final routeIdIdx = header.indexOf('route_id');
    final shapeIdIdx = header.indexOf('shape_id');

    return rows.skip(1).where((row) => row.length > idIdx && row.length > routeIdIdx).map((row) {
      final shapeId = (shapeIdIdx != -1 && row.length > shapeIdIdx) ? row[shapeIdIdx].toString().trim() : null;
      return Trip(
        id: row[idIdx].toString(),
        routeId: row[routeIdIdx].toString(),
        shapeId: (shapeId != null && shapeId.isNotEmpty) ? shapeId : null,
      );
    }).toList();
  }

  /// Loads shapes.txt and returns a map of shapeId -> list of LatLng points (sorted by sequence).
  Future<Map<String, List<LatLng>>> loadShapes() async {
    final rawData = await rootBundle.loadString(Assets.gtfs.shapes);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(data, shouldParseNumbers: false);

    final header = rows.first.map((e) => e.toString().trim()).toList();
    final shapeIdIdx = header.indexOf('shape_id');
    final latIdx = header.indexOf('shape_pt_lat');
    final lonIdx = header.indexOf('shape_pt_lon');
    final seqIdx = header.indexOf('shape_pt_sequence');

    final result = <String, List<_ShapePoint>>{};

    for (final row in rows.skip(1)) {
      if (row.length <= shapeIdIdx || row.length <= latIdx || row.length <= lonIdx || row.length <= seqIdx) {
        continue;
      }
      final shapeId = row[shapeIdIdx].toString().trim();
      final lat = double.parse(row[latIdx].toString().trim());
      final lon = double.parse(row[lonIdx].toString().trim());
      final seq = int.parse(row[seqIdx].toString().trim());
      result.putIfAbsent(shapeId, () => []).add(_ShapePoint(lat, lon, seq));
    }

    return result.map((key, points) {
      points.sort((a, b) => a.sequence.compareTo(b.sequence));
      return MapEntry(key, points.map((p) => LatLng(p.lat, p.lon)).toList());
    });
  }

  Future<List<StopTime>> loadStopTimes() async {
    final rawData = await rootBundle.loadString(Assets.gtfs.stopTimes);
    final data = rawData.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n').convert(data, shouldParseNumbers: false);
    
    final header = rows.first.map((e) => e.toString().trim()).toList();
    final tripIdIdx = header.indexOf('trip_id');
    final stopIdIdx = header.indexOf('stop_id');
    final sequenceIdx = header.indexOf('stop_sequence');

    return rows.skip(1).where((row) => row.length > tripIdIdx && row.length > stopIdIdx && row.length > sequenceIdx).map((row) {
      return StopTime(
        tripId: row[tripIdIdx].toString(),
        stopId: row[stopIdIdx].toString(),
        stopSequence: int.parse(row[sequenceIdx].toString()),
      );
    }).toList();
  }
}

class _ShapePoint {
  final double lat;
  final double lon;
  final int sequence;
  _ShapePoint(this.lat, this.lon, this.sequence);
}
