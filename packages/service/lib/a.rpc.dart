// dart format width=80
// ignore_for_file: non_constant_identifier_names

part of 'a.dart';

// **************************************************************************
// JsonRpcRequestModelGenerator
// **************************************************************************

@JsonSerializable()
final class _testRequest {
  const _testRequest(this.id);

  factory _testRequest.fromJson(Map<dynamic, dynamic> json) =>
      _$testRequestFromJson(json);

  final String id;
}

// **************************************************************************
// JsonRpcClientGenerator
// **************************************************************************

final class TestSerciceClient {}

// **************************************************************************
// JsonRpcServerGenerator
// **************************************************************************

abstract interface class TestSerciceServerService
    implements _TestSercice, IJsonRpcService {
  TestSerciceServerService(this.peer) {
    peer
      ..registerMethod('TestSercice/test', _test_Pre)
      ..registerMethod('TestSercice/test2', _test2_Pre);
  }

  @override
  final Peer peer;

  Future<Map<dynamic, dynamic>> _test_Pre(Parameters request) async {
    final requestModel = _testRequest.fromJson(request.asMap);
    final result = await _test(requestModel.id);
    return {'value': result};
  }

  Future<Map<dynamic, dynamic>> _test2_Pre(Parameters request) async {
    final result = _test2();
    return result.toJson();
  }
}
