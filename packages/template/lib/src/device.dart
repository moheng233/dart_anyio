import '../service.dart';

abstract class Device {
  String get deviceId;

  Map<String, Object?> get values;
  List<PointInfo> get points;

  Object? read(String tagId);
  Stream<Object?> listen(String tagId);

  void write(String tagId, Object? value);
  Future<bool> writeAsync(String tagid, Object? value);
}
