import 'package:analyzer/dart/element/type.dart';

bool isPrimitiveType(DartType type) {
  return type.isDartCoreInt ||
      type.isDartCoreDouble ||
      type.isDartCoreNum ||
      type.isDartCoreString ||
      type.isDartCoreBool;
}

bool isRecordType(DartType type) {
  return type.isDartCoreRecord;
}

DartType unwarpStreamType(DartType type) {
  if (type.isDartAsyncStream) {
    if (type is InterfaceType && type.typeArguments.isNotEmpty) {
      return type.typeArguments.first;
    }
  }
  return type;
}

DartType unwrapFutureType(DartType type) {
  if (type.isDartAsyncFuture) {
    if (type is InterfaceType && type.typeArguments.isNotEmpty) {
      return type.typeArguments.first;
    }
  }
  return type;
}
