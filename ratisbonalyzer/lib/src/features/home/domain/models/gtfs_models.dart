import 'package:latlong2/latlong.dart';

class Stop {
  final String id;
  final String name;
  final LatLng position;

  Stop({
    required this.id,
    required this.name,
    required this.position,
  });
}

class RouteInfo {
  final String id;
  final String shortName;
  final String longName;
  final String? color;

  RouteInfo({
    required this.id,
    required this.shortName,
    required this.longName,
    this.color,
  });
}

class Trip {
  final String id;
  final String routeId;
  final String? shapeId;

  Trip({
    required this.id,
    required this.routeId,
    this.shapeId,
  });
}

class StopTime {
  final String tripId;
  final String stopId;
  final int stopSequence;

  StopTime({
    required this.tripId,
    required this.stopId,
    required this.stopSequence,
  });
}
