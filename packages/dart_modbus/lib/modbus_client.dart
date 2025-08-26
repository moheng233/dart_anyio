/// Support for doing something awesome.
///
/// More dartdocs go here.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'modbus_server.dart';
import 'src/transformers/rtu.dart';
import 'src/transformers/tcp.dart';

export 'src/frame.dart';

final class ModbusClient {
  ModbusClient(
    this.read,
    this.write, {
    this.isRtu = false,
    this.completerLimit = 1,
    this.timeout = const Duration(milliseconds: 100),
  }) {
    if (isRtu) {
      _requestTo = ModbusRtuRequestSerializer();
      _responeFrom = ModbusRtuResponseParser();
    } else {
      _requestTo = ModbusTcpRequestSerializer();
      _responeFrom = ModbusTcpResponseParser();
    }

    _responeFrom
        .bind(read)
        .listen(
          _onRespone,
          onError: (Object error, StackTrace stackTrace) {
            // Swallow parser errors here; upper layers handle connection lifecycle
            // via socket.done in the adapter. Pending requests will timeout.
          },
        );

    _requestTo
        .bind(_request.stream)
        .listen(
          write.add,
        );
  }

  final bool isRtu;
  final Duration timeout;
  final int completerLimit;

  final _request = StreamController<ModbusRequestPacket>(sync: true);

  late final StreamTransformer<ModbusRequestPacket, List<int>> _requestTo;
  late final StreamTransformer<Uint8List, ModbusResponsePacket> _responeFrom;

  final Stream<Uint8List> read;
  final StreamSink<List<int>> write;

  int transactionId = 0;

  final queue =
      Queue<
        ({ModbusRequestPacket request, Completer<ModbusResponsePacket> respone})
      >();
  final inFlights =
      <int, ({Completer<ModbusResponsePacket> completer, Timer timer})>{};

  Future<ModbusResponsePacket> request(
    int unitId,
    ModbusPDURequest pdu,
    int? transactionId,
  ) async {
    return _sendRequst(ModbusRequestPacket(unitId, pdu, transactionId)).future;
  }

  void _onRespone(ModbusResponsePacket respone) {
    final key = respone.transactionId ?? 0;
    final inflight = inFlights.remove(key);
    inflight?.timer.cancel();
    final completer = inflight?.completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(respone);
    }
    _tryDispatchPending();
  }

  Completer<ModbusResponsePacket> _sendRequst(ModbusRequestPacket request) {
    final completer = Completer<ModbusResponsePacket>();
    queue.addLast((request: request, respone: completer));
    _tryDispatchPending();
    return completer;
  }

  void _tryDispatchPending() {
    while (inFlights.length < completerLimit && queue.isNotEmpty) {
      final item = queue.removeFirst();
      final key = item.request.transactionId ?? 0;

      final timer = Timer(timeout, () {
        final removed = inFlights.remove(key);
        final c = removed?.completer;
        if (c != null && !c.isCompleted) {
          c.completeError(
            TimeoutException('Modbus request timed out', timeout),
          );
        }
        _tryDispatchPending();
      });

      inFlights[key] = (completer: item.respone, timer: timer);
      _request.add(item.request);
    }
  }
}

extension ModbusClientHelper on ModbusClient {
  Future<List<bool>> readCoils(int unitId, int start, int quantity) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.readCoils(start, quantity),
      _nextTx(),
    );
    return (resp.pdu as ReadCoilsResponse).values;
  }

  Future<List<bool>> readDiscreteInputs(
    int unitId,
    int start,
    int quantity,
  ) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.readDiscreteInputs(start, quantity),
      _nextTx(),
    );
    return (resp.pdu as ReadDiscreteInputsResponse).values;
  }

  Future<List<int>> readHoldingRegisters(
    int unitId,
    int start,
    int quantity,
  ) async {
    final respone = await request(
      unitId,
      ModbusPDURequest.readHoldingRegisters(start, quantity),
      _nextTx(),
    );

    return (respone.pdu as ReadHoldingRegistersResponse).values;
  }

  Future<List<int>> readInputRegisters(
    int unitId,
    int start,
    int quantity,
  ) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.readInputRegisters(start, quantity),
      _nextTx(),
    );
    return (resp.pdu as ReadInputRegistersResponse).values;
  }

  Future<int> writeHoldingRegister(int unitId, int addr, int value) async {
    final respone = await request(
      unitId,
      ModbusPDURequest.writeSingleRegister(addr, value),
      _nextTx(),
    );

    return (respone.pdu as WriteSingleRegisterResponse).value;
  }

  Future<int> writeMultipleCoils(
    int unitId,
    int start,
    List<bool> values,
  ) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.writeMultipleCoils(start, values),
      _nextTx(),
    );
    return (resp.pdu as WriteMultipleCoilsResponse).quantity;
  }

  Future<int> writeMultipleRegisters(
    int unitId,
    int start,
    List<int> values,
  ) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.writeMultipleRegisters(start, values),
      _nextTx(),
    );
    return (resp.pdu as WriteMultipleRegistersResponse).quantity;
  }

  // ignore: avoid_positional_boolean_parameters 统一接口
  Future<bool> writeSingleCoil(int unitId, int addr, bool value) async {
    final resp = await request(
      unitId,
      ModbusPDURequest.writeSingleCoil(addr, value),
      _nextTx(),
    );
    return (resp.pdu as WriteSingleCoilResponse).value;
  }

  // 统一生成事务号（RTU 模式不使用事务号）
  int? _nextTx() => isRtu ? null : transactionId += 1;
}
