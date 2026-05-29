// dart format width=80

/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: deprecated_member_use,directives_ordering,implicit_dynamic_list_literal,unnecessary_import

class $AssetsGtfsGen {
  const $AssetsGtfsGen();

  /// File path: assets/gtfs/routes.txt
  String get routes => 'assets/gtfs/routes.txt';

  /// File path: assets/gtfs/shapes.txt
  String get shapes => 'assets/gtfs/shapes.txt';

  /// File path: assets/gtfs/stop_times.txt
  String get stopTimes => 'assets/gtfs/stop_times.txt';

  /// File path: assets/gtfs/stops.txt
  String get stops => 'assets/gtfs/stops.txt';

  /// File path: assets/gtfs/trips.txt
  String get trips => 'assets/gtfs/trips.txt';

  /// List of all assets
  List<String> get values => [routes, shapes, stopTimes, stops, trips];
}

class $AssetsRecGen {
  const $AssetsRecGen();

  /// File path: assets/rec/october_2024.csv
  String get october2024 => 'assets/rec/october_2024.csv';

  /// List of all assets
  List<String> get values => [october2024];
}

class $AssetsWeatherGen {
  const $AssetsWeatherGen();

  /// File path: assets/weather/weather_regensburg_all.csv
  String get weatherRegensburgAll =>
      'assets/weather/weather_regensburg_all.csv';

  /// List of all assets
  List<String> get values => [weatherRegensburgAll];
}

class Assets {
  const Assets._();

  static const $AssetsGtfsGen gtfs = $AssetsGtfsGen();
  static const $AssetsRecGen rec = $AssetsRecGen();
  static const $AssetsWeatherGen weather = $AssetsWeatherGen();
}
