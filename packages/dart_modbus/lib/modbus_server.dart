import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'src/frame.dart';
import 'src/transformers/rtu.dart';
import 'src/transformers/tcp.dart';

export 'src/frame.dart';

class ModbusServer {
  ModbusServer(
    this.read,
    this.write, {
    this.isRtu = false,
    this.workerLimit = 4,
    this.timeout = const Duration(milliseconds: 100),
  }) {
    if (isRtu) {
      _requestFrom = ModbusRtuRequestParser();
      _responseTo = ModbusRtuResponseSerializer();
    } else {
      _requestFrom = ModbusTcpRequestParser();
      _responseTo = ModbusTcpResponseSerializer();
    }

    _requestFrom.bind(read).listen(_onRequest);
    write.addStream(_responseTo.bind(_response.stream));
  }

  final bool isRtu;
  final Duration timeout;
  final int workerLimit;

  final Stream<Uint8List> read;
  final IOSink write;

  final _response = StreamController<ModbusResponsePacket>(sync: true);

  late final StreamTransformer<Uint8List, ModbusRequestPacket> _requestFrom;
  late final StreamTransformer<ModbusResponsePacket, List<int>> _responseTo;

  final queue = Queue<ModbusRequestPacket>();
  int _inFlight = 0;

  FutureOr<ModbusPDUResponse> Function(int unitId, ModbusPDURequest pdu)?
  onRequest;

  void _onRequest(ModbusRequestPacket req) {
    queue.addLast(req);
    _tryDispatch();
  }

  void _tryDispatch() {
    while (_inFlight < workerLimit && queue.isNotEmpty) {
      final req = queue.removeFirst();
      _inFlight += 1;

      var finished = false;
      Timer? timer;

      void done() {
        if (finished) return;
        finished = true;
        timer?.cancel();
        _inFlight -= 1;
        _tryDispatch();
      }

      timer = Timer(timeout, done);

      final handler = onRequest;
      if (handler == null) {
        done();
        continue;
      }

      final result = handler(req.unitId, req.pdu);
      Future<ModbusPDUResponse>.value(result)
          .then((pduResp) {
            _response.add(
              ModbusResponsePacket(req.unitId, pduResp, req.transactionId),
            );
            done();
          })
          .catchError((_) {
            done();
          });
    }
  }
}
