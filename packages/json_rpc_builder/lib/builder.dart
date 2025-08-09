import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/generator/model/request_model_generator.dart';
import 'src/generator/model/respone_model_generator.dart';
import 'src/generator/service/client_service_generator.dart';
import 'src/generator/service/server_service_generator.dart';

Builder jsonRpcBuilder(BuilderOptions options) {
  return PartBuilder(
    [
      JsonRpcRequestModelGenerator(),
      JsonRpcResponeModelGenerator(),
      JsonRpcClientGenerator(),
      JsonRpcServerGenerator(),
    ],
    '.rpc.dart',
    options: options,
    header: <String>[
      '// ignore_for_file: non_constant_identifier_names',
    ].join('\n'),
  );
}
