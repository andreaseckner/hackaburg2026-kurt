import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ratisbonalyzer/src/core/assets.gen.dart';
import 'package:ratisbonalyzer/src/core/l10n/app_localizations.dart';
import 'package:ratisbonalyzer/src/core/theme/dimens.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/widgets/chat_panel.dart';
import 'package:ratisbonalyzer/src/features/home/presentation/widgets/rvv_logo.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/gtfs_service.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/gtfs_models.dart';

class _RouteData {
  final String routeId;
  final String shortName;
  final Color color;
  final List<Polyline> polylines;
  final List<Marker> labels;
  final Set<String> stopIds;

  _RouteData({
    required this.routeId,
    required this.shortName,
    required this.color,
    required this.polylines,
    required this.labels,
    required this.stopIds,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Map Config
  static const LatLng _initialCenter = LatLng(49.0134, 12.1016);
  static const double _initialZoom = 14.0;
  static const String _osmUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String _userAgentPackage = 'de.rvv.ratisbonalyzer';

  // UI Styling
  static const double _stopMarkerSize = 24.0;

  final GtfsService _gtfsService = GtfsService();
  final MapController _mapController = MapController();
  double _currentZoom = _initialZoom;

  List<Stop> _stops = [];
  List<_RouteData> _allRoutes = [];
  bool _isLoading = true;
  bool _showBusLines = true;
  bool _showBusStops = true;
  bool _controlPanelExpanded = true;
  Set<String> _selectedRouteIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final stops = await _gtfsService.loadStops();
      final routes = await _gtfsService.loadRoutes();
      final trips = await _gtfsService.loadTrips();
      final stopTimes = await _gtfsService.loadStopTimes();
      final shapeMap = await _gtfsService.loadShapes();

      if (!mounted) return;

      // Build tripId -> stop IDs for filtering
      final tripStopIds = <String, Set<String>>{};
      for (var st in stopTimes) {
        tripStopIds.putIfAbsent(st.tripId, () => {}).add(st.stopId);
      }

      final routeColors = {for (var r in routes) r.id: r.color};
      final routeShortNames = {for (var r in routes) r.id: r.shortName};
      final primaryColor = Theme.of(context).colorScheme.primary;

      final allRoutes = <_RouteData>[];

      // Group trips by route
      final tripsByRoute = <String, List<Trip>>{};
      for (var trip in trips) {
        tripsByRoute.putIfAbsent(trip.routeId, () => []).add(trip);
      }

      for (var routeEntry in tripsByRoute.entries) {
        final routeId = routeEntry.key;
        final routeTrips = routeEntry.value;

        final colorStr = routeColors[routeId];
        final color = colorStr != null && colorStr.isNotEmpty
            ? Color(int.parse('0xFF$colorStr'))
            : primaryColor.withAlpha(178);
        final shortName = routeShortNames[routeId] ?? '';

        final allStopIds = <String>{};
        final polylines = <Polyline>[];
        final labels = <Marker>[];
        final seenShapeIds = <String>{};

        for (var trip in routeTrips) {
          // Collect stop IDs for this trip
          final stopIds = tripStopIds[trip.id];
          if (stopIds != null) {
            allStopIds.addAll(stopIds);
          }

          // Use shape for polyline
          final shapeId = trip.shapeId;
          if (shapeId != null && !seenShapeIds.contains(shapeId)) {
            seenShapeIds.add(shapeId);
            final points = shapeMap[shapeId];
            if (points != null && points.length >= 2) {
              polylines.add(
                Polyline(points: points, strokeWidth: 3.0, color: color),
              );

              // Place a label at the midpoint of the shape
              if (shortName.isNotEmpty) {
                final midIdx = points.length ~/ 2;
                labels.add(
                  Marker(
                    point: points[midIdx],
                    width: 30,
                    height: 18,
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shortName,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.visible,
                        maxLines: 1,
                      ),
                    ),
                  ),
                );
              }
            }
          }
        }

        if (polylines.isNotEmpty) {
          allRoutes.add(
            _RouteData(
              routeId: routeId,
              shortName: shortName,
              color: color,
              polylines: polylines,
              labels: labels,
              stopIds: allStopIds,
            ),
          );
        }
      }

