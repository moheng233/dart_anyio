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
  return '${toPascalCase(normalizeElementName(name))}Request';
}

String getResponeModelName(String name) {
  return '${toPascalCase(normalizeElementName(name))}Respone';
}

String toPascalCase(String input) {
  if (input.isEmpty) return input;
  final parts = input.split(RegExp(r'[_\-\s]+'));
  return parts.map((part) {
    if (part.isEmpty) return '';
    final lower = part.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join();
}
