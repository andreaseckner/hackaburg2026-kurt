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

  static List<GtfsConnection> reconstructConnections({
    required String stopTimesCsv,
    required String tripsCsv,
    required String routesCsv,
    required List<GtfsStop> stops,
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

    // Map tripId -> routeId
    final Map<String, String> tripToRoute = {};

    for (var row in tripRows.skip(1)) {
      final tripId = row[tripHeaderIndex['trip_id']!].toString();
      final routeId = row[tripHeaderIndex['route_id']!].toString();
      tripToRoute[tripId] = routeId;
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
      if (seenRoutePatterns.contains(patternKey)) continue;
      seenRoutePatterns.add(patternKey);

      List<LatLng> points = [];
      List<LatLng> midpoints = [];

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

      if (points.isNotEmpty) {
        connections.add(
          GtfsConnection(
            tripId: tripId,
            routeId: routeId,
            lineName: lineName,
            points: points,
            midpoints: midpoints,
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
