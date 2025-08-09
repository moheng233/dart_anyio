import 'package:json_annotation/json_annotation.dart';
import 'package:json_rpc_annotation/annotation.dart';
import 'package:json_rpc_runtime/runtime.dart';
import 'package:json_rpc_2/json_rpc_2.dart';

part 'a.rpc.dart';
part 'a.g.dart';

@JsonSerializable()
class Test2Respone {
  Test2Respone(this.name);

  Map<String, dynamic> toJson() => _$Test2ResponeToJson(this);

  final String name;
}

@JsonRpcService()
abstract interface class _TestSercice {
  @JsonRpcMethod()
  Future<String> _test(String id);

  @JsonRpcMethod()
  Test2Respone _test2();
}
