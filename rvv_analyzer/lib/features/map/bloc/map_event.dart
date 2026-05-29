import 'package:equatable/equatable.dart';
import 'package:rvv_analyzer/features/map/bloc/map_state.dart';

abstract class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

class MapLoadStarted extends MapEvent {
  const MapLoadStarted();
}

class MapRouteFilterToggled extends MapEvent {
  final String routeId;
  final bool isEnabled;

  const MapRouteFilterToggled({required this.routeId, required this.isEnabled});

  @override
  List<Object?> get props => [routeId, isEnabled];
}

class MapAllRoutesToggled extends MapEvent {
  final bool enableAll;

  const MapAllRoutesToggled({required this.enableAll});

  @override
  List<Object?> get props => [enableAll];
}

class MapPlaybackStarted extends MapEvent {
  const MapPlaybackStarted();
}

class MapPlaybackPaused extends MapEvent {
  const MapPlaybackPaused();
}

class MapPlaybackTimeChanged extends MapEvent {
  final DateTime time;

  const MapPlaybackTimeChanged(this.time);

  @override
  List<Object?> get props => [time];
}

class MapPlaybackSpeedChanged extends MapEvent {
  final double speed;

  const MapPlaybackSpeedChanged(this.speed);

  @override
  List<Object?> get props => [speed];
}

class MapTickerTicked extends MapEvent {
  final DateTime time;

  const MapTickerTicked(this.time);

  @override
  List<Object?> get props => [time];
}

class MapDaySelected extends MapEvent {
  final DateTime day;

  const MapDaySelected(this.day);

  @override
  List<Object?> get props => [day];
}

class MapVisualizationModeChanged extends MapEvent {
  final VisualizationMode mode;

  const MapVisualizationModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}
