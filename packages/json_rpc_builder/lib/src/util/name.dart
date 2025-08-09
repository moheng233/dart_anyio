String normalizeElementName(String name) {
  var result = name;
  if (result.startsWith('_')) {
    result = result.substring(1);
  }
  return result;
}

String normalizeSeviceName(String name) {
  var result = normalizeElementName(name);
  if (result.endsWith('Service')) {
    result = result.substring(0, result.length - 'Service'.length);
  }

  return result;
}

String getRequstModelName(String name) {
  return '_${normalizeElementName(name)}Request';
}

String getResponeModelName(String name) {
  return '_${normalizeElementName(name)}Respone';
}
