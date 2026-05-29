import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_connection.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_stop.dart';
import 'package:rvv_analyzer/gtfs/models/recorded_stop_event.dart';

enum MapStatus { initial, loading, loaded, error }

class MapState extends Equatable {
  final MapStatus status;
  final List<GtfsStop> allStops;
  final List<GtfsConnection> allConnections;
  final Set<String> enabledRouteIds;
  final String? errorMessage;

  // Recording data
  final List<RecordedStopEvent> recordedEvents;
  final Map<String, List<RecordedStopEvent>> currentDayEvents;
  final Map<String, GtfsStop> stopNameLookup;
  final Set<DateTime> availableDays;
  final DateTime? selectedDay;
  final DateTime? currentPlaybackTime;
  final bool isPlaying;
  final double playbackSpeed;

  const MapState({
    this.status = MapStatus.initial,
    this.allStops = const [],
    this.allConnections = const [],
    this.enabledRouteIds = const {},
    this.errorMessage,
    this.recordedEvents = const [],
    this.currentDayEvents = const {},
    this.stopNameLookup = const {},
    this.availableDays = const {},
    this.selectedDay,
    this.currentPlaybackTime,
    this.isPlaying = false,
    this.playbackSpeed = 60.0, // Default 1 min/s
  });

  List<GtfsConnection> get filteredConnections {
    return allConnections
        .where((conn) => enabledRouteIds.contains(conn.routeId))
        .toList();
  }

  List<ActiveVehicle> get activeVehicles {
    if (currentPlaybackTime == null) return [];
    final active = <ActiveVehicle>[];

    for (var tripId in currentDayEvents.keys) {
      final events = currentDayEvents[tripId]!;
      for (var i = 0; i < events.length; i++) {
        final current = events[i];

        // Case 1: At a stop
        if ((currentPlaybackTime!.isAfter(current.arrivalTimeActual) ||
                currentPlaybackTime!.isAtSameMomentAs(current.arrivalTimeActual)) &&
            currentPlaybackTime!.isBefore(current.departureTimeActual)) {
          if (current.isArrivalProductive || current.isDepartureProductive) {
            final stop = _findStop(current);
            if (stop != null) {
              active.add(
                ActiveVehicle(
                  tripId: tripId,
                  location: stop.location,
                  delaySeconds: current.arrivalDelaySeconds ?? 0,
                  lineId: current.lineId,
                ),
              );
            }
          }
          break;
        }

        // Case 2: Between stops
        if (i < events.length - 1) {
          final next = events[i + 1];
          if ((currentPlaybackTime!.isAfter(current.departureTimeActual) ||
                  currentPlaybackTime!.isAtSameMomentAs(current.departureTimeActual)) &&
              (currentPlaybackTime!.isBefore(next.arrivalTimeActual) ||
                  currentPlaybackTime!.isAtSameMomentAs(next.arrivalTimeActual))) {
            if (current.isDepartureProductive || next.isArrivalProductive) {
              final startStop = _findStop(current);
              final endStop = _findStop(next);

              if (startStop != null && endStop != null) {
                final totalDuration = next.arrivalTimeActual
                    .difference(current.departureTimeActual)
                    .inMilliseconds;
                final elapsed = currentPlaybackTime!
                    .difference(current.departureTimeActual)
                    .inMilliseconds;
                final fraction = totalDuration > 0
                    ? (elapsed / totalDuration).clamp(0.0, 1.0)
                    : 1.0;

                final location = _interpolateAlongRoute(
                  current.lineId,
                  startStop.id,
                  endStop.id,
                  fraction,
                );

                active.add(
                  ActiveVehicle(
                    tripId: tripId,
                    location: location ??
                        LatLng(
                          startStop.location.latitude +
                              (endStop.location.latitude -
                                      startStop.location.latitude) *
                                  fraction,
                          startStop.location.longitude +
                              (endStop.location.longitude -
                                      startStop.location.longitude) *
                                  fraction,
                        ),
                    delaySeconds: current.departureDelaySeconds ?? 0,
                    lineId: current.lineId,
                  ),
                );
              }
            }
            break;
          }
        }
      }
    }
    return active;
  }

  String _normalizeStopName(String name) {
    return name.split('(').first.trim().toLowerCase();
  }

  GtfsStop? _findStop(RecordedStopEvent event) {
    try {
      return allStops.firstWhere((s) => s.id == event.stopId);
    } catch (_) {}
    final cleanName = _normalizeStopName(event.stopName);
    return stopNameLookup[cleanName];
  }

  LatLng? _interpolateAlongRoute(
    String lineId,
    String startStopId,
    String endStopId,
    double fraction,
  ) {
    GtfsConnection? bestConn;
    int startIndex = -1;
    int endIndex = -1;

    for (var conn in allConnections) {
      if (conn.lineName == lineId || conn.routeId == lineId) {
        startIndex = conn.stopIds.indexOf(startStopId);
        endIndex = conn.stopIds.indexOf(endStopId);
        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          bestConn = conn;
          break;
        }
      }
    }

    if (bestConn == null) return null;

    final segmentStart = startIndex * 2;
    final segmentEnd = segmentStart + 1;

    if (segmentEnd >= bestConn.points.length) return null;

    final p1 = bestConn.points[segmentStart];
    final p2 = bestConn.points[segmentEnd];

    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * fraction,
      p1.longitude + (p2.longitude - p1.longitude) * fraction,
    );
  }

  MapState copyWith({
    MapStatus? status,
    List<GtfsStop>? allStops,
    List<GtfsConnection>? allConnections,
    Set<String>? enabledRouteIds,
    String? errorMessage,
    List<RecordedStopEvent>? recordedEvents,
    Map<String, List<RecordedStopEvent>>? currentDayEvents,
    Map<String, GtfsStop>? stopNameLookup,
    Set<DateTime>? availableDays,
    DateTime? selectedDay,
    DateTime? currentPlaybackTime,
    bool? isPlaying,
    double? playbackSpeed,
  }) {
    return MapState(
      status: status ?? this.status,
      allStops: allStops ?? this.allStops,
      allConnections: allConnections ?? this.allConnections,
      enabledRouteIds: enabledRouteIds ?? this.enabledRouteIds,
      errorMessage: errorMessage ?? this.errorMessage,
      recordedEvents: recordedEvents ?? this.recordedEvents,
      currentDayEvents: currentDayEvents ?? this.currentDayEvents,
      stopNameLookup: stopNameLookup ?? this.stopNameLookup,
      availableDays: availableDays ?? this.availableDays,
      selectedDay: selectedDay ?? this.selectedDay,
      currentPlaybackTime: currentPlaybackTime ?? this.currentPlaybackTime,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    );
  }

  @override
  List<Object?> get props => [
        status,
        allStops,
        allConnections,
        enabledRouteIds,
        errorMessage,
        recordedEvents,
        currentDayEvents,
        stopNameLookup,
        availableDays,
        selectedDay,
        currentPlaybackTime,
        isPlaying,
        playbackSpeed,
      ];
}

class ActiveVehicle {
  final String tripId;
  final LatLng location;
  final int delaySeconds;
  final String lineId;

  ActiveVehicle({
    required this.tripId,
    required this.location,
    required this.delaySeconds,
    required this.lineId,
  });
}
