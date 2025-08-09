import 'package:meta/meta_meta.dart';

@Target({TargetKind.classType})
final class JsonRpcService {
  const JsonRpcService();
}

@Target({TargetKind.method})
final class JsonRpcMethod {
  const JsonRpcMethod();
}

@Target({TargetKind.classType})
final class JsonRpcRouter {
  const JsonRpcRouter();
}
