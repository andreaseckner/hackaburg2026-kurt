import 'package:latlong2/latlong.dart';

class GtfsStop {
  final String id;
  final String name;
  final LatLng location;

  GtfsStop({required this.id, required this.name, required this.location});

  factory GtfsStop.fromCsv(List<dynamic> row, Map<String, int> headerIndex) {
    return GtfsStop(
      id: row[headerIndex['stop_id']!].toString(),
      name: row[headerIndex['stop_name']!].toString(),
      location: LatLng(
        double.parse(row[headerIndex['stop_lat']!].toString()),
        double.parse(row[headerIndex['stop_lon']!].toString()),
      ),
    );
  }
}
