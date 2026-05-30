import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:ratisbonalyzer/src/app.dart';
import 'package:ratisbonalyzer/src/features/home/data/services/rvv_record_adapter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(RvvRecordAdapter());
  runApp(const MainApp());
}
