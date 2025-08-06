import 'dart:async';
import 'dart:typed_data';

class Uint8ListToIntListTransformer
    extends StreamTransformerBase<Uint8List, List<int>> {
  @override
  Stream<List<int>> bind(Stream<Uint8List> stream) async* {
    await for (final raw in stream) {
      yield raw.toList();
    }
  }
}
