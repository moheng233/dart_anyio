import 'package:anyio_template/service.dart';

final class DeviceImpl extends Device {
  DeviceImpl(this.deviceId);

  final String deviceId;

  @override
  // TODO: implement points
  List<PointInfo> get points => throw UnimplementedError();

  @override
  // TODO: implement values
  Map<String, PointValue> get values => throw UnimplementedError();

  @override
  Stream<PointValue> listen(String tagId) {
    // TODO: implement listen
    throw UnimplementedError();
  }

  @override
  PointValue read(String tagId) {
    // TODO: implement read
    throw UnimplementedError();
  }

  @override
  void write(String tagId, value) {
    // TODO: implement write
  }

  @override
  Future<bool> writeAsync(String tagid, value) {
    // TODO: implement writeAsync
    throw UnimplementedError();
  }
}
