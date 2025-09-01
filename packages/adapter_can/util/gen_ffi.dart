import 'package:ffigen/ffigen.dart';

final ffigen = FfiGen();

void main(List<String> args) {
  ffigenForVCICan();
}

String functionRename(Declaration declaration) {
  final name = declaration.originalName;
  if (name.startsWith('VCI_')) {
    final suffix = name.substring(4); // 移除 'VCI_' 前缀
    // 将第一个字符转换为小写，其余保持原样（假设已经是驼峰）
    return suffix[0].toLowerCase() + suffix.substring(1);
  } else if (name.startsWith('_VCI_')) {
    final suffix = name.substring(5); // 移除 '_VCI_' 前缀
    final parts = suffix.split('_');
    final camel = StringBuffer(
      parts[0][0].toUpperCase() + parts[0].substring(1).toLowerCase(),
    );
    for (var i = 1; i < parts.length; i++) {
      camel.write(
        parts[i][0].toUpperCase() + parts[i].substring(1).toLowerCase(),
      );
    }
    return camel.toString();
  }
  return name;
}

void ffigenForVCICan() {
  ffigen.run(
    Config(
      output: Uri.file('lib/src/vci_can/generated_bindings.dart'),
      entryPoints: [Uri.file('src/usbcan2/ControlCAN.h')],
      ffiNativeConfig: const FfiNativeConfig(
        enabled: true,
        assetId:
            'package:anyio_adapter_modbus/src/vci_can/generated_bindings.dart',
      ),
      functionDecl: DeclarationFilters(
        shouldInclude: (_) => true,
        rename: functionRename,
      ),
      structDecl: DeclarationFilters(
        shouldInclude: (_) => true,
        rename: functionRename,
      ),
    ),
  );
}
