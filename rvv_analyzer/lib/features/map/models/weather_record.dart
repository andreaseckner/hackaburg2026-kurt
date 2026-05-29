import 'package:flutter/material.dart';

class WeatherRecord {
  final DateTime time; // UTC time
  final double temp;
  final double? dwpt;
  final double? rhum;
  final double? prcp;
  final double? snow;
  final double? wdir;
  final double? wspd;
  final double? wpgt;
  final double? pres;
  final double? tsun;
  final int? coco;

  WeatherRecord({
    required this.time,
    required this.temp,
    this.dwpt,
    this.rhum,
    this.prcp,
    this.snow,
    this.wdir,
    this.wspd,
    this.wpgt,
    this.pres,
    this.tsun,
    this.coco,
  });

  String get conditionDescription {
    switch (coco) {
      case 1: return 'Clear';
      case 2: return 'Fair';
      case 3: return 'Cloudy';
      case 4: return 'Overcast';
      case 5: return 'Fog';
      case 6: return 'Freezing Fog';
      case 7: return 'Light Rain';
      case 8: return 'Rain';
      case 9: return 'Heavy Rain';
      case 10: return 'Freezing Rain';
      case 11: return 'Heavy Freezing Rain';
      case 12: return 'Sleet';
      case 13: return 'Heavy Sleet';
      case 14: return 'Light Snowfall';
      case 15: return 'Snowfall';
      case 16: return 'Heavy Snowfall';
      case 17: return 'Rain Shower';
      case 18: return 'Heavy Rain Shower';
      case 19: return 'Sleet Shower';
      case 20: return 'Heavy Sleet Shower';
      case 21: return 'Snow Shower';
      case 22: return 'Heavy Snow Shower';
      case 23: return 'Lightning';
      case 24: return 'Hail';
      case 25: return 'Thunderstorm';
      case 26: return 'Heavy Thunderstorm';
      case 27: return 'Storm';
      default: return 'Unknown';
    }
  }

  IconData get conditionIcon {
    switch (coco) {
      case 1:
      case 2:
        return Icons.wb_sunny;
      case 3:
        return Icons.wb_cloudy;
      case 4:
        return Icons.cloud;
      case 5:
      case 6:
        return Icons.foggy;
      case 7:
      case 8:
      case 9:
      case 17:
      case 18:
        return Icons.umbrella; // umbrella is very premium for rain
      case 10:
      case 11:
      case 12:
      case 13:
      case 19:
      case 20:
      case 14:
      case 15:
      case 16:
      case 21:
      case 22:
        return Icons.ac_unit; // Snow / Sleet
      case 23:
      case 25:
      case 26:
        return Icons.thunderstorm; // Thunderstorm
      case 24:
        return Icons.grain; // Hail
      case 27:
        return Icons.cyclone; // Storm
      default:
        return Icons.help_outline;
    }
  }

  Color get conditionColor {
    switch (coco) {
      case 1:
      case 2:
        return Colors.orangeAccent;
      case 3:
      case 4:
        return Colors.blueGrey;
      case 5:
      case 6:
        return Colors.grey;
      case 7:
      case 8:
      case 9:
      case 17:
      case 18:
        return Colors.blue;
      case 23:
      case 25:
      case 26:
      case 27:
        return Colors.deepPurple;
      default:
        return Colors.lightBlueAccent;
    }
  }
}
