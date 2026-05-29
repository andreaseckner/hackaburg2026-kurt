import 'dart:ui';

import 'package:latlong2/latlong.dart';

class GtfsConnection {
  final String tripId;
  final String routeId;
  final String lineName;
  final List<LatLng> points;
  final List<LatLng> midpoints; // For labels
  final List<String> stopIds;
  final Color color;

  GtfsConnection({
    required this.tripId,
    required this.routeId,
    required this.lineName,
    required this.points,
    required this.midpoints,
    required this.stopIds,
    required this.color,
  });
}
