import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rvv_analyzer/core/assets.gen.dart';
import 'package:rvv_analyzer/features/map/bloc/map_event.dart';
import 'package:rvv_analyzer/features/map/bloc/map_state.dart';
import 'package:rvv_analyzer/gtfs/models/recorded_stop_event.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_stop.dart';
import 'package:rvv_analyzer/gtfs/tools/gtfs_parser.dart';
import 'package:rvv_analyzer/gtfs/tools/recorded_data_parser.dart';
import 'package:rvv_analyzer/gtfs/tools/weather_parser.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  Timer? _playbackTimer;

  MapBloc() : super(const MapState()) {
    on<MapLoadStarted>(_onLoadStarted);
    on<MapDaySelected>(_onDaySelected);
    on<MapVisualizationModeChanged>(_onVisualizationModeChanged);
    on<MapRouteFilterToggled>(_onRouteFilterToggled);
    on<MapAllRoutesToggled>(_onAllRoutesToggled);
    on<MapPlaybackStarted>(_onPlaybackStarted);
    on<MapPlaybackPaused>(_onPlaybackPaused);
    on<MapPlaybackTimeChanged>(_onPlaybackTimeChanged);
    on<MapPlaybackSpeedChanged>(_onPlaybackSpeedChanged);
    on<MapTickerTicked>(_onTickerTicked);
  }

  @override
  Future<void> close() {
    _playbackTimer?.cancel();
    return super.close();
  }

  Future<void> _onLoadStarted(
    MapLoadStarted event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(status: MapStatus.loading));

    try {
      final csvStops = await rootBundle.loadString(Assets.gtfs.stops);
      final csvStopTimes = await rootBundle.loadString(Assets.gtfs.stopTimes);
      final csvTrips = await rootBundle.loadString(Assets.gtfs.trips);
      final csvRoutes = await rootBundle.loadString(Assets.gtfs.routes);
      final csvRecording = await rootBundle.loadString(Assets.rec.october2024);
      final csvWeather = await rootBundle.loadString(Assets.weather.weatherRegensburgAll);

      final stops = GtfsParser.parseStops(csvStops);
      final connections = GtfsParser.reconstructConnections(
        stopTimesCsv: csvStopTimes,
        tripsCsv: csvTrips,
        routesCsv: csvRoutes,
        stops: stops,
      );

      final recordedEvents = RecordedDataParser.parseRecording(csvRecording);
      final weatherRecords = WeatherParser.parseWeather(csvWeather);
      
      // Extract available days
      final availableDays = recordedEvents
          .map((e) => DateTime(
                e.arrivalTimeActual.year,
                e.arrivalTimeActual.month,
                e.arrivalTimeActual.day,
              ))
          .toSet();

      final stopNameLookup = <String, GtfsStop>{};
      for (var stop in stops) {
        final cleanName = stop.name.split('(').first.trim().toLowerCase();
        stopNameLookup.putIfAbsent(cleanName, () => stop);
      }

      final routeIds = connections.map((c) => c.routeId).toSet();

      final selectedDay = availableDays.isNotEmpty ? availableDays.first : null;

      final newState = state.copyWith(
        status: MapStatus.loaded,
        allStops: stops,
        allConnections: connections,
        enabledRouteIds: routeIds,
        recordedEvents: recordedEvents,
        stopNameLookup: stopNameLookup,
        availableDays: availableDays,
        weatherRecords: weatherRecords,
      );

      if (selectedDay != null) {
        emit(_processDayChange(newState, selectedDay));
      } else {
        emit(newState);
      }
    } catch (e) {
      emit(state.copyWith(status: MapStatus.error, errorMessage: e.toString()));
    }
  }

  void _onDaySelected(MapDaySelected event, Emitter<MapState> emit) {
    emit(_processDayChange(state, event.day));
  }

  void _onVisualizationModeChanged(
    MapVisualizationModeChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(vizMode: event.mode));
  }

  MapState _processDayChange(MapState currentState, DateTime day) {
    final dayEvents = currentState.recordedEvents.where((e) {
      return e.arrivalTimeActual.year == day.year &&
          e.arrivalTimeActual.month == day.month &&
          e.arrivalTimeActual.day == day.day;
    }).toList();

    final grouped = <String, List<RecordedStopEvent>>{};
    for (var event in dayEvents) {
      grouped.putIfAbsent(event.tripId, () => []).add(event);
    }
    for (var list in grouped.values) {
      list.sort((a, b) => a.arrivalTimePlanned.compareTo(b.arrivalTimePlanned));
    }

    final initialTime = dayEvents.isNotEmpty 
        ? dayEvents.first.arrivalTimeActual 
        : null;

    return currentState.copyWith(
      selectedDay: day,
      currentDayEvents: grouped,
      currentPlaybackTime: initialTime,
    );
  }

  void _onPlaybackStarted(MapPlaybackStarted event, Emitter<MapState> emit) {
    _playbackTimer?.cancel();
    
    DateTime? playbackTime = state.currentPlaybackTime;
    final eventsForDay = state.currentDayEvents.values.expand((e) => e).toList();
    if (eventsForDay.isNotEmpty && playbackTime != null) {
      final endTime = eventsForDay
          .map((e) => e.departureTimeActual)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (playbackTime.isAfter(endTime) || playbackTime.isAtSameMomentAs(endTime)) {
        final startTime = eventsForDay
            .map((e) => e.arrivalTimeActual)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        playbackTime = startTime;
      }
    }

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (state.currentPlaybackTime != null) {
        final newTime = state.currentPlaybackTime!.add(
          Duration(milliseconds: (100 * state.playbackSpeed).toInt()),
        );
        add(MapTickerTicked(newTime));
      }
    });
    emit(state.copyWith(
      isPlaying: true,
      currentPlaybackTime: playbackTime,
    ));
  }

  void _onPlaybackPaused(MapPlaybackPaused event, Emitter<MapState> emit) {
    _playbackTimer?.cancel();
    emit(state.copyWith(isPlaying: false));
  }

  void _onPlaybackTimeChanged(
    MapPlaybackTimeChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(currentPlaybackTime: event.time));
  }

  void _onPlaybackSpeedChanged(
    MapPlaybackSpeedChanged event,
    Emitter<MapState> emit,
  ) {
    emit(state.copyWith(playbackSpeed: event.speed));
  }

  void _onTickerTicked(MapTickerTicked event, Emitter<MapState> emit) {
    final eventsForDay = state.currentDayEvents.values.expand((e) => e).toList();
    if (eventsForDay.isNotEmpty) {
      final endTime = eventsForDay
          .map((e) => e.departureTimeActual)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (event.time.isAfter(endTime)) {
        _playbackTimer?.cancel();
        emit(state.copyWith(
          currentPlaybackTime: endTime,
          isPlaying: false,
        ));
        return;
      }
    }
    emit(state.copyWith(currentPlaybackTime: event.time));
  }

  void _onRouteFilterToggled(
    MapRouteFilterToggled event,
    Emitter<MapState> emit,
  ) {
    final newEnabledIds = Set<String>.from(state.enabledRouteIds);
    if (event.isEnabled) {
      newEnabledIds.add(event.routeId);
    } else {
      newEnabledIds.remove(event.routeId);
    }
    emit(state.copyWith(enabledRouteIds: newEnabledIds));
  }

  void _onAllRoutesToggled(MapAllRoutesToggled event, Emitter<MapState> emit) {
    if (event.enableAll) {
      final allRouteIds = state.allConnections.map((c) => c.routeId).toSet();
      emit(state.copyWith(enabledRouteIds: allRouteIds));
    } else {
      emit(state.copyWith(enabledRouteIds: {}));
    }
  }
}
