final class RpcRouter {
  const RpcRouter(this.name, this.services);

  final String name;
  final List<RpcService> services;

  Map<String, RpcService> get serviceMap => Map.fromEntries(
    services.map(
      (e) => MapEntry(e.name, e),
    ),
  );
}

final class RpcService {
  const RpcService(this.name, this.methods);

  final String name;
  final List<RpcMethod> methods;

  Map<String, RpcMethod> get methodMap => Map.fromEntries(
    methods.map(
      (e) => MapEntry(e.name, e),
    ),
  );
}

sealed class RpcMethod {
  const RpcMethod(this.name);

  final String name;
}

final class RpcGeneralMethod extends RpcMethod {
  const RpcGeneralMethod(super.name);
}

final class RpcSubscribeMethod extends RpcMethod {
  const RpcSubscribeMethod(super.name);
}
