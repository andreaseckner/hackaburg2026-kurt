import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_connection.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_route.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_stop.dart';

class GtfsParser {
  static List<GtfsStop> parseStops(String csvContent) {
    final rows = Csv(lineDelimiter: '\n').decode(csvContent);
    if (rows.isEmpty) return [];

    final header = rows.first.map((e) => e.toString()).toList();
    final Map<String, int> headerIndex = {
      for (var i = 0; i < header.length; i++) header[i]: i,
    };

    return rows
        .skip(1)
        .map((row) => GtfsStop.fromCsv(row, headerIndex))
        .toList();
  }

  /// Parse shapes.txt and return {shapeId: [LatLng, ...]} ordered by sequence.
  static Map<String, List<LatLng>> parseShapes(String csvContent) {
    final rows = Csv(lineDelimiter: '\n').decode(csvContent);
    if (rows.isEmpty) return {};

    final header = rows.first.map((e) => e.toString()).toList();
    final Map<String, int> headerIndex = {
      for (var i = 0; i < header.length; i++) header[i]: i,
    };

    final Map<String, List<_ShapePointRaw>> raw = {};
    for (var row in rows.skip(1)) {
      if (row.length < 4) continue;
      final shapeId = row[headerIndex['shape_id']!].toString();
      final lat = double.parse(row[headerIndex['shape_pt_lat']!].toString());
      final lon = double.parse(row[headerIndex['shape_pt_lon']!].toString());
      final seq = int.parse(row[headerIndex['shape_pt_sequence']!].toString());
      raw.putIfAbsent(shapeId, () => []).add(_ShapePointRaw(lat, lon, seq));
    }

    final Map<String, List<LatLng>> shapes = {};
    for (var entry in raw.entries) {
      entry.value.sort((a, b) => a.sequence.compareTo(b.sequence));
      shapes[entry.key] =
          entry.value.map((p) => LatLng(p.lat, p.lon)).toList();
    }
    return shapes;
  }

