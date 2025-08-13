import 'dart:async';

typedef JsonMap = Map<dynamic, dynamic>;

typedef FRpc<R, P> = FutureOr<P> Function(R respone);
typedef FMap2D<O> = O Function(JsonMap input);
typedef FD2Map<O> = JsonMap Function(O input);

final class RpcServerMethod<R, P> {
  RpcServerMethod({
    required this.rpc,
    required this.requestFrom,
    required this.responeTo,
    this.isAsync = false,
    this.isStream = false,
  });

  final FRpc<R, P> rpc;

  final FMap2D<R> requestFrom;
  final FD2Map<P> responeTo;

  final bool isAsync;
  final bool isStream;
}

final class RpcClientMethod<R, P> {
  RpcClientMethod({
    required this.requestTo,
    required this.responeFrom,
    this.isAsync = false,
    this.isStream = false,
  });

  final FD2Map<R> requestTo;
  final FMap2D<P> responeFrom;

  final bool isAsync;
  final bool isStream;
}
