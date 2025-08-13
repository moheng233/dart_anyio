import 'package:source_helper/source_helper.dart';

String normalizeElementName(String name) {
  return name.nonPrivate;
}

String normalizeSeviceName(String name) {
  var result = normalizeElementName(name);
  if (result.endsWith('Service')) {
    result = result.substring(0, result.length - 'Service'.length);
  }

  return result;
}

String getMethodName(String service, String method) {
  return '${normalizeElementName(service)}/${normalizeElementName(method)}';
}

String getRequstModelName(String name, {bool withPrive = false}) {
  return '${withPrive ? '_' : ''}${normalizeElementName(name).pascal}Request';
}

String getResponeModelName(String name, {bool withPrive = false}) {
  return '${withPrive ? '_' : ''}${normalizeElementName(name).pascal}Respone';
}