  static List<GtfsConnection> reconstructConnections({
    required String stopTimesCsv,
    required String tripsCsv,
    required String routesCsv,
    required List<GtfsStop> stops,
    Map<String, List<LatLng>>? shapes,
  }) {
    final stopMap = {for (var stop in stops) stop.id: stop.location};

    // Parse Routes
    final routeRows = Csv(lineDelimiter: '\n').decode(routesCsv);
    if (routeRows.isEmpty) return [];
    final routeHeader = routeRows.first.map((e) => e.toString()).toList();
    final routeHeaderIndex = {
      for (var i = 0; i < routeHeader.length; i++) routeHeader[i]: i,
    };
    final Map<String, GtfsRoute> routeMap = {};
    for (var row in routeRows.skip(1)) {
      final route = GtfsRoute.fromCsv(row, routeHeaderIndex);
      routeMap[route.id] = route;
    }

    // Parse Trips
    final tripRows = Csv(lineDelimiter: '\n').decode(tripsCsv);
    if (tripRows.isEmpty) return [];
    final tripHeader = tripRows.first.map((e) => e.toString()).toList();
    final tripHeaderIndex = {
      for (var i = 0; i < tripHeader.length; i++) tripHeader[i]: i,
    };

    // Map tripId -> routeId and tripId -> shapeId
    final Map<String, String> tripToRoute = {};
    final Map<String, String> tripToShape = {};
    final shapeIdIdx = tripHeaderIndex['shape_id'];

    for (var row in tripRows.skip(1)) {
      final tripId = row[tripHeaderIndex['trip_id']!].toString();
      final routeId = row[tripHeaderIndex['route_id']!].toString();
      tripToRoute[tripId] = routeId;
      if (shapeIdIdx != null) {
        final shapeId = row[shapeIdIdx].toString().trim();
        if (shapeId.isNotEmpty) {
          tripToShape[tripId] = shapeId;
        }
      }
    }

    // Parse Stop Times
    final stopTimeRows = Csv(lineDelimiter: '\n').decode(stopTimesCsv);
    if (stopTimeRows.isEmpty) return [];
    final stHeader = stopTimeRows.first.map((e) => e.toString()).toList();
    final stHeaderIndex = {
      for (var i = 0; i < stHeader.length; i++) stHeader[i]: i,
    };

    final Map<String, List<_StopSequenceItem>> tripSequences = {};
    for (var row in stopTimeRows.skip(1)) {
      final tripId = row[stHeaderIndex['trip_id']!].toString();
      final stopId = row[stHeaderIndex['stop_id']!].toString();
      final sequence = int.parse(
        row[stHeaderIndex['stop_sequence']!].toString(),
      );
      tripSequences
          .putIfAbsent(tripId, () => [])
          .add(_StopSequenceItem(stopId, sequence));
    }

    for (var sequenceList in tripSequences.values) {
      sequenceList.sort((a, b) => a.sequence.compareTo(b.sequence));
    }

    final List<GtfsConnection> connections = [];
    final Set<String> seenRoutePatterns = {};
    final Map<String, String> patternToShapeId = {};

    for (var tripId in tripSequences.keys) {
      final routeId = tripToRoute[tripId] ?? 'unknown';
      final route = routeMap[routeId];
      final lineName = route != null
          ? (route.shortName.isNotEmpty ? route.shortName : route.longName)
          : 'Unknown Line';
      final color = route?.color ?? Colors.blue;

      final sequence = tripSequences[tripId]!;

      // We use a combination of stop IDs to identify unique route patterns
      final patternKey = '$routeId-${sequence.map((s) => s.stopId).join('-')}';

      // Remember shape for this pattern
      if (!patternToShapeId.containsKey(patternKey) &&
          tripToShape.containsKey(tripId)) {
        patternToShapeId[patternKey] = tripToShape[tripId]!;
      }

      if (seenRoutePatterns.contains(patternKey)) continue;
      seenRoutePatterns.add(patternKey);

      List<LatLng> points = [];
      List<LatLng> midpoints = [];

      // Try to use shape geometry
      final shapeId = patternToShapeId[patternKey];
      final shapePoints = (shapeId != null && shapes != null)
          ? shapes[shapeId]
          : null;

      if (shapePoints != null && shapePoints.isNotEmpty) {
        // Use shape points directly as the polyline
        points = List<LatLng>.from(shapePoints);
        // Compute midpoints per stop segment for label placement
        for (var i = 0; i < sequence.length - 1; i++) {
          final startLoc = stopMap[sequence[i].stopId];
          final endLoc = stopMap[sequence[i + 1].stopId];
          if (startLoc != null && endLoc != null) {
            midpoints.add(
              LatLng(
                (startLoc.latitude + endLoc.latitude) / 2,
                (startLoc.longitude + endLoc.longitude) / 2,
              ),
            );
          }
        }
      } else {
        // Fallback to stop-to-stop straight lines
        for (var i = 0; i < sequence.length - 1; i++) {
          final startLoc = stopMap[sequence[i].stopId];
          final endLoc = stopMap[sequence[i + 1].stopId];
          if (startLoc != null && endLoc != null) {
            points.addAll([startLoc, endLoc]);
            midpoints.add(
              LatLng(
                (startLoc.latitude + endLoc.latitude) / 2,
                (startLoc.longitude + endLoc.longitude) / 2,
              ),
            );
          }
        }
      }

      if (points.isNotEmpty) {
        final List<String> currentStopIds = sequence.map((s) => s.stopId).toList();
        connections.add(
          GtfsConnection(
            tripId: tripId,
            routeId: routeId,
            lineName: lineName,
            points: points,
            midpoints: midpoints,
            stopIds: currentStopIds,
            color: color,
          ),
        );
      }
    }

    return connections;
  }
}

class _StopSequenceItem {
  final String stopId;
  final int sequence;

  _StopSequenceItem(this.stopId, this.sequence);
}

class _ShapePointRaw {
  final double lat;
  final double lon;
  final int sequence;

  _ShapePointRaw(this.lat, this.lon, this.sequence);
}
