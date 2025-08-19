import 'package:anyio_template/service.dart';

final class DeviceImpl extends Device {
  DeviceImpl(this.deviceId);

  @override
  final String deviceId;

  @override
  // TODO: implement points
  List<PointInfo> get points => throw UnimplementedError();

  @override
  // TODO: implement values
  Map<String, Object?> get values => throw UnimplementedError();

  @override
  Stream<Object?> listen(String tagId) {
    // TODO: implement listen
    throw UnimplementedError();
  }

  @override
  Object? read(String tagId) {
    // TODO: implement read
    throw UnimplementedError();
  }

  @override
  void write(String tagId, Object? value) {
    // TODO: implement write
  }

  @override
  Future<bool> writeAsync(String tagid, Object? value) {
    // TODO: implement writeAsync
    throw UnimplementedError();
  }
}
