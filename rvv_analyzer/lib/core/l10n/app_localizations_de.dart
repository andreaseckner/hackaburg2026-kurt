// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'R.A.T. (RVV Analyzing Tool)';

  @override
  String get filterBusLines => 'Buslinien filtern';

  @override
  String get all => 'Alle';

  @override
  String get none => 'Keine';

  @override
  String line(String lineName) {
    return 'Linie $lineName';
  }

  @override
  String stop(String stopName) {
    return 'Haltestelle: $stopName';
  }

  @override
  String errorLoadingGtfs(String error) {
    return 'Fehler beim Laden der GTFS-Daten: $error';
  }
}
