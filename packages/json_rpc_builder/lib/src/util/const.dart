import 'package:built_collection/built_collection.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';

const jsonRpcMethodChecker = TypeChecker.fromUrl(
  'package:json_rpc_annotation/annotation.dart#JsonRpcMethod',
);

const voidReference = Reference('void');
const stringReference = Reference('String');
const dynamicReference = Reference('dynamic');

final jsonMapReference = TypeReference(
  (b) => b
    ..symbol = 'Map'
    ..types = ListBuilder([dynamicReference, dynamicReference]),
);

const parametersReference = Reference('Parameters');

const jsonSerializableReference = Reference(
  'JsonSerializable',
  'package:json_annotation/json_annotation.dart',
);

final jsonMapFutureReference = TypeReference(
  (b) => b
    ..symbol = 'Future'
    ..types = ListBuilder([jsonMapReference]),
);

const JsonRpcPeerReference = Reference(
  'Peer',
  'package:json_rpc_2/json_rpc_2.dart',
);
