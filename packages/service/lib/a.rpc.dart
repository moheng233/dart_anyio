// dart format width=80
// ignore_for_file: non_constant_identifier_names

part of 'a.dart';

// **************************************************************************
// JsonRpcRequestModelGenerator
// **************************************************************************

@JsonSerializable()
final class _TestRequest {
  const _TestRequest(this.id);

  factory _TestRequest.fromJson(Map<dynamic, dynamic> json) =>
      _$TestRequestFromJson(json);

  final String id;

  Map<dynamic, dynamic> toJson() => _$TestRequestToJson(this);
}

// **************************************************************************
// JsonRpcClientGenerator
// **************************************************************************

final class TestSerciceClient extends IJsonRpcClient {}

// **************************************************************************
// JsonRpcServerGenerator
// **************************************************************************

abstract interface class TestSerciceServerService
    implements _TestSercice, IJsonRpcServer {
  TestSerciceServerService(this.peer) {
    peer
      ..registerMethod('TestSercice/test', _test_Pre)
      ..registerMethod('TestSercice/test2', _test2_Pre)
      ..registerMethod('TestSercice/test3', _test3_Pre);
  }

  @override
  final Peer peer;

  Future<Map<dynamic, dynamic>> _test_Pre(Parameters request) async {
    final requestModel = _TestRequest.fromJson(request.asMap);
    final result = await _test(requestModel.id);
    return {'value': result};
  }

  Future<Map<dynamic, dynamic>> _test2_Pre(Parameters request) async {
    final result = _test2();
    return result.toJson();
  }

  Future<Map<dynamic, dynamic>> _test3_Pre(Parameters request) async {
    final result = await _test3();
    return {'value': result};
  }
}
