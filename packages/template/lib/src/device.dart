import '../service.dart';

abstract class Device {
  Map<String, PointValue> get values;
  List<PointInfo> get points;

  PointValue read(String tagId);
  Stream<PointValue> listen(String tagId);

  void write(String tagId, dynamic value);
  Future<bool> writeAsync(String tagid, dynamic value);
}
