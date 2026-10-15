/// A minimal client of Handheld Daemon's local API.
///
/// Handheld Daemon owns the hardware: it validates values, resolves conflicts
/// with Steam and other power tools, and persists its own settings. This client
/// only reads its state and writes documented keys back, so the panel never
/// becomes a second writer of the same device.
///
/// Nothing here touches `shortcuts.*`: Handheld Daemon's touchscreen gestures
/// stay entirely its own.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Handheld Daemon's local API socket.
const hhdSocketPath = '/run/hhd/api';

/// Raised when Handheld Daemon is unreachable or answers with an error.
class HhdApiException implements Exception {
  const HhdApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null
      ? 'HhdApiException: $message'
      : 'HhdApiException($status): $message';
}

/// One raw HTTP response.
class HhdResponse {
  const HhdResponse({required this.status, required this.body});

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;
}

/// Talks HTTP/1.1 over Handheld Daemon's Unix socket.
///
/// Handheld Daemon serves `BaseHTTPRequestHandler`, whose responses are
/// HTTP/1.0 and therefore delimited by connection close. The parser accepts a
/// chunked body too, so a future server change cannot silently truncate one.
class HhdClient {
  HhdClient({this.socketPath = hhdSocketPath});

  final String socketPath;

  /// Static metadata describing every exposed setting.
  Future<Map<String, Object?>> settings() =>
      _json('GET', '/api/v1/settings', timeout: const Duration(seconds: 15));

  /// Current live state, including hardware-backed values.
  Future<Map<String, Object?>> state() =>
      _json('GET', '/api/v1/state', timeout: const Duration(seconds: 15));

  /// Blocks until Handheld Daemon's next event-loop pass, then returns state.
  Future<Map<String, Object?>> pollState({Duration? timeout}) => _json(
    'GET',
    '/api/v1/state?poll',
    timeout: timeout ?? const Duration(seconds: 30),
  );

  /// Applies one dotted-key patch and returns the authoritative state.
  ///
  /// A device driver may reject or adjust a value, so callers must adopt the
  /// reply rather than their optimistic guess.
  Future<Map<String, Object?>> setValue(String key, Object? value) => _json(
    'POST',
    '/api/v1/state',
    body: <String, Object?>{key: value},
    timeout: const Duration(seconds: 15),
  );

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Object? body,
    required Duration timeout,
  }) async {
    final response = await _send(method, path, body: body, timeout: timeout);
    if (!response.ok) {
      throw HhdApiException(
        'Handheld Daemon rejected $method $path',
        status: response.status,
      );
    }
    if (response.body.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return decoded.cast<String, Object?>();
      throw HhdApiException('unexpected payload for $method $path');
    } on FormatException catch (error) {
      throw HhdApiException(
        'invalid JSON from Handheld Daemon: ${error.message}',
      );
    }
  }

  Future<HhdResponse> _send(
    String method,
    String path, {
    Object? body,
    required Duration timeout,
  }) async {
    final payload = body == null ? null : utf8.encode(jsonEncode(body));

    final Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: const Duration(seconds: 5),
      );
    } on SocketException catch (error) {
      throw HhdApiException('cannot reach Handheld Daemon: ${error.message}');
    } on FileSystemException catch (error) {
      throw HhdApiException('cannot reach Handheld Daemon: ${error.message}');
    }

    final received = BytesBuilder(copy: false);
    final closed = Completer<void>();
    final subscription = socket.listen(
      received.add,
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
      onError: (Object error) {
        if (!closed.isCompleted) closed.completeError(error);
      },
      cancelOnError: true,
    );

    final head = StringBuffer()
      ..write('$method $path HTTP/1.1\r\n')
      ..write('Host: localhost\r\n')
      ..write('Connection: close\r\n')
      ..write('Accept: application/json\r\n');
    if (payload != null) {
      head
        ..write('Content-Type: application/json\r\n')
        ..write('Content-Length: ${payload.length}\r\n');
    }
    head.write('\r\n');

    socket.add(utf8.encode(head.toString()));
    if (payload != null) socket.add(payload);

    try {
      await socket.flush().timeout(timeout);
      await closed.future.timeout(timeout);
    } on TimeoutException {
      throw HhdApiException(
        'Handheld Daemon did not answer $method $path in time',
      );
    } finally {
      await subscription.cancel();
      socket.destroy();
    }

    return parseHhdResponse(received.takeBytes());
  }
}

/// Parses one raw HTTP response, including a chunked body when present.
HhdResponse parseHhdResponse(List<int> bytes) {
  final headerEnd = _indexOfDoubleCrlf(bytes);
  if (headerEnd < 0) {
    throw const HhdApiException('malformed response: no header terminator');
  }
  final headerText = latin1.decode(bytes.sublist(0, headerEnd));
  final lines = headerText.split('\r\n');
  if (lines.isEmpty) {
    throw const HhdApiException('malformed response: empty status line');
  }
  final status = _parseStatus(lines.first);
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    headers[line.substring(0, separator).trim().toLowerCase()] = line
        .substring(separator + 1)
        .trim();
  }

  var body = bytes.sublist(headerEnd + 4);
  if ((headers['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) {
    body = _decodeChunked(body);
  }
  return HhdResponse(
    status: status,
    body: utf8.decode(body, allowMalformed: true),
  );
}

int _indexOfDoubleCrlf(List<int> bytes) {
  for (var index = 0; index + 3 < bytes.length; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index;
    }
  }
  return -1;
}

int _parseStatus(String statusLine) {
  final parts = statusLine.split(' ');
  if (parts.length < 2) {
    throw HhdApiException('malformed status line: $statusLine');
  }
  final status = int.tryParse(parts[1]);
  if (status == null) {
    throw HhdApiException('malformed status code: $statusLine');
  }
  return status;
}

List<int> _decodeChunked(List<int> body) {
  final out = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < body.length) {
    final lineEnd = _indexOfCrlf(body, offset);
    if (lineEnd < 0) break;
    final sizeText = latin1
        .decode(body.sublist(offset, lineEnd))
        .split(';')
        .first
        .trim();
    final size = int.tryParse(sizeText, radix: 16);
    if (size == null) {
      throw HhdApiException('malformed chunk size: $sizeText');
    }
    final start = lineEnd + 2;
    if (size == 0) break;
    if (start + size > body.length) {
      throw const HhdApiException('truncated chunked body');
    }
    out.add(body.sublist(start, start + size));
    offset = start + size + 2;
  }
  return out.takeBytes();
}

int _indexOfCrlf(List<int> bytes, int from) {
  for (var index = from; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
  }
  return -1;
}

/// Reads one nested value by its dotted key.
Object? readHhdValue(Map<String, Object?> tree, String dottedKey) {
  Object? cursor = tree;
  for (final segment in dottedKey.split('.')) {
    if (cursor is! Map) return null;
    cursor = cursor[segment];
  }
  return cursor;
}
