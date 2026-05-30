import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:ratisbonalyzer/src/core/assets.gen.dart';
import 'package:ratisbonalyzer/src/core/audio_utils.dart';
import 'package:ratisbonalyzer/src/core/l10n/app_localizations.dart';
import 'package:ratisbonalyzer/src/core/theme/dimens.dart';
import 'package:ratisbonalyzer/src/features/chat/bloc/chat_bloc.dart';
import 'package:ratisbonalyzer/src/features/chat/widgets/chat_panel.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/gtfs_service.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/rvv_record_service.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/gtfs_models.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/rvv_record.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/weather_record.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/weather_parser.dart';
import 'package:ratisbonalyzer/src/core/timezone_utils.dart';
import 'package:ratisbonalyzer/src/features/home/presentation/widgets/rvv_logo.dart';

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

class _BusPlaybackState {
  final String line;
  final String rotation;
  final int direction;
  final Color color;
  final LatLng position;
  final double bearing;
  final int? delaySeconds;

  _BusPlaybackState({
    required this.line,
    required this.rotation,
    required this.direction,
    required this.color,
    required this.position,
    required this.bearing,
    this.delaySeconds,
  });
}

class _PathInterpolationResult {
  final LatLng position;
  final double bearing;

  _PathInterpolationResult(this.position, this.bearing);
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
  bool _showBusLineLabels = true;
  bool _interpolateBuses = true;
  bool _showHeatmap = true;
  bool _showHeatmapDelays = true;
  bool _showHeatmapEarly = true;
  bool _showGlowEffect = true;
  bool _controlPanelExpanded = true;
  bool _chatPanelOpen = false;
  bool _chatButtonHovered = false;
  bool _tofuHovered = false;
  Timer? _tofuTimer;
  Set<String> _selectedRouteIds = {};

  List<String> _recFilesList = [];
  String? _selectedRecFile;
  List<DateTime> _selectedFileDays = [];
  DateTime? _selectedDay;
  List<RvvRecord> _selectedDayRecords = [];
  DateTime? _firstTimestamp;
  DateTime? _lastTimestamp;

