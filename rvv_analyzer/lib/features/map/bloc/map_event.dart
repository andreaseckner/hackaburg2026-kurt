import 'package:equatable/equatable.dart';

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
