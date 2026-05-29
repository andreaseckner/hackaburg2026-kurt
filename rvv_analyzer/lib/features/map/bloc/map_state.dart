import 'package:equatable/equatable.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_connection.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_stop.dart';

enum MapStatus { initial, loading, loaded, error }

class MapState extends Equatable {
  final MapStatus status;
  final List<GtfsStop> allStops;
  final List<GtfsConnection> allConnections;
  final Set<String> enabledRouteIds;
  final String? errorMessage;

  const MapState({
    this.status = MapStatus.initial,
    this.allStops = const [],
    this.allConnections = const [],
    this.enabledRouteIds = const {},
    this.errorMessage,
  });

  List<GtfsConnection> get filteredConnections {
    return allConnections
        .where((conn) => enabledRouteIds.contains(conn.routeId))
        .toList();
  }

  MapState copyWith({
    MapStatus? status,
    List<GtfsStop>? allStops,
    List<GtfsConnection>? allConnections,
    Set<String>? enabledRouteIds,
    String? errorMessage,
  }) {
    return MapState(
      status: status ?? this.status,
      allStops: allStops ?? this.allStops,
      allConnections: allConnections ?? this.allConnections,
      enabledRouteIds: enabledRouteIds ?? this.enabledRouteIds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    allStops,
    allConnections,
    enabledRouteIds,
    errorMessage,
  ];
}