  // Playback state variables
  Timer? _playbackTimer;
  bool _isPlaying = false;
  int _playbackSpeed = 10;
  DateTime? _currentPlaybackTime;
  Map<String, List<RvvRecord>> _busTimelines = {};
  List<_BusPlaybackState> _activeBuses = [];
  Map<String, Stop> _stopMapByName = {};
  Map<DateTime, WeatherRecord> _weatherRecords = {};
  bool _isDatasetLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _tofuTimer?.cancel();
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
        _rvvRecordService.listAllRecFiles(),
        rootBundle.loadString(Assets.weather.weatherRegensburgAll),
      ]);

      final stops = results[0] as List<Stop>;
      final routes = results[1] as List<RouteInfo>;
      final trips = results[2] as List<Trip>;
      final stopTimes = results[3] as List<StopTime>;
      final shapeMap = results[4] as Map<String, List<LatLng>>;
      final recFilesList = results[5] as List<String>;
      final weatherCsv = results[6] as String;
      final weatherRecords = WeatherParser.parseWeather(weatherCsv);

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
        final proposedLabels = <Marker>[];
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
                proposedLabels.add(
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

        // De-duplicate labels that are too close (within ~880 meters)
        final routeLabels = <Marker>[];
        for (var label in proposedLabels) {
          bool tooClose = false;
          for (var existing in routeLabels) {
            final dx = label.point.latitude - existing.point.latitude;
            final dy = label.point.longitude - existing.point.longitude;
            final distSq = dx * dx + dy * dy;
            if (distSq < 0.000064) {
              tooClose = true;
              break;
            }
          }
          if (!tooClose) {
            routeLabels.add(label);
          }
        }

        if (polylines.isNotEmpty) {
          allRoutes.add(
            _RouteData(
              routeId: routeId,
              shortName: shortName,
              color: color,
              polylines: polylines,
              labels: routeLabels,
              stopIds: allStopIds,
            ),
          );
        }
      }

      _stopMapByName = {for (var s in stops) s.name.trim().toLowerCase(): s};

      setState(() {
        _stops = stops;
        _allRoutes = allRoutes;
        _selectedRouteIds = allRoutes.map((r) => r.routeId).toSet();
        _recFilesList = recFilesList;
        _weatherRecords = weatherRecords;
        _selectedRecFile = recFilesList.isNotEmpty
            ? recFilesList.first
            : null;
      });

      if (_selectedRecFile != null) {
        await _loadSelectedFileAndDay();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading GTFS data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSelectedFileAndDay() async {
    final filename = _selectedRecFile;
    if (filename == null) return;

    setState(() {
      _isDatasetLoading = true;
    });

    try {
      await _rvvRecordService.cacheFile(filename, 'assets/rec/$filename');
      final days = await _rvvRecordService.getDaysForFile(filename);

      if (!mounted) return;

      DateTime? targetDay;
      if (days.isNotEmpty) {
        targetDay = days.first;
      }

      List<RvvRecord> dayRecords = [];
      if (targetDay != null) {
        dayRecords = await _rvvRecordService.getRecordsForDay(filename, targetDay);
      }

      if (!mounted) return;

      setState(() {
        _selectedFileDays = days;
        _selectedDay = targetDay;
        _selectedDayRecords = dayRecords;

        _updateTimestamps();
        _currentPlaybackTime = _firstTimestamp;
        _pregroupBusTimelines();
        _updateActiveBuses();

        _isDatasetLoading = false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dataset file $filename: $e');
      if (mounted) {
        setState(() {
          _isDatasetLoading = false;
          _isLoading = false;
        });
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
    return _selectedFileDays;
  }

  void _updateTimestamps() {
    if (_selectedRecFile == null || _selectedDay == null) {
      _firstTimestamp = null;
      _lastTimestamp = null;
      return;
    }
    final records = _selectedDayRecords;
    if (records.isEmpty) {
      _firstTimestamp = null;
      _lastTimestamp = null;
      return;
    }

    DateTime minT = records.first.arrivalHalt;
    DateTime maxT = records.first.departureHalt;
    for (var r in records) {
      if (r.arrivalHalt.isBefore(minT)) minT = r.arrivalHalt;
      if (r.departureHalt.isAfter(maxT)) maxT = r.departureHalt;
    }

    _firstTimestamp = minT;
    _lastTimestamp = maxT;
  }

  Future<void> _onRecFileChanged(String? newFile) async {
    if (newFile == null) return;
    _pausePlayback();
    setState(() {
      _selectedRecFile = newFile;
    });
    await _loadSelectedFileAndDay();
  }

  Future<void> _onDayChanged(DateTime? newDay) async {
    if (newDay == null || _selectedRecFile == null) return;
    _pausePlayback();

    setState(() {
      _isDatasetLoading = true;
    });

    try {
      final dayRecords = await _rvvRecordService.getRecordsForDay(_selectedRecFile!, newDay);

      if (!mounted) return;

      setState(() {
        _selectedDay = newDay;
        _selectedDayRecords = dayRecords;

        _updateTimestamps();
        _currentPlaybackTime = _firstTimestamp;
        _pregroupBusTimelines();
        _updateActiveBuses();

        _isDatasetLoading = false;
      });
    } catch (e) {
      debugPrint('Error changing day: $e');
      if (mounted) {
        setState(() {
          _isDatasetLoading = false;
        });
      }
    }
  }

  void _pregroupBusTimelines() {
    if (_selectedRecFile == null || _selectedDay == null) {
      _busTimelines = {};
      return;
    }
    final records = _selectedDayRecords;

    final timelines = <String, List<RvvRecord>>{};
    for (var r in records) {
      timelines.putIfAbsent(r.rotation, () => []).add(r);
    }
    for (var timeline in timelines.values) {
      timeline.sort((a, b) => a.arrivalHalt.compareTo(b.arrivalHalt));
    }
    _busTimelines = timelines;
  }

  LatLng? _getStopPosition(String stopName) {
    final key = stopName.trim().toLowerCase();
    final stop = _stopMapByName[key];
    if (stop != null) return stop.position;

    for (var entry in _stopMapByName.entries) {
      if (entry.key.contains(key) || key.contains(entry.key)) {
        return entry.value.position;
      }
    }
    return null;
  }

  double _distance(LatLng p1, LatLng p2) {
    final dLat = p2.latitude - p1.latitude;
    final dLon = p2.longitude - p1.longitude;
    return dLat * dLat + dLon * dLon;
  }

  double _realDistance(LatLng p1, LatLng p2) {
    final dLat = p2.latitude - p1.latitude;
    final dLon = p2.longitude - p1.longitude;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  double _calculateBearing(LatLng p1, LatLng p2) {
    final dLat = p2.latitude - p1.latitude;
    final dLon = p2.longitude - p1.longitude;
    return math.atan2(dLon, dLat) * 180 / math.pi;
  }

  Color _getRouteColor(String line) {
    for (var r in _allRoutes) {
      if (r.shortName == line || r.routeId == line) {
        return r.color;
      }
    }
    return Theme.of(context).colorScheme.primary;
  }

  List<LatLng> _getPathAlongPolyline(String line, LatLng start, LatLng end) {
    _RouteData? routeData;
    for (var r in _allRoutes) {
      if (r.shortName == line || r.routeId == line) {
        routeData = r;
        break;
      }
    }
    if (routeData == null || routeData.polylines.isEmpty) {
      return [];
    }

    List<LatLng>? bestPath;
    double bestDistanceSum = double.infinity;

    for (var polyline in routeData.polylines) {
      final points = polyline.points;
      if (points.length < 2) continue;

      int startIdx = -1;
      double minStartDist = double.infinity;
      int endIdx = -1;
      double minEndDist = double.infinity;

      for (int i = 0; i < points.length; i++) {
        final distToStart = _distance(points[i], start);
        if (distToStart < minStartDist) {
          minStartDist = distToStart;
          startIdx = i;
        }

        final distToEnd = _distance(points[i], end);
        if (distToEnd < minEndDist) {
          minEndDist = distToEnd;
          endIdx = i;
        }
      }

      if (startIdx != -1 && endIdx != -1) {
        if (minStartDist < 0.0002 && minEndDist < 0.0002) {
          final distanceSum = minStartDist + minEndDist;
          if (distanceSum < bestDistanceSum) {
            bestDistanceSum = distanceSum;

            if (startIdx <= endIdx) {
              bestPath = points.sublist(startIdx, endIdx + 1);
            } else {
              bestPath = points.sublist(endIdx, startIdx + 1).reversed.toList();
            }
          }
        }
      }
    }

    return bestPath ?? [];
  }

  _PathInterpolationResult _interpolateAlongPath(List<LatLng> path, double t) {
    if (path.isEmpty) {
      return _PathInterpolationResult(const LatLng(0, 0), 0.0);
    }
    if (path.length == 1) {
      return _PathInterpolationResult(path.first, 0.0);
    }

    final segmentDistances = <double>[];
    double totalDist = 0.0;

    for (int j = 0; j < path.length - 1; j++) {
      final d = _realDistance(path[j], path[j + 1]);
      segmentDistances.add(d);
      totalDist += d;
    }

    if (totalDist <= 0) {
      return _PathInterpolationResult(path.first, 0.0);
    }

    final targetDist = t * totalDist;
    double accumDist = 0.0;

    for (int j = 0; j < segmentDistances.length; j++) {
      final segLength = segmentDistances[j];
      if (accumDist + segLength >= targetDist) {
        final remaining = targetDist - accumDist;
        final segT = segLength > 0 ? remaining / segLength : 0.0;

        final p1 = path[j];
        final p2 = path[j + 1];

        final lat = p1.latitude + (p2.latitude - p1.latitude) * segT;
        final lon = p1.longitude + (p2.longitude - p1.longitude) * segT;

        return _PathInterpolationResult(
          LatLng(lat, lon),
          _calculateBearing(p1, p2),
        );
      }
      accumDist += segLength;
    }

    return _PathInterpolationResult(
      path.last,
      _calculateBearing(path[path.length - 2], path.last),
    );
  }

  void _updateActiveBuses() {
    if (_currentPlaybackTime == null) {
      _activeBuses = [];
      return;
    }

    final activeBuses = <_BusPlaybackState>[];

    _busTimelines.forEach((rotation, timeline) {
      if (timeline.isEmpty) return;

      final firstArr = timeline.first.arrivalHalt;
      final lastDep = timeline.last.departureHalt;

      if (_currentPlaybackTime!.isBefore(firstArr) ||
          _currentPlaybackTime!.isAfter(lastDep)) {
        return;
      }

      for (int i = 0; i < timeline.length; i++) {
        final record = timeline[i];

        if ((_currentPlaybackTime!.isAfter(record.arrivalHalt) &&
                _currentPlaybackTime!.isBefore(record.departureHalt)) ||
            _currentPlaybackTime!.isAtSameMomentAs(record.arrivalHalt) ||
            _currentPlaybackTime!.isAtSameMomentAs(record.departureHalt)) {
          final pos = _getStopPosition(record.stopName);
          if (pos != null) {
            double bearing = 0.0;
            if (i < timeline.length - 1) {
              final nextPos = _getStopPosition(timeline[i + 1].stopName);
              if (nextPos != null) {
                bearing = _calculateBearing(pos, nextPos);
              }
            }
            activeBuses.add(
              _BusPlaybackState(
                line: record.line,
                rotation: rotation,
                direction: record.direction,
                color: _getRouteColor(record.line),
                position: pos,
                bearing: bearing,
                delaySeconds:
                    record.scheduleDeviationDeparture ??
                    record.scheduleDeviationArrival,
              ),
            );
          }
          return;
        }

        if (i < timeline.length - 1) {
          final nextRecord = timeline[i + 1];
          if (_currentPlaybackTime!.isAfter(record.departureHalt) &&
              _currentPlaybackTime!.isBefore(nextRecord.arrivalHalt)) {
            if (!_interpolateBuses) {
              return;
            }

            final posI = _getStopPosition(record.stopName);
            final posNext = _getStopPosition(nextRecord.stopName);

            if (posI != null && posNext != null) {
              final depTime = record.departureHalt;
              final arrTime = nextRecord.arrivalHalt;
              final totalDuration = arrTime.difference(depTime).inMilliseconds;
              final elapsed = _currentPlaybackTime!
                  .difference(depTime)
                  .inMilliseconds;
              final t = totalDuration > 0 ? elapsed / totalDuration : 0.0;

              final polylinePoints = _getPathAlongPolyline(
                record.line,
                posI,
                posNext,
              );

              LatLng pos;
              double bearing;

              if (polylinePoints.length >= 2) {
                final result = _interpolateAlongPath(polylinePoints, t);
                pos = result.position;
                bearing = result.bearing;
              } else {
                final lat =
                    posI.latitude + (posNext.latitude - posI.latitude) * t;
                final lon =
                    posI.longitude + (posNext.longitude - posI.longitude) * t;
                pos = LatLng(lat, lon);
                bearing = _calculateBearing(posI, posNext);
              }

              activeBuses.add(
                _BusPlaybackState(
                  line: record.line,
                  rotation: rotation,
                  direction: record.direction,
                  color: _getRouteColor(record.line),
                  position: pos,
                  bearing: bearing,
                  delaySeconds:
                      record.scheduleDeviationDeparture ??
                      record.scheduleDeviationArrival,
                ),
              );
            }
            return;
          }
        }
      }
    });

    _activeBuses = activeBuses;
  }

  void _startPlayback() {
    if (_playbackTimer != null) return;
    if (_currentPlaybackTime != null &&
        _lastTimestamp != null &&
        _firstTimestamp != null) {
      if (_currentPlaybackTime!.isAfter(_lastTimestamp!) ||
          _currentPlaybackTime!.isAtSameMomentAs(_lastTimestamp!)) {
        _currentPlaybackTime = _firstTimestamp;
      }
    }
    setState(() {
      _isPlaying = true;
    });
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_currentPlaybackTime == null ||
          _firstTimestamp == null ||
          _lastTimestamp == null) {
        _stopPlayback();
        return;
      }
      final advanceSeconds = 3 * _playbackSpeed; // 50ms tick
      final newTime = _currentPlaybackTime!.add(
        Duration(seconds: advanceSeconds),
      );
      if (newTime.isAfter(_lastTimestamp!)) {
        _pausePlayback();
        setState(() {
          _currentPlaybackTime = _lastTimestamp;
          _updateActiveBuses();
        });
      } else {
        setState(() {
          _currentPlaybackTime = newTime;
          _updateActiveBuses();
        });
      }
    });
  }

  void _pausePlayback() {
    if (_playbackTimer == null) return;
    _playbackTimer!.cancel();
    _playbackTimer = null;
    setState(() {
      _isPlaying = false;
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    setState(() {
      _isPlaying = false;
      _currentPlaybackTime = _firstTimestamp;
      _updateActiveBuses();
    });
  }

  void _onSliderChanged(double value) {
    if (_firstTimestamp == null || _lastTimestamp == null) return;
    final total = _lastTimestamp!.difference(_firstTimestamp!).inSeconds;
    final elapsed = (value * total).round();
    setState(() {
      _currentPlaybackTime = _firstTimestamp!.add(Duration(seconds: elapsed));
      _updateActiveBuses();
    });
  }

  Color _getDelayColor(int delaySeconds) {
    if (delaySeconds <= 30) return Colors.green;
    if (delaySeconds <= 180) return Colors.orange;
    return Colors.red;
  }

  List<CircleMarker> _getHeatmapCircles() {
    if (!_showHeatmap ||
        _currentPlaybackTime == null ||
        _selectedRecFile == null ||
        _selectedDay == null) {
      return [];
    }

    final dayRecords = _selectedDayRecords;

    final circles = <CircleMarker>[];
    final fifteenMinutesAgo = _currentPlaybackTime!.subtract(const Duration(minutes: 15));

    for (var record in dayRecords) {
      if (record.arrivalHalt.isAfter(fifteenMinutesAgo) &&
          (record.arrivalHalt.isBefore(_currentPlaybackTime!) ||
              record.arrivalHalt.isAtSameMomentAs(_currentPlaybackTime!))) {
        final arrDev = record.scheduleDeviationArrival;
        final depDev = record.scheduleDeviationDeparture;

        final lateSeconds = arrDev ?? 0;
        final earlySeconds = depDev ?? 0;

        if (lateSeconds > 30 && _showHeatmapDelays) {
          final isBigger = lateSeconds > 180;
          final pos = _getStopPosition(record.stopName);
          if (pos != null) {
            circles.add(
              CircleMarker(
                point: pos,
                radius: isBigger ? 250.0 : 125.0,
                useRadiusInMeter: true,
                color: Colors.orange.shade700.withValues(alpha: 0.35),
                borderColor: Colors.orange.shade700.withValues(alpha: 0.6),
                borderStrokeWidth: 1.5,
              ),
            );
          }
        } else if (earlySeconds < -30 && _showHeatmapEarly) {
          final absDev = earlySeconds.abs();
          final isBigger = absDev > 180;
          final pos = _getStopPosition(record.stopName);
          if (pos != null) {
            circles.add(
              CircleMarker(
                point: pos,
                radius: isBigger ? 250.0 : 125.0,
                useRadiusInMeter: true,
                color: Colors.cyan.shade600.withValues(alpha: 0.35),
                borderColor: Colors.cyan.shade600.withValues(alpha: 0.6),
                borderStrokeWidth: 1.5,
              ),
            );
          }
        }
      }
    }
    return circles;
  }

  double get _playbackProgress {
    if (_currentPlaybackTime == null ||
        _firstTimestamp == null ||
        _lastTimestamp == null) {
      return 0.0;
    }
    final total = _lastTimestamp!.difference(_firstTimestamp!).inSeconds;
    if (total <= 0) return 0.0;
    final elapsed = _currentPlaybackTime!
        .difference(_firstTimestamp!)
        .inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  WeatherRecord? get _currentWeather {
    if (_currentPlaybackTime == null || _weatherRecords.isEmpty) return null;

    // Convert playback time (German local) to UTC
    final utcTime = TimezoneUtils.convertGermanLocalToUtc(_currentPlaybackTime!);

    // Find closest hourly weather record
    final target = DateTime.utc(utcTime.year, utcTime.month, utcTime.day, utcTime.hour);
    final direct = _weatherRecords[target];
    if (direct != null) return direct;

    // Fallback 1: check offset by 1 hour backwards
    final prev = _weatherRecords[target.subtract(const Duration(hours: 1))];
    if (prev != null) return prev;

    // Fallback 2: check offset by 1 hour forwards
    final next = _weatherRecords[target.add(const Duration(hours: 1))];
    if (next != null) return next;

    return null;
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

    return Stack(
      children: [
        Scaffold(
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
                  if (_showHeatmap)
                    CircleLayer(circles: _getHeatmapCircles()),
                  if (_showBusLines)
                    PolylineLayer(polylines: _filteredPolylines),
                  if (_showBusLines &&
                      _showBusLineLabels &&
                      _currentZoom >= _initialZoom)
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
                  // Live bus markers layer
                  MarkerLayer(
                    markers: _activeBuses.map((bus) {
                      final delayColor = _getDelayColor(bus.delaySeconds ?? 0);
                      return Marker(
                        point: bus.position,
                        width: 32.0,
                        height: 32.0,
                        alignment: Alignment.center,
                        child: Tooltip(
                          message:
                              'Line ${bus.line}\nUmlauf: ${bus.rotation}\nDelay: ${bus.delaySeconds != null ? "${(bus.delaySeconds! / 60).round()}m" : "N/A"}',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: bus.color,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.0,
                              ),
                              boxShadow: [
                                if (_showGlowEffect) ...[
                                  BoxShadow(
                                    color: delayColor.withValues(alpha: 0.95),
                                    blurRadius: 8.0,
                                    spreadRadius: 3.5,
                                  ),
                                  BoxShadow(
                                    color: delayColor.withValues(alpha: 0.85),
                                    blurRadius: 25.0,
                                    spreadRadius: 10.0,
                                  ),
                                ],
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 2.0,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                bus.line,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (!_isLoading && _weatherRecords.isNotEmpty)
            Positioned(
              top: 16,
              right: 16,
              child: _WeatherOverlay(weather: _currentWeather),
            ),Positioned(
                top: 16,
                left: 16,
                child: _controlPanelExpanded
                    ? Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 460,
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
                                      InkWell(
                                        onTap: () => setState(
                                          () => _controlPanelExpanded = false,
                                        ),
                                        child: const Icon(
                                          Icons.chevron_left,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.controlPanelTitle,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.route, size: 18),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Bus Lines',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _showBusLines,
                                            onChanged: (v) => setState(
                                              () => _showBusLines = v,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.directions_bus,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Bus Stops',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _showBusStops,
                                            onChanged: (v) => setState(
                                              () => _showBusStops = v,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.label_outline, size: 18),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Line Labels',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _showBusLineLabels,
                                            onChanged: (v) => setState(
                                              () => _showBusLineLabels = v,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.linear_scale, size: 18),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Interpolate',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _interpolateBuses,
                                            onChanged: (v) {
                                              setState(() {
                                                _interpolateBuses = v;
                                                _updateActiveBuses();
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.blur_on, size: 18),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Glow Effect',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _showGlowEffect,
                                            onChanged: (v) {
                                              setState(() {
                                                _showGlowEffect = v;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.map_outlined, size: 18),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Heatmap',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 28,
                                        width: 44,
                                        child: FittedBox(
                                          child: Switch(
                                            value: _showHeatmap,
                                            onChanged: (v) {
                                              setState(() {
                                                _showHeatmap = v;
                                              });
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showHeatmap) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.circle, size: 12, color: Colors.orange),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Show Delays',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          const Spacer(),
                                          SizedBox(
                                            height: 24,
                                            width: 36,
                                            child: FittedBox(
                                              child: Switch(
                                                value: _showHeatmapDelays,
                                                onChanged: (v) {
                                                  setState(() {
                                                    _showHeatmapDelays = v;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.circle, size: 12, color: Colors.cyan),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Show Early',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                          const Spacer(),
                                          SizedBox(
                                            height: 24,
                                            width: 36,
                                            child: FittedBox(
                                              child: Switch(
                                                value: _showHeatmapEarly,
                                                onChanged: (v) {
                                                  setState(() {
                                                    _showHeatmapEarly = v;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
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
                                            decoration:
                                                TextDecoration.underline,
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
                                            decoration:
                                                TextDecoration.underline,
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
                                      final selected = _selectedRouteIds
                                          .contains(route.routeId);
                                      return GestureDetector(
                                        onTap: () =>
                                            _toggleRoute(route.routeId),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? route.color
                                                : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
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
                          onTap: () =>
                              setState(() => _controlPanelExpanded = true),
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
                  bottom: 148,
                  width: chatPanelWidth,
                  child: BlocProvider.value(
                    value: _chatBloc,
                    child: ChatPanel(
                      height: chatPanelHeight,
                      onClose: _closeChatPanel,
                    ),
                  ),
                ),
              if (!_isLoading && _recFilesList.isNotEmpty)
                Positioned(
                  left: 16,
                  right: 140,
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
                                _currentPlaybackTime != null
                                    ? 'Playback: ${DateFormat('HH:mm:ss').format(_currentPlaybackTime!)}'
                                    : 'Playback Controls',
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
                                    items: _recFilesList.map((filename) {
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
                                    items: _getDaysForSelectedDataset().map((
                                      day,
                                    ) {
                                      return DropdownMenuItem<DateTime>(
                                        value: day,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          child: Text(
                                            DateFormat(
                                              'dd.MM.yyyy',
                                            ).format(day),
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
                          const SizedBox(height: 12),
                          // Play/Pause, Progress Bar, and Speed Selection Row
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                ),
                                iconSize: 36,
                                color: theme.colorScheme.primary,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_isPlaying) {
                                    _pausePlayback();
                                  } else {
                                    _startPlayback();
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
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
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    activeTrackColor: theme.colorScheme.primary,
                                    inactiveTrackColor: theme
                                        .colorScheme
                                        .primary
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
                                    disabledThumbColor: theme
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.5),
                                  ),
                                  child: Slider(
                                    value: _playbackProgress,
                                    onChanged: _onSliderChanged,
                                  ),
                                ),
                              ),
                              Text(
                                _lastTimestamp != null
                                    ? DateFormat(
                                        'HH:mm:ss',
                                      ).format(_lastTimestamp!)
                                    : '--:--:--',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Speed Selection
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
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
                                  child: DropdownButton<int>(
                                    value: _playbackSpeed,
                                    icon: const Icon(Icons.speed, size: 14),
                                    isDense: true,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    focusColor: Colors.transparent,
                                    items: List.generate(30, (i) => i + 1).map((
                                      speed,
                                    ) {
                                      return DropdownMenuItem<int>(
                                        value: speed,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4.0,
                                          ),
                                          child: Text('${speed}x'),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _playbackSpeed = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                right: 20,
                bottom: 70 - (_chatButtonHovered ? 48 : 42),
                child: MouseRegion(
                  onEnter: (_) => setState(() => _chatButtonHovered = true),
                  onExit: (_) => setState(() => _chatButtonHovered = false),
                  child: Tooltip(
                    message: 'Ask me anything!',
                    preferBelow: false,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      width: _chatButtonHovered ? 96 : 84,
                      height: _chatButtonHovered ? 96 : 84,
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
              if (_isDatasetLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Center(
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Optimizing & caching dataset...',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'This will only happen once per dataset.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Mr. Tofu peeking graphic
        Positioned(
          right: -40,
          top: 8,
          child: IgnorePointer(
            child: AnimatedRotation(
              turns: _tofuHovered ? -70 / 360 : 0,
              alignment: Alignment.bottomLeft,
              duration: const Duration(seconds: 2),
              curve: Curves.easeOut,
              child: Assets.img.tofu.image(width: 40, height: 40),
            ),
          ),
        ),
        // Invisible hover trigger region over the toolbar right corner
        Positioned(
          top: 0,
          right: 0,
          width: 50,
          height: 56,
          child: MouseRegion(
            onEnter: (_) {
              if (!_tofuHovered) {
                setState(() {
                  _tofuHovered = true;
                });
                playBoingSound();
                _tofuTimer?.cancel();
                _tofuTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted) {
                    setState(() {
                      _tofuHovered = false;
                    });
                  }
                });
              }
            },
            child: Container(color: Colors.transparent),
          ),
        ),
      ],
    );
  }
}

class _WeatherOverlay extends StatelessWidget {
  final WeatherRecord? weather;

  const _WeatherOverlay({required this.weather});

  @override
  Widget build(BuildContext context) {
    if (weather == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      color: theme.colorScheme.surface.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(maxWidth: 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: weather!.conditionColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    weather!.conditionIcon,
                    color: weather!.conditionColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${weather!.temp.toStringAsFixed(1)}°C',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        weather!.conditionDescription,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (weather!.rhum != null ||
                weather!.wspd != null ||
                (weather!.prcp != null && weather!.prcp! > 0)) ...[
              const Divider(height: 16, thickness: 1),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (weather!.rhum != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop_outlined,
                          size: 13,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${weather!.rhum!.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  if (weather!.wspd != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.air_outlined,
                          size: 13,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${weather!.wspd!.toStringAsFixed(0)} km/h',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  if (weather!.prcp != null && weather!.prcp! > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.umbrella_outlined,
                          size: 13,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${weather!.prcp!.toStringAsFixed(1)} mm',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
