// FFI bindings to td_json_client.h. The library is bundled by hook/build.dart.
@DefaultAsset('package:veilgram/tdjson')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int32 Function()>(symbol: 'td_create_client_id')
external int _tdCreateClientId();

@Native<Void Function(Int32, Pointer<Utf8>)>(symbol: 'td_send')
external void _tdSend(int clientId, Pointer<Utf8> request);

@Native<Pointer<Utf8> Function(Double)>(symbol: 'td_receive')
external Pointer<Utf8> _tdReceive(double timeout);

@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(symbol: 'td_execute')
external Pointer<Utf8> _tdExecute(Pointer<Utf8> request);

abstract final class TdJson {
  static int createClientId() => _tdCreateClientId();

  static void send(int clientId, String request) {
    final ptr = request.toNativeUtf8();
    try {
      _tdSend(clientId, ptr);
    } finally {
      malloc.free(ptr);
    }
  }

  /// Must be called from a single thread. Returns null on timeout.
  static String? receive(double timeoutSeconds) {
    final ptr = _tdReceive(timeoutSeconds);
    return ptr == nullptr ? null : ptr.toDartString();
  }

  static String? execute(String request) {
    final req = request.toNativeUtf8();
    try {
      final ptr = _tdExecute(req);
      return ptr == nullptr ? null : ptr.toDartString();
    } finally {
      malloc.free(req);
    }
  }
}