      setState(() {
        _stops = stops;
        _allRoutes = allRoutes;
        _selectedRouteIds = allRoutes.map((r) => r.routeId).toSet();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading GTFS data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Polyline> get _filteredPolylines => _allRoutes
      .where((r) => _selectedRouteIds.contains(r.routeId))
      .expand((r) => r.polylines)
      .toList();

  List<Marker> get _filteredLabels => _allRoutes
      .where((r) => _selectedRouteIds.contains(r.routeId))
      .expand((r) => r.labels)
      .toList();

  List<Stop> get _filteredStops {
    if (_selectedRouteIds.length == _allRoutes.length) return _stops;
    final ids = _allRoutes
        .where((r) => _selectedRouteIds.contains(r.routeId))
        .expand((r) => r.stopIds)
        .toSet();
    return _stops.where((s) => ids.contains(s.id)).toList();
  }

  void _selectAllRoutes() {
    setState(() {
      _selectedRouteIds = _allRoutes.map((r) => r.routeId).toSet();
    });
  }

  void _selectNoRoutes() {
    setState(() {
      _selectedRouteIds = {};
    });
  }

  void _toggleRoute(String routeId) {
    setState(() {
      if (_selectedRouteIds.contains(routeId)) {
        _selectedRouteIds.remove(routeId);
      } else {
        _selectedRouteIds.add(routeId);
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        leadingWidth: Dimens.appBarLeadingWidth,
        leading: const Padding(
          padding: EdgeInsets.symmetric(
            vertical: Dimens.paddingSmall,
            horizontal: Dimens.paddingMedium,
          ),
          child: RvvLogo(height: Dimens.rvvLogoHeight),
        ),
        title: Text(
          l10n.appTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => _showChatPanel(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              onPositionChanged: (position, hasGesture) {
                if (position.zoom != _currentZoom) {
                  setState(() {
                    _currentZoom = position.zoom;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _osmUrlTemplate,
                userAgentPackageName: _userAgentPackage,
              ),
              if (_showBusLines) PolylineLayer(polylines: _filteredPolylines),
              if (_showBusLines && _currentZoom >= _initialZoom)
                MarkerLayer(markers: _filteredLabels),
              if (_showBusStops)
                MarkerLayer(
                  markers: _filteredStops.map((stop) {
                    return Marker(
                      point: stop.position,
                      width: _stopMarkerSize,
                      height: _stopMarkerSize,
                      alignment: Alignment.center,
                      child: Tooltip(
                        message: stop.name,
                        child: Assets.img.busStop.svg(),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: _controlPanelExpanded
                ? Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 400,
                        maxWidth: 220,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.controlPanelTitle,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => setState(
                                      () => _controlPanelExpanded = false,
                                    ),
                                    child: const Icon(
                                      Icons.chevron_right,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.route, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Bus Lines',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 28,
                                    width: 44,
                                    child: FittedBox(
                                      child: Switch(
                                        value: _showBusLines,
                                        onChanged: (v) =>
                                            setState(() => _showBusLines = v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.directions_bus, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Bus Stops',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 28,
                                    width: 44,
                                    child: FittedBox(
                                      child: Switch(
                                        value: _showBusStops,
                                        onChanged: (v) =>
                                            setState(() => _showBusStops = v),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Filter',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _selectAllRoutes,
                                    child: const Text(
                                      'All',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: _selectNoRoutes,
                                    child: const Text(
                                      'None',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: _allRoutes.map((route) {
                                  final selected = _selectedRouteIds.contains(
                                    route.routeId,
                                  );
                                  return GestureDetector(
                                    onTap: () => _toggleRoute(route.routeId),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? route.color
                                            : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: route.color,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        route.shortName,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: selected
                                              ? Colors.white
                                              : route.color,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _controlPanelExpanded = true),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.layers, size: 22),
                      ),
                    ),
                  ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
