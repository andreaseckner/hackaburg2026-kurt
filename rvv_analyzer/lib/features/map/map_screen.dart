import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:rvv_analyzer/core/dimens.dart';
import 'package:rvv_analyzer/core/l10n/app_localizations.dart';
import 'package:rvv_analyzer/features/map/bloc/map_bloc.dart';
import 'package:rvv_analyzer/features/map/bloc/map_event.dart';
import 'package:rvv_analyzer/features/map/bloc/map_state.dart';
import 'package:rvv_analyzer/gtfs/models/gtfs_connection.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MapBloc()..add(const MapLoadStarted()),
      child: const _MapView(),
    );
  }
}

class _MapView extends StatelessWidget {
  // Map Config
  static const LatLng _initialCenter = LatLng(49.0134, 12.1016); // Regensburg
  static const String _osmUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _userAgentPackage = 'de.rvv.rvv_analyzer';

  const _MapView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocConsumer<MapBloc, MapState>(
      listener: (context, state) {
        if (state.status == MapStatus.error && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.errorLoadingGtfs(state.errorMessage!))),
          );
        }
      },
      builder: (context, state) {
        final uniqueRoutes = <String, GtfsConnection>{};
        for (var conn in state.allConnections) {
          if (!uniqueRoutes.containsKey(conn.routeId)) {
            uniqueRoutes[conn.routeId] = conn;
          }
        }
        final sortedRoutes = uniqueRoutes.values.toList()
          ..sort((a, b) => a.lineName.compareTo(b.lineName));

        final activeVehicles = state.activeVehicles.where((v) {
          return state.enabledRouteIds.contains(v.lineId) ||
              state.allConnections.any(
                (conn) =>
                    conn.lineName == v.lineId &&
                    state.enabledRouteIds.contains(conn.routeId),
              );
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.appTitle),
            actions: [
              if (state.status == MapStatus.loaded) ...[
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () => _selectDay(context, state),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterDialog(context, sortedRoutes),
                ),
              ],
            ],
          ),
          body: Stack(
            children: [
              FlutterMap(
                options: const MapOptions(
                  initialCenter: _initialCenter,
                  initialZoom: Dimens.initialZoom,
                ),
                children: [
                  TileLayer(
                    urlTemplate: _osmUrlTemplate,
                    userAgentPackageName: _userAgentPackage,
                  ),
                  PolylineLayer(
                    polylines: state.filteredConnections.map((conn) {
                      return Polyline(
                        points: conn.points,
                        color: conn.color.withAlpha(Dimens.polylineAlpha),
                        strokeWidth: Dimens.polylineStrokeWidth,
                      );
                    }).toList(),
                  ),
                  // Stop Markers
                  MarkerLayer(
                    markers: state.allStops.map((stop) {
                      return Marker(
                        point: stop.location,
                        width: Dimens.stopMarkerSize,
                        height: Dimens.stopMarkerSize,
                        child: Icon(
                          Icons.circle,
                          color: Colors.blue.withValues(alpha: 0.3),
                          size: 8,
                        ),
                      );
                    }).toList(),
                  ),
                  // Active Vehicle Markers
                  MarkerLayer(
                    markers: activeVehicles.map((v) {
                      Color color = Colors.green;
                      if (v.delaySeconds > 300) {
                        color = Colors.red;
                      } else if (v.delaySeconds > 60) {
                        color = Colors.orange;
                      }

                      return Marker(
                        point: v.location,
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              v.lineId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (state.status == MapStatus.loading)
                const Center(child: CircularProgressIndicator()),
              _PlaybackControlPanel(state: state),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectDay(BuildContext context, MapState state) async {
    if (state.availableDays.isEmpty) return;

    final initialDate = state.selectedDay ?? state.availableDays.first;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: state.availableDays.reduce((a, b) => a.isBefore(b) ? a : b),
      lastDate: state.availableDays.reduce((a, b) => a.isAfter(b) ? a : b),
      selectableDayPredicate: (date) {
        return state.availableDays.any((d) =>
            d.year == date.year && d.month == date.month && d.day == date.day);
      },
    );

    if (pickedDate != null && context.mounted) {
      context.read<MapBloc>().add(MapDaySelected(pickedDate));
    }
  }

  void _showFilterDialog(BuildContext context, List<GtfsConnection> routes) {
    final l10n = AppLocalizations.of(context)!;
    final mapBloc = context.read<MapBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return BlocProvider.value(
          value: mapBloc,
          child: DraggableScrollableSheet(
            initialChildSize: Dimens.sheetInitialSize,
            maxChildSize: Dimens.sheetMaxSize,
            minChildSize: Dimens.sheetMinSize,
            expand: false,
            builder: (context, scrollController) {
              return BlocBuilder<MapBloc, MapState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Dimens.paddingLarge),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.filterBusLines,
                              style: const TextStyle(
                                fontSize: Dimens.fontSizeMedium,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () => context.read<MapBloc>().add(
                                    const MapAllRoutesToggled(enableAll: true),
                                  ),
                                  child: Text(l10n.all),
                                ),
                                TextButton(
                                  onPressed: () => context.read<MapBloc>().add(
                                    const MapAllRoutesToggled(enableAll: false),
                                  ),
                                  child: Text(l10n.none),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: routes.length,
                          itemBuilder: (context, index) {
                            final route = routes[index];
                            final isEnabled = state.enabledRouteIds.contains(
                              route.routeId,
                            );
                            return CheckboxListTile(
                              secondary: Container(
                                width: Dimens.routeColorBoxSize,
                                height: Dimens.routeColorBoxSize,
                                decoration: BoxDecoration(
                                  color: route.color,
                                  borderRadius: BorderRadius.circular(
                                    Dimens.borderRadiusSmall,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    route.lineName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: Dimens.fontSizeSmall,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(l10n.line(route.lineName)),
                              value: isEnabled,
                              onChanged: (bool? value) {
                                context.read<MapBloc>().add(
                                  MapRouteFilterToggled(
                                    routeId: route.routeId,
                                    isEnabled: value ?? false,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _PlaybackControlPanel extends StatelessWidget {
  final MapState state;

  const _PlaybackControlPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.currentPlaybackTime == null) {
      return const SizedBox.shrink();
    }

    final eventsForDay = state.currentDayEvents.values.expand((e) => e).toList();
    if (eventsForDay.isEmpty) return const SizedBox.shrink();

    final startTime = eventsForDay
        .map((e) => e.arrivalTimeActual)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final endTime = eventsForDay
        .map((e) => e.departureTimeActual)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final totalDuration = endTime.difference(startTime).inSeconds;
    final currentOffset =
        state.currentPlaybackTime!.difference(startTime).inSeconds;

    final dateFormat = DateFormat('dd.MM.yyyy');
    final timeFormat = DateFormat('HH:mm:ss');

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Card(
        elevation: 4,
        color: Colors.white.withValues(alpha: 0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
                    color: Theme.of(context).primaryColor,
                    onPressed: () {
                      if (state.isPlaying) {
                        context.read<MapBloc>().add(const MapPlaybackPaused());
                      } else {
                        context.read<MapBloc>().add(const MapPlaybackStarted());
                      }
                    },
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dateFormat.format(state.currentPlaybackTime!),
                        style: const TextStyle(fontSize: 10),
                      ),
                      Text(
                        timeFormat.format(state.currentPlaybackTime!),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Slider(
                      value: currentOffset.toDouble().clamp(0, totalDuration.toDouble()),
                      max: totalDuration.toDouble() > 0 ? totalDuration.toDouble() : 1.0,
                      onChanged: (value) {
                        final newTime =
                            startTime.add(Duration(seconds: value.toInt()));
                        context
                            .read<MapBloc>()
                            .add(MapPlaybackTimeChanged(newTime));
                      },
                    ),
                  ),
                  Text(timeFormat.format(endTime), style: const TextStyle(fontSize: 12)),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Playback Speed:', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    _SpeedChip(speed: 60, current: state.playbackSpeed, label: '1 min/s'),
                    _SpeedChip(speed: 120, current: state.playbackSpeed, label: '2 min/s'),
                    _SpeedChip(speed: 300, current: state.playbackSpeed, label: '5 min/s'),
                    _SpeedChip(speed: 600, current: state.playbackSpeed, label: '10 min/s'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final double speed;
  final double current;
  final String label;

  const _SpeedChip({required this.speed, required this.current, required this.label});

  @override
  Widget build(BuildContext context) {
    final isSelected = speed == current;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isSelected,
        onSelected: (_) {
          context.read<MapBloc>().add(MapPlaybackSpeedChanged(speed));
        },
      ),
    );
  }
}
