import 'package:freezed_annotation/freezed_annotation.dart';

part 'template.freezed.dart';
part 'template.g.dart';

@freezed
abstract class TemplateBase with _$TemplateBase {
  const factory TemplateBase(
    String name,
    String version,
    String adapter,
  ) = _TemplateBase;

  factory TemplateBase.fromJson(Map<dynamic, dynamic> json) =>
      _$TemplateBaseFromJson(json);
}

@freezed
abstract class DeviceBase with _$DeviceBase {
  const factory DeviceBase({
    required String name,
    required String template,
    required TransportOption transport,
    String? displayName,
  }) = _DeviceBase;
}

@JsonEnum(alwaysCreate: true)
enum SerialPartiy { none, odd, even, mark, space }

@Freezed(unionKey: 'type')
sealed class TransportOption with _$TransportOption {
  factory TransportOption.fromJson(Map<String, dynamic> json) =>
      _$TransportOptionFromJson(json);

  factory TransportOption.serial(
    String dev, {
    @Default(9600) int baudRate,
    @Default(8) int dataBits,
    @Default(SerialPartiy.none) SerialPartiy parity,
    @Default(1) int stopBits,
    @Default(Duration(microseconds: 100)) Duration frameTimeout,
  }) = TransportOptionForSerial;

  factory TransportOption.tcp(
    String host,
    int port, {
    @Default(Duration(microseconds: 100)) Duration frameTimeout,
  }) = TransportOptionForTcp;

  factory TransportOption.can(
    String dev, {
    @Default(9600) int baudRate,
    @Default(Duration(microseconds: 100)) Duration frameTimeout,
  }) = TransportOptionForCan;
}

@Freezed(unionKey: 'type')
sealed class PointValue with _$PointValue {
  factory PointValue.fromValue(dynamic value, int ts) => switch (value) {
    int() => PointValue.int(value, ts),
    double() => PointValue.double(value, ts),
    bool() => PointValue.boolean(value, ts),
    Object() => PointValue.invalid(ts),
    null => PointValue.invalid(ts),
  };

  factory PointValue.fromJson(Map<String, dynamic> json) =>
      _$PointValueFromJson(json);

  factory PointValue.invalid(int time) = PointValueForInvalid;
  factory PointValue.int(int value, int time) = PointValueForInt;
  factory PointValue.double(double value, int time) = PointValueForDouble;
  // ignore: avoid_positional_boolean_parameters 统一命名
  factory PointValue.boolean(bool value, int time) = PointValueForBoolean;
}

@Freezed()
abstract class PointInfo with _$PointInfo {
  const factory PointInfo({
    required String tag,
    String? displayName,
    String? detailed,
  }) = _PointInfo;

  factory PointInfo.fromJson(Map<dynamic, dynamic> json) =>
      _$PointInfoFromJson(json);
}
