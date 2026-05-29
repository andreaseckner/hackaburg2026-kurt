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
import 'package:rvv_analyzer/features/map/models/weather_record.dart';

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

enum DelaySortOption { count, max, average }

class _MapView extends StatefulWidget {
  const _MapView();

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> with SingleTickerProviderStateMixin {
  // Map Config
  static const LatLng _initialCenter = LatLng(49.0134, 12.1016); // Regensburg
  static const String _osmUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _userAgentPackage = 'de.rvv.rvv_analyzer';

  late AnimationController _blinkController;
  bool _isStatsPanelVisible = false;
  DelaySortOption _sortOption = DelaySortOption.count;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

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

        final aggregatedDelays = state.aggregatedDelays;
        final blinkingBuses = state.blinkingBuses;

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
                  if (state.vizMode != VisualizationMode.heatmap)
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
                  // Heatmap Persistence Layer (Aggregated Stop Delays)
                  if (state.vizMode == VisualizationMode.heatmap)
                    CircleLayer(
                      circles: aggregatedDelays.map((agg) {
                        return CircleMarker(
                          point: agg.location,
                          color: agg.color.withValues(alpha: agg.opacity),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: false,
                          radius: agg.radius,
                        );
                      }).toList(),
                    ),
                  // Active UI Layer (Moving Buses or Blinking New Arrivals)
                  MarkerLayer(
                    markers: [
                      if (state.vizMode == VisualizationMode.buses)
                        ...activeVehicles.map((v) {
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
                            child: _BusMarker(color: color, lineId: v.lineId),
                          );
                        }),
                      if (state.vizMode == VisualizationMode.heatmap && state.isPlaying)
                        ...blinkingBuses.map((bus) {
                          return Marker(
                            point: bus.location,
                            width: 32,
                            height: 32,
                            child: FadeTransition(
                              opacity: _blinkController,
                              child: _BusMarker(
                                  color: bus.color, lineId: bus.lineId),
                            ),
                          );
                        }),
                    ],
                  ),
                ],
              ),
              if (state.status == MapStatus.loading)
                const Center(child: CircularProgressIndicator()),
              _PlaybackControlPanel(state: state),

              // Weather Overlay
              if (state.status == MapStatus.loaded)
                Positioned(
                  top: 16,
                  left: 16,
                  child: _WeatherOverlay(state: state),
                ),

              // Stats Toggle Button
              if (state.vizMode == VisualizationMode.heatmap)
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: () => setState(() => _isStatsPanelVisible = !_isStatsPanelVisible),
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    child: Icon(
                      _isStatsPanelVisible ? Icons.close : Icons.analytics,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),

              // Right Side Stats Panel
              if (state.vizMode == VisualizationMode.heatmap)
                _RightDelayStatsPanel(
                  aggregatedDelays: aggregatedDelays,
                  isVisible: _isStatsPanelVisible,
                  sortOption: _sortOption,
                  onSortChanged: (option) => setState(() => _sortOption = option),
                ),
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

class _BusMarker extends StatelessWidget {
  final Color color;
  final String lineId;

