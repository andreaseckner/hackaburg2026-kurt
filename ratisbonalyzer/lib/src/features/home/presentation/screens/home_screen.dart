import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ratisbonalyzer/src/core/assets.gen.dart';
import 'package:ratisbonalyzer/src/core/l10n/app_localizations.dart';
import 'package:ratisbonalyzer/src/core/theme/dimens.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/widgets/chat_panel.dart';
import 'package:ratisbonalyzer/src/features/home/presentation/widgets/rvv_logo.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/gtfs_service.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/rvv_record_service.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/gtfs_models.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/rvv_record.dart';

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
  final RvvRecordService _rvvRecordService = RvvRecordService();
  final MapController _mapController = MapController();
  final ChatBloc _chatBloc = ChatBloc();
  double _currentZoom = _initialZoom;

  List<Stop> _stops = [];
  List<_RouteData> _allRoutes = [];
  bool _isLoading = true;
  bool _showBusLines = true;
  bool _showBusStops = true;
  bool _controlPanelExpanded = true;
  bool _chatPanelOpen = false;
  bool _chatButtonHovered = false;
  Set<String> _selectedRouteIds = {};

  Map<String, List<RvvRecord>> _recFiles = {};
  String? _selectedRecFile;
  DateTime? _selectedDay;
  DateTime? _firstTimestamp;
  DateTime? _lastTimestamp;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _chatBloc.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _gtfsService.loadStops(),
        _gtfsService.loadRoutes(),
        _gtfsService.loadTrips(),
        _gtfsService.loadStopTimes(),
        _gtfsService.loadShapes(),
        _rvvRecordService.loadAllRecFiles(),
      ]);

      final stops = results[0] as List<Stop>;
      final routes = results[1] as List<RouteInfo>;
      final trips = results[2] as List<Trip>;
      final stopTimes = results[3] as List<StopTime>;
      final shapeMap = results[4] as Map<String, List<LatLng>>;
      final recFiles = results[5] as Map<String, List<RvvRecord>>;

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
        _recFiles = recFiles;
        _selectedRecFile = recFiles.keys.isNotEmpty
            ? recFiles.keys.first
            : null;
        _isLoading = false;

        if (_selectedRecFile != null) {
          final days = _getDaysForSelectedDataset();
          if (days.isNotEmpty) {
            _selectedDay = days.first;
            _updateTimestamps();
          }
        }
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

  void _toggleChatPanel() {
    setState(() => _chatPanelOpen = !_chatPanelOpen);
  }

  void _closeChatPanel() {
    setState(() => _chatPanelOpen = false);
  }

  List<DateTime> _getDaysForSelectedDataset() {
    if (_selectedRecFile == null || !_recFiles.containsKey(_selectedRecFile)) {
      return [];
    }
    final records = _recFiles[_selectedRecFile]!;
    final days = records.map((r) => r.operationDay).toSet().toList();
    days.sort();
    return days;
  }

  void _updateTimestamps() {
    if (_selectedRecFile == null || _selectedDay == null) {
      _firstTimestamp = null;
      _lastTimestamp = null;
      return;
    }
    final records = _recFiles[_selectedRecFile]!;
    final dayRecords = records
        .where((r) => r.operationDay == _selectedDay)
        .toList();
    if (dayRecords.isEmpty) {
      _firstTimestamp = null;
      _lastTimestamp = null;
      return;
    }

    DateTime minT = dayRecords.first.arrivalHalt;
    DateTime maxT = dayRecords.first.departureHalt;
    for (var r in dayRecords) {
      if (r.arrivalHalt.isBefore(minT)) minT = r.arrivalHalt;
      if (r.departureHalt.isAfter(maxT)) maxT = r.departureHalt;
    }

    _firstTimestamp = minT;
    _lastTimestamp = maxT;
  }

  void _onRecFileChanged(String? newFile) {
    if (newFile == null) return;
    setState(() {
      _selectedRecFile = newFile;
      final days = _getDaysForSelectedDataset();
      if (days.isNotEmpty) {
        _selectedDay = days.first;
      } else {
        _selectedDay = null;
      }
      _updateTimestamps();
    });
  }

  void _onDayChanged(DateTime? newDay) {
    if (newDay == null) return;
    setState(() {
      _selectedDay = newDay;
      _updateTimestamps();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final screenSize = MediaQuery.sizeOf(context);
    final chatPanelWidth = screenSize.width < 460
        ? screenSize.width - 32
        : 420.0;
    final chatPanelHeight = screenSize.height < 680
        ? screenSize.height - 160
        : 540.0;

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
          if (_chatPanelOpen)
            Positioned(
              right: 16,
              bottom: 88,
              width: chatPanelWidth,
              child: BlocProvider.value(
                value: _chatBloc,
                child: ChatPanel(
                  height: chatPanelHeight,
                  onClose: _closeChatPanel,
                ),
              ),
            ),
          if (!_isLoading && _recFiles.isNotEmpty)
            Positioned(
              left: 16,
              right: 104,
              bottom: 16,
              child: Card(
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.tune_outlined,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Playback Controls',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedRecFile,
                                icon: const Icon(Icons.arrow_drop_down),
                                isDense: true,
                                focusColor: Colors.transparent,
                                items: _recFiles.keys.map((filename) {
                                  return DropdownMenuItem<String>(
                                    value: filename,
                                    child: Text(
                                      filename,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: _onRecFileChanged,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<DateTime>(
                                value: _selectedDay,
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 14,
                                ),
                                isDense: true,
                                focusColor: Colors.transparent,
                                items: _getDaysForSelectedDataset().map((day) {
                                  return DropdownMenuItem<DateTime>(
                                    value: day,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8.0,
                                      ),
                                      child: Text(
                                        DateFormat('dd.MM.yyyy').format(day),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: _onDayChanged,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            _firstTimestamp != null
                                ? DateFormat(
                                    'HH:mm:ss',
                                  ).format(_firstTimestamp!)
                                : '--:--:--',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 4,
                                activeTrackColor: theme.colorScheme.primary,
                                inactiveTrackColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.12),
                                thumbColor: theme.colorScheme.primary,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                disabledActiveTrackColor: theme
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.4),
                                disabledInactiveTrackColor: theme
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12),
                                disabledThumbColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.5),
                              ),
                              child: const Slider(value: 0.0, onChanged: null),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _lastTimestamp != null
                                ? DateFormat('HH:mm:ss').format(_lastTimestamp!)
                                : '--:--:--',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 20,
            bottom: 20,
            child: MouseRegion(
              onEnter: (_) => setState(() => _chatButtonHovered = true),
              onExit: (_) => setState(() => _chatButtonHovered = false),
              child: Tooltip(
                message: 'Ask me anything!',
                preferBelow: false,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: _chatButtonHovered ? 76 : 64,
                  height: _chatButtonHovered ? 76 : 64,
                  child: Material(
                    color: theme.colorScheme.surface,
                    shape: CircleBorder(
                      side: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    elevation: _chatButtonHovered ? 12 : 8,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _toggleChatPanel,
                      child: Image.asset(
                        'assets/img/kurt.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
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
