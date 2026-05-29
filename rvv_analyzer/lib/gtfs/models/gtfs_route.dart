import 'package:flutter/material.dart';

class GtfsRoute {
  final String id;
  final String shortName;
  final String longName;
  final Color color;

  GtfsRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.color,
  });

  factory GtfsRoute.fromCsv(List<dynamic> row, Map<String, int> headerIndex) {
    final colorHex = row[headerIndex['route_color']!]?.toString() ?? '0000FF';
    return GtfsRoute(
      id: row[headerIndex['route_id']!].toString(),
      shortName: row[headerIndex['route_short_name']!]?.toString() ?? '',
      longName: row[headerIndex['route_long_name']!]?.toString() ?? '',
      color: _parseColor(colorHex),
    );
  }

  static Color _parseColor(String hex) {
    try {
      if (hex.startsWith('#')) hex = hex.substring(1);
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }
}
