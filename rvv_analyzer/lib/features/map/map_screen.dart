import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:rvv_analyzer/core/dimens.dart';
import 'package:rvv_analyzer/core/l10n/app_localizations.dart';
import 'package:rvv_analyzer/features/chat/bloc/chat_bloc.dart';
import 'package:rvv_analyzer/features/chat/widgets/chat_panel.dart';
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

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.appTitle),
            actions: [
              if (state.status == MapStatus.loaded) ...[
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => _showChatPanel(context),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () => _showFilterDialog(context, sortedRoutes),
                ),
              ],
            ],
          ),
          body: state.status == MapStatus.loading
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
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
                    MarkerLayer(
                      markers: state.filteredConnections.expand((conn) {
                        return conn.midpoints.map((midpoint) {
                          return Marker(
                            point: midpoint,
                            width: Dimens.markerWidth,
                            height: Dimens.markerHeight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Dimens.paddingSmall,
                                vertical: Dimens.paddingSmall / 2,
                              ),
                              decoration: BoxDecoration(
                                color: conn.color,
                                borderRadius: BorderRadius.circular(
                                  Dimens.borderRadiusSmall,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(
                                      Dimens.shadowAlpha,
                                    ),
                                    blurRadius: Dimens.shadowBlurRadius,
                                    offset: const Offset(
                                      Dimens.shadowOffsetX,
                                      Dimens.shadowOffsetY,
                                    ),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  conn.lineName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: Dimens.fontSizeSmall,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          );
                        });
                      }).toList(),
                    ),
                    MarkerLayer(
                      markers: state.allStops.map((stop) {
                        return Marker(
                          point: stop.location,
                          width: Dimens.stopMarkerSize,
                          height: Dimens.stopMarkerSize,
                          child: GestureDetector(
                            onTap: () {
                              ScaffoldMessenger.of(
                                context,
                              ).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.stop(stop.name))),
                              );
                            },
                            child: const Icon(
                              Icons.directions_bus,
                              color: Colors.blue,
                              size: Dimens.iconSizeSmall,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _showChatPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return BlocProvider(
          create: (_) => ChatBloc(),
          child: const ChatPanel(),
        );
      },
    );
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
