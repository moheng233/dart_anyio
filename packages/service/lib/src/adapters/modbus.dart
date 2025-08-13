import 'dart:async';

import 'package:anyio_template/service.dart';
import 'package:anyio_modbus/modbus_client.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'modbus.freezed.dart';
part 'modbus.g.dart';

final class AdapterFactoryForModbus
    extends AdapterPluginBase<AdapterInstanceForModbus, AdapterForModbusExtra> {
  @override
  List<String> get matchAdapter => ['modbus'];

  @override
  String get name => 'Modbus';

  @override
  String get version => '';

  @override
  AdapterInstanceForModbus build(
    DeviceBase device,
    TemplateBase template,
    TransportSessionBase transport,
    AdapterForModbusExtra extra,
  ) {}

  @override
  Future<void> down() async {}

  @override
  AdapterForModbusExtra load(Map<dynamic, dynamic> json) {
    return AdapterForModbusExtra.fromJson(json);
  }

  @override
  Future<void> up() async {}
}

@freezed
abstract class AdapterForModbusExtra with _$AdapterForModbusExtra {
  const factory AdapterForModbusExtra({
    required List<ModbusPoll> pools,
    required List<ModbusReadPoint> reads,
    required List<ModbusWritePoint> writes,
  }) = _AdapterForModbusExtra;

  factory AdapterForModbusExtra.fromJson(Map<dynamic, dynamic> json) =>
      _$AdapterForModbusExtraFromJson(json);
}

final class AdapterInstanceForModbus extends AdapterInstance {
  AdapterInstanceForModbus(this.aid, this.transport, this.option);

  final AdapterForModbusExtra option;

  final TransportSessionBase transport;

  final _request = StreamController<ModbusRequestPacket>();

  @override
  final String aid;

  @override
  Iterable<PointInfo> get points => [];

  @override
  Future<void> close() {
    // TODO: implement close
    throw UnimplementedError();
  }

  @override
  Future<void> open() {

  }

  @override
  Future<dynamic> read(String tag) {
    // TODO: implement read
    throw UnimplementedError();
  }

  @override
  Future<bool> write(String tag, dynamic value) {
    // TODO: implement write
    throw UnimplementedError();
  }
}

