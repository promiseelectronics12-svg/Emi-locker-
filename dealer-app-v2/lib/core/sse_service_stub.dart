// Mobile stub — these functions are never called on non-web platforms.
// The SseService uses kIsWeb to guard the web path before calling these.

void openEventSource({
  required String url,
  required void Function() onOpen,
  required void Function(String type, String data) onMessage,
  required void Function() onError,
  required void Function(Object es) setHandle,
}) {
  throw UnsupportedError('openEventSource called on non-web platform');
}

void closeEventSource(Object es) {
  throw UnsupportedError('closeEventSource called on non-web platform');
}
