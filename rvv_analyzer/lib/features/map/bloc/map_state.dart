import 'dart:math' as math;
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_connection.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_stop.dart';
import 'package:rvv_analyzer/gtfs/models/recorded_stop_event.dart';

enum MapStatus { initial, loading, loaded, error }

enum VisualizationMode { buses, heatmap }

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
  final VisualizationMode vizMode;

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
    this.vizMode = VisualizationMode.buses,
  });

  List<GtfsConnection> get filteredConnections {
    return allConnections
        .where((conn) => enabledRouteIds.contains(conn.routeId))
        .toList();
  }

  List<ActiveVehicle> get activeVehicles {
    if (currentPlaybackTime == null || vizMode != VisualizationMode.buses) {
      return [];
    }
    final active = <ActiveVehicle>[];

    for (var tripId in currentDayEvents.keys) {
      final events = currentDayEvents[tripId]!;
      for (var i = 0; i < events.length; i++) {
        final current = events[i];

        // Case 1: At a stop
        if ((currentPlaybackTime!.isAfter(current.arrivalTimeActual) ||
                currentPlaybackTime!
                    .isAtSameMomentAs(current.arrivalTimeActual)) &&
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
                  currentPlaybackTime!
                      .isAtSameMomentAs(current.departureTimeActual)) &&
              (currentPlaybackTime!.isBefore(next.arrivalTimeActual) ||
                  currentPlaybackTime!
                      .isAtSameMomentAs(next.arrivalTimeActual))) {
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

  List<AggregatedStopDelay> get aggregatedDelays {
    if (currentPlaybackTime == null || vizMode != VisualizationMode.heatmap) {
      return [];
    }

    final stopAggregates = <String, _StopAccumulator>{};
    final eventsForDay = currentDayEvents.values.expand((e) => e).toList();

    for (var event in eventsForDay) {
      if ((event.arrivalTimeActual.isBefore(currentPlaybackTime!) ||
          event.arrivalTimeActual.isAtSameMomentAs(currentPlaybackTime!))) {
        // Filter by enabled route IDs
        bool isRouteEnabled = enabledRouteIds.contains(event.lineId) ||
            allConnections.any((conn) =>
                conn.lineName == event.lineId &&
                enabledRouteIds.contains(conn.routeId));

        if (!isRouteEnabled) continue;

        final stop = _findStop(event);
        if (stop != null) {
          final delay = event.arrivalDelaySeconds ?? 0;
          if (delay > 60) {
            final acc = stopAggregates.putIfAbsent(
              stop.id,
              () => _StopAccumulator(stop.id, stop.name, stop.location),
            );
            acc.maxDelaySeconds = math.max(acc.maxDelaySeconds, delay);
            acc.minDelaySeconds = math.min(acc.minDelaySeconds, delay);
            acc.totalDelaySeconds += delay;
            acc.totalDelayedBuses++;
          }
        }
      }
    }

    final result = stopAggregates.values
        .map((acc) => AggregatedStopDelay(
              stopId: acc.stopId,
              stopName: acc.stopName,
              location: acc.location,
              minDelaySeconds: acc.minDelaySeconds,
              maxDelaySeconds: acc.maxDelaySeconds,
              totalDelaySeconds: acc.totalDelaySeconds,
              totalDelayedBuses: acc.totalDelayedBuses,
            ))
        .toList();

    // Sort by volume of delays descending
    result.sort((a, b) => b.totalDelayedBuses.compareTo(a.totalDelayedBuses));
    return result;
  }

  List<BlinkingBus> get blinkingBuses {
    if (currentPlaybackTime == null || vizMode != VisualizationMode.heatmap) {
      return [];
    }

    final blinking = <BlinkingBus>[];
    final eventsForDay = currentDayEvents.values.expand((e) => e).toList();

    for (var event in eventsForDay) {
      final timeDiff = currentPlaybackTime!.difference(event.arrivalTimeActual);
      if (timeDiff.inSeconds >= 0 && timeDiff.inMinutes < 2) {
        // Filter by enabled route IDs
        bool isRouteEnabled = enabledRouteIds.contains(event.lineId) ||
            allConnections.any((conn) =>
                conn.lineName == event.lineId &&
                enabledRouteIds.contains(conn.routeId));

        if (!isRouteEnabled) continue;

        final stop = _findStop(event);
        if (stop != null) {
          final delay = event.arrivalDelaySeconds ?? 0;
          if (delay > 60) {
            blinking.add(
              BlinkingBus(
                location: stop.location,
                lineId: event.lineId,
                delaySeconds: delay,
              ),
            );
          }
        }
      }
    }
    return blinking;
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

    // Find the shape points closest to the start and end stops
    final startStopLoc =
        allStops.where((s) => s.id == startStopId).firstOrNull?.location;
    final endStopLoc =
        allStops.where((s) => s.id == endStopId).firstOrNull?.location;
    if (startStopLoc == null || endStopLoc == null) return null;

    final points = bestConn.points;
    if (points.length < 2) return null;

    // Find nearest point index in polyline for start and end stop
    int nearestStartIdx = _nearestPointIndex(points, startStopLoc);
    int nearestEndIdx = _nearestPointIndex(points, endStopLoc);

    if (nearestEndIdx <= nearestStartIdx) {
      // Fallback to simple linear interpolation
      return LatLng(
        startStopLoc.latitude +
            (endStopLoc.latitude - startStopLoc.latitude) * fraction,
        startStopLoc.longitude +
            (endStopLoc.longitude - startStopLoc.longitude) * fraction,
      );
    }

    // Get sub-polyline between the two stops
    final subPoints = points.sublist(nearestStartIdx, nearestEndIdx + 1);
    if (subPoints.length < 2) return subPoints.first;

    // Compute cumulative distances along sub-polyline
    final distances = <double>[0.0];
    for (var i = 1; i < subPoints.length; i++) {
      final d = _distanceBetween(subPoints[i - 1], subPoints[i]);
      distances.add(distances.last + d);
    }

    final totalDist = distances.last;
    if (totalDist == 0) return subPoints.first;

    final targetDist = totalDist * fraction;

    // Find the segment containing targetDist
    for (var i = 1; i < distances.length; i++) {
      if (distances[i] >= targetDist) {
        final segLen = distances[i] - distances[i - 1];
        final segFraction = segLen > 0
            ? (targetDist - distances[i - 1]) / segLen
            : 0.0;
        final p1 = subPoints[i - 1];
        final p2 = subPoints[i];
        return LatLng(
          p1.latitude + (p2.latitude - p1.latitude) * segFraction,
          p1.longitude + (p2.longitude - p1.longitude) * segFraction,
        );
      }
    }

    return subPoints.last;
  }

  static int _nearestPointIndex(List<LatLng> points, LatLng target) {
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = _distanceBetween(points[i], target);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  static double _distanceBetween(LatLng a, LatLng b) {
    final dlat = a.latitude - b.latitude;
    final dlon = a.longitude - b.longitude;
    return dlat * dlat + dlon * dlon;
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
    VisualizationMode? vizMode,
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
      vizMode: vizMode ?? this.vizMode,
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
        vizMode,
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

class _StopAccumulator {
  final String stopId;
  final String stopName;
  final LatLng location;
  int minDelaySeconds = 999999;
  int maxDelaySeconds = 0;
  int totalDelaySeconds = 0;
  int totalDelayedBuses = 0;

  _StopAccumulator(this.stopId, this.stopName, this.location);
}

class AggregatedStopDelay {
  final String stopId;
  final String stopName;
  final LatLng location;
  final int minDelaySeconds;
  final int maxDelaySeconds;
  final int totalDelaySeconds;
  final int totalDelayedBuses;

  AggregatedStopDelay({
    required this.stopId,
    required this.stopName,
    required this.location,
    required this.minDelaySeconds,
    required this.maxDelaySeconds,
    required this.totalDelaySeconds,
    required this.totalDelayedBuses,
  });

  double get averageDelaySeconds =>
      totalDelayedBuses > 0 ? totalDelaySeconds / totalDelayedBuses : 0;

  Color get color {
    if (maxDelaySeconds > 300) return Colors.red;
    if (maxDelaySeconds > 60) return Colors.orange;
    return Colors.green;
  }

  double get radius {
    // Starts at 10, grows with volume of delays
    return 10.0 + (math.log(totalDelayedBuses + 1) * 8.0);
  }

  double get opacity {
    // More consistent trouble = deeper color
    return (0.3 + (math.min(totalDelayedBuses, 10) / 20.0)).clamp(0.0, 0.8);
  }
}

class BlinkingBus {
  final LatLng location;
  final String lineId;
  final int delaySeconds;

  BlinkingBus({
    required this.location,
    required this.lineId,
    required this.delaySeconds,
  });

  Color get color {
    if (delaySeconds > 300) return Colors.red;
    if (delaySeconds > 60) return Colors.orange;
    return Colors.green;
  }
}
