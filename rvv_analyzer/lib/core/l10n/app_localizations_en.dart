// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'R.A.T. (RVV Analyzing Tool)';

  @override
  String get filterBusLines => 'Filter Bus Lines';

  @override
  String get all => 'All';

  @override
  String get none => 'None';

  @override
  String line(String lineName) {
    return 'Line $lineName';
  }

  @override
  String stop(String stopName) {
    return 'Stop: $stopName';
  }

  @override
  String errorLoadingGtfs(String error) {
    return 'Error loading GTFS data: $error';
  }
}
