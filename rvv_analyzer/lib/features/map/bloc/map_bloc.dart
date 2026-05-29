import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rvv_analyzer/core/assets.gen.dart';
import 'package:rvv_analyzer/features/map/bloc/map_event.dart';
import 'package:rvv_analyzer/features/map/bloc/map_state.dart';
import 'package:rvv_analyzer/gtfs/tools/gtfs_parser.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc() : super(const MapState()) {
    on<MapLoadStarted>(_onLoadStarted);
    on<MapRouteFilterToggled>(_onRouteFilterToggled);
    on<MapAllRoutesToggled>(_onAllRoutesToggled);
  }

  Future<void> _onLoadStarted(
    MapLoadStarted event,
    Emitter<MapState> emit,
  ) async {
    emit(state.copyWith(status: MapStatus.loading));

    final csvStops = await rootBundle.loadString(Assets.gtfs.stops);
    final csvStopTimes= await rootBundle.loadString(Assets.gtfs.stopTimes);
    final csvTrips = await rootBundle.loadString(Assets.gtfs.trips);
    final csvRoutes = await rootBundle.loadString(Assets.gtfs.routes);

    try {
      final stops = GtfsParser.parseStops(csvStops);
      final connections = GtfsParser.reconstructConnections(
        stopTimesCsv: csvStopTimes,
        tripsCsv: csvTrips,
        routesCsv: csvRoutes,
        stops: stops,
      );

      final routeIds = connections.map((c) => c.routeId).toSet();

      emit(
        state.copyWith(
          status: MapStatus.loaded,
          allStops: stops,
          allConnections: connections,
          enabledRouteIds: routeIds,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: MapStatus.error, errorMessage: e.toString()));
    }
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
