import 'package:hive_ce/hive.dart';
import 'package:ratisbonalyzer/src/features/home/domain/models/rvv_record.dart';

class RvvRecordAdapter extends TypeAdapter<RvvRecord> {
  @override
  final int typeId = 0;

  @override
  RvvRecord read(BinaryReader reader) {
    return RvvRecord(
      arrivalDoor: reader.read() as DateTime,
      arrivalHalt: reader.read() as DateTime,
      arrivalPlan: reader.read() as DateTime,
      departureDoor: reader.read() as DateTime,
      departureHalt: reader.read() as DateTime,
      departurePlan: reader.read() as DateTime,
      arrivalProductive: reader.read() as bool,
      departureProductive: reader.read() as bool,
      operationDay: reader.read() as DateTime,
      tripStartCode: reader.read() as String,
      tripStartName: reader.read() as String,
      tripEndCode: reader.read() as String,
      tripEndName: reader.read() as String,
      stopCode: reader.read() as String,
      stopName: reader.read() as String,
      haltPoint: reader.read() as String,
      line: reader.read() as String,
      direction: reader.read() as int,
      branch: reader.read() as String,
      rotation: reader.read() as String,
      scheduleDeviationDeparture: reader.read() as int?,
      scheduleDeviationArrival: reader.read() as int?,
      cumulativeDistance: reader.read() as int,
      cumulativeTravelTime: reader.read() as int,
    );
  }

  @override
  void write(BinaryWriter writer, RvvRecord obj) {
    writer.write(obj.arrivalDoor);
    writer.write(obj.arrivalHalt);
    writer.write(obj.arrivalPlan);
    writer.write(obj.departureDoor);
    writer.write(obj.departureHalt);
    writer.write(obj.departurePlan);
    writer.write(obj.arrivalProductive);
    writer.write(obj.departureProductive);
    writer.write(obj.operationDay);
    writer.write(obj.tripStartCode);
    writer.write(obj.tripStartName);
    writer.write(obj.tripEndCode);
    writer.write(obj.tripEndName);
    writer.write(obj.stopCode);
    writer.write(obj.stopName);
    writer.write(obj.haltPoint);
    writer.write(obj.line);
    writer.write(obj.direction);
    writer.write(obj.branch);
    writer.write(obj.rotation);
    writer.write(obj.scheduleDeviationDeparture);
    writer.write(obj.scheduleDeviationArrival);
    writer.write(obj.cumulativeDistance);
    writer.write(obj.cumulativeTravelTime);
  }
}
