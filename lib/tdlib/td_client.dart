import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'td_json.dart';

typedef TdObject = Map<String, dynamic>;

class TdError implements Exception {
  TdError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'TdError($code): $message';
}

/// TDLib client: requests matched to responses via `@extra`, plus a stream
/// of updates. td_receive blocks, so it runs in a separate isolate.
class TdClient {
  TdClient._(this._clientId);

  final int _clientId;
  final _updates = StreamController<TdObject>.broadcast();
  final _pending = <String, Completer<TdObject>>{};
  var _nextId = 0;
  ReceivePort? _port;
  Isolate? _receiver;

  Stream<TdObject> get updates => _updates.stream;

  static Future<TdClient> create({int logVerbosity = 1}) async {
    TdJson.execute(
      jsonEncode({
        '@type': 'setLogVerbosityLevel',
        'new_verbosity_level': logVerbosity,
      }),
    );
    final client = TdClient._(TdJson.createClientId());
    await client._start();
    // Any request wakes up a new client and triggers updateAuthorizationState.
    unawaited(client.send({'@type': 'getOption', 'name': 'version'}));
    return client;
  }

  Future<void> _start() async {
    final port = ReceivePort();
    _port = port;
    port.listen((message) => _onMessage(message as String));
    _receiver = await Isolate.spawn(_receiveLoop, port.sendPort);
  }

  static void _receiveLoop(SendPort port) {
    while (true) {
      final event = TdJson.receive(1.0);
      if (event != null) port.send(event);
    }
  }

  void _onMessage(String raw) {
    final obj = jsonDecode(raw) as TdObject;
    if (obj['@client_id'] != _clientId) return;

    final extra = obj['@extra'];
    if (extra is String) {
      final completer = _pending.remove(extra);
      if (completer != null) {
        if (obj['@type'] == 'error') {
          completer.completeError(
            TdError(obj['code'] as int, obj['message'] as String),
          );
        } else {
          completer.complete(obj);
        }
      }
      return;
    }
    _updates.add(obj);
  }

  Future<TdObject> send(TdObject request) {
    final id = '${_nextId++}';
    final completer = Completer<TdObject>();
    _pending[id] = completer;
    TdJson.send(_clientId, jsonEncode({...request, '@extra': id}));
    return completer.future;
  }

  void dispose() {
    _receiver?.kill(priority: Isolate.immediate);
    _port?.close();
    _updates.close();
  }
}
