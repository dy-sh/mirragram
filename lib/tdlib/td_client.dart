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
/// of updates.
class TdClient {
  TdClient._(this._clientId);

  final int _clientId;
  final _updates = StreamController<TdObject>.broadcast();
  final _pending = <String, Completer<TdObject>>{};
  var _nextId = 0;
  var _closed = false;

  Stream<TdObject> get updates => _updates.stream;

  static Future<TdClient> create({int logVerbosity = 1}) async {
    TdJson.execute(
      jsonEncode({
        '@type': 'setLogVerbosityLevel',
        'new_verbosity_level': logVerbosity,
      }),
    );
    final client = TdClient._(TdJson.createClientId());
    _clients[client._clientId] = client;
    await _startReceiver();
    // Any request wakes up a new client and triggers updateAuthorizationState.
    unawaited(
      client
          .send({'@type': 'getOption', 'name': 'version'})
          .catchError((_) => <String, dynamic>{}),
    );
    return client;
  }

  // td_receive blocks and must be called from one thread only, so a single
  // isolate receives events for all clients and they are routed by id.
  static final _clients = <int, TdClient>{};
  static Future<void>? _receiver;

  static Future<void> _startReceiver() => _receiver ??= () async {
    final port = ReceivePort();
    port.listen((message) => _route(message as String));
    await Isolate.spawn(_receiveLoop, port.sendPort);
  }();

  static void _receiveLoop(SendPort port) {
    while (true) {
      final event = TdJson.receive(1.0);
      if (event != null) port.send(event);
    }
  }

  static void _route(String raw) {
    final obj = jsonDecode(raw) as TdObject;
    _clients[obj['@client_id']]?._onMessage(obj);
  }

  void _onMessage(TdObject obj) {
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
    if (!_closed) _updates.add(obj);
  }

  Future<TdObject> send(TdObject request) {
    if (_closed) return Future.error(TdError(-1, 'client closed'));
    final id = '${_nextId++}';
    final completer = Completer<TdObject>();
    _pending[id] = completer;
    TdJson.send(_clientId, jsonEncode({...request, '@extra': id}));
    return completer.future;
  }

  void dispose() {
    _closed = true;
    _clients.remove(_clientId);
    for (final c in _pending.values) {
      c.completeError(TdError(-1, 'client closed'));
    }
    _pending.clear();
    _updates.close();
  }
}