  const _BusMarker({required this.color, required this.lineId});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          lineId,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: SegmentedButton<VisualizationMode>(
                  segments: const [
                    ButtonSegment(
                      value: VisualizationMode.buses,
                      label: Text('Buses'),
                      icon: Icon(Icons.directions_bus),
                    ),
                    ButtonSegment(
                      value: VisualizationMode.heatmap,
                      label: Text('Heatmap'),
                      icon: Icon(Icons.local_fire_department),
                    ),
                  ],
                  selected: {state.vizMode},
                  onSelectionChanged: (Set<VisualizationMode> newSelection) {
                    context.read<MapBloc>().add(
                          MapVisualizationModeChanged(newSelection.first),
                        );
                  },
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon:
                        Icon(state.isPlaying ? Icons.pause : Icons.play_arrow),
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
                      value: currentOffset
                          .toDouble()
                          .clamp(0, totalDuration.toDouble()),
                      max: totalDuration.toDouble() > 0
                          ? totalDuration.toDouble()
                          : 1.0,
                      onChanged: (value) {
                        final newTime =
                            startTime.add(Duration(seconds: value.toInt()));
                        context
                            .read<MapBloc>()
                            .add(MapPlaybackTimeChanged(newTime));
                      },
                    ),
                  ),
                  Text(timeFormat.format(endTime),
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Playback Speed:',
                        style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    _SpeedChip(
                        speed: 60, current: state.playbackSpeed, label: '1 min/s'),
                    _SpeedChip(
                        speed: 120, current: state.playbackSpeed, label: '2 min/s'),
                    _SpeedChip(
                        speed: 300, current: state.playbackSpeed, label: '5 min/s'),
                    _SpeedChip(
                        speed: 600, current: state.playbackSpeed, label: '10 min/s'),
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

  const _SpeedChip(
      {required this.speed, required this.current, required this.label});

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

class _RightDelayStatsPanel extends StatelessWidget {
  final List<AggregatedStopDelay> aggregatedDelays;
  final bool isVisible;
  final DelaySortOption sortOption;
  final Function(DelaySortOption) onSortChanged;

  const _RightDelayStatsPanel({
    required this.aggregatedDelays,
    required this.isVisible,
    required this.sortOption,
    required this.onSortChanged,
  });

  String _formatSeconds(num seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).round();
    return '${minutes}m ${remainingSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    // Apply sorting based on user selection
    final sortedList = List<AggregatedStopDelay>.from(aggregatedDelays);
    switch (sortOption) {
      case DelaySortOption.count:
        sortedList.sort((a, b) => b.totalDelayedBuses.compareTo(a.totalDelayedBuses));
        break;
      case DelaySortOption.max:
        sortedList.sort((a, b) => b.maxDelaySeconds.compareTo(a.maxDelaySeconds));
        break;
      case DelaySortOption.average:
        sortedList.sort((a, b) => b.averageDelaySeconds.compareTo(a.averageDelaySeconds));
        break;
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      top: 16,
      bottom: 200, // Stay above the playback controls
      right: isVisible ? 16 : -320, // Slide out of view
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(-2, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics, size: 18, color: Colors.blueGrey),
                      SizedBox(width: 8),
                      Text(
                        'Top Delayed Stops',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Sort Toggle
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Sort by: ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        const SizedBox(width: 4),
                        _SortChip(
                          label: 'Freq',
                          isSelected: sortOption == DelaySortOption.count,
                          onSelected: () => onSortChanged(DelaySortOption.count),
                        ),
                        _SortChip(
                          label: 'Max',
                          isSelected: sortOption == DelaySortOption.max,
                          onSelected: () => onSortChanged(DelaySortOption.max),
                        ),
                        _SortChip(
                          label: 'Avg',
                          isSelected: sortOption == DelaySortOption.average,
                          onSelected: () => onSortChanged(DelaySortOption.average),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: sortedList.length,
                itemBuilder: (context, index) {
                  final stop = sortedList[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: stop.color.withValues(alpha: 0.2),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                            color: stop.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 10),
                      ),
                    ),
                    title: Text(
                      stop.stopName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${stop.totalDelayedBuses} delays',
                          style: const TextStyle(fontSize: 10),
                        ),
                        Row(
                          children: [
                            Text(
                              'Max: ${_formatSeconds(stop.maxDelaySeconds)}',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: sortOption == DelaySortOption.max ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Avg: ${_formatSeconds(stop.averageDelaySeconds)}',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: sortOption == DelaySortOption.average ? FontWeight.bold : FontWeight.normal),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  const _SortChip({required this.label, required this.isSelected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 9)),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _WeatherOverlay extends StatelessWidget {
  final MapState state;

  const _WeatherOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final WeatherRecord? weather = state.currentWeather;
    if (weather == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      color: Colors.white.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  weather.conditionIcon,
                  color: weather.conditionColor,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${weather.temp.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      weather.conditionDescription,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (weather.rhum != null) ...[
                  const Icon(Icons.water_drop, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.rhum!.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  const SizedBox(width: 8),
                ],
                if (weather.wspd != null) ...[
                  const Icon(Icons.air, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.wspd!.toStringAsFixed(1)} km/h',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                  const SizedBox(width: 8),
                ],
                if (weather.prcp != null && weather.prcp! > 0) ...[
                  const Icon(Icons.umbrella, size: 12, color: Colors.blueGrey),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.prcp!.toStringAsFixed(1)} mm',
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
