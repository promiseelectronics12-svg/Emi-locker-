import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'sse_service_web.dart' if (dart.library.io) 'sse_service_stub.dart' as platform;

/// A single parsed SSE event from the server.
class SseEvent {
  final String type;
  final Map<String, dynamic> data;
  const SseEvent({required this.type, required this.data});
}

/// Connects to GET /api/v1/events and re-emits typed [SseEvent]s.
///
/// Web (Chrome): uses browser native EventSource with token as query param.
/// Mobile: uses Dio chunked streaming.
class SseService {
  SseService({required Dio dio, required this.getToken}) : _dio = dio;

  final Dio _dio;
  /// Callback that returns the current access token (may change after refresh).
  final String? Function() getToken;

  final _controller = StreamController<SseEvent>.broadcast();
  bool _active = false;
  CancelToken? _cancelToken;
  Object? _webEs;

  Stream<SseEvent> get events => _controller.stream;

  void start() {
    if (_active) return;
    _active = true;
    if (kIsWeb) {
      _connectWeb(0);
    } else {
      _connectMobile(0);
    }
  }

  void stop() {
    _active = false;
    _cancelToken?.cancel('SSE stopped');
    _cancelToken = null;
    if (_webEs != null) {
      platform.closeEventSource(_webEs!);
      _webEs = null;
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }

  // ── Web path — browser native EventSource ────────────────────────────────

  void _connectWeb(int attempt) {
    if (!_active) return;
    final token = getToken();
    if (token == null) {
      debugPrint('[SSE] no token yet — retrying in 2s');
      Future.delayed(const Duration(seconds: 2), () => _connectWeb(attempt));
      return;
    }

    final baseUrl = _dio.options.baseUrl.replaceAll(RegExp(r'/$'), '');
    final url = '$baseUrl/api/v1/events?token=${Uri.encodeComponent(token)}';

    platform.openEventSource(
      url: url,
      onOpen: () => debugPrint('[SSE web] connected'),
      onMessage: (type, data) {
        final event = _parseBlock('event: $type\ndata: $data');
        if (event != null && !_controller.isClosed) _controller.add(event);
      },
      onError: () {
        if (!_active) return;
        if (_webEs != null) {
          platform.closeEventSource(_webEs!);
          _webEs = null;
        }
        final delay = Duration(seconds: (2 << attempt.clamp(0, 5)));
        debugPrint('[SSE web] error — reconnecting in ${delay.inSeconds}s');
        Future.delayed(delay, () => _connectWeb(attempt + 1));
      },
      setHandle: (es) => _webEs = es,
    );
  }

  // ── Mobile path — Dio chunked stream ─────────────────────────────────────

  Future<void> _connectMobile(int attempt) async {
    if (!_active) return;
    _cancelToken = CancelToken();

    try {
      final response = await _dio.get<ResponseBody>(
        '/api/v1/events',
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(hours: 24),
        ),
        cancelToken: _cancelToken,
      );

      final stream = response.data?.stream;
      if (stream == null) throw Exception('null stream');

      attempt = 0;
      String buffer = '';

      await for (final chunk in stream) {
        if (!_active) return;
        buffer += utf8.decode(chunk);
        final parts = buffer.split('\n\n');
        buffer = parts.removeLast();
        for (final part in parts) {
          final event = _parseBlock(part);
          if (event != null && !_controller.isClosed) _controller.add(event);
        }
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return;
      debugPrint('[SSE mobile] connection error: ${e.message}');
    } catch (e) {
      debugPrint('[SSE mobile] unexpected error: $e');
    }

    if (_active) {
      final delay = Duration(seconds: (2 << attempt.clamp(0, 5)));
      debugPrint('[SSE mobile] reconnecting in ${delay.inSeconds}s (attempt ${attempt + 1})');
      await Future.delayed(delay);
      _connectMobile(attempt + 1);
    }
  }

  // ── Shared parser ─────────────────────────────────────────────────────────

  SseEvent? _parseBlock(String block) {
    String? type;
    String? dataLine;

    for (final line in block.split('\n')) {
      if (line.startsWith('event: ')) {
        type = line.substring(7).trim();
      } else if (line.startsWith('data: ')) {
        dataLine = line.substring(6).trim();
      }
    }

    if (dataLine == null || dataLine == '{}') return null;
    if (type == 'heartbeat' || type == 'connected') return null;

    try {
      final decoded = jsonDecode(dataLine);
      if (decoded is! Map) return null;
      return SseEvent(
        type: type ?? 'message',
        data: Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }
}
