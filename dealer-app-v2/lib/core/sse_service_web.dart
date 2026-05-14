// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void openEventSource({
  required String url,
  required void Function() onOpen,
  required void Function(String type, String data) onMessage,
  required void Function() onError,
  required void Function(Object es) setHandle,
}) {
  final es = html.EventSource(url);
  setHandle(es);

  es.onOpen.listen((_) => onOpen());
  es.onError.listen((_) => onError());

  // Named events the backend emits
  const events = [
    'key_requested',
    'key_request_approved',
    'enrollment_complete',
    'device_locked',
    'device_unlocked',
    'device_decoupled',
    'device_decoupling_requested',
    'grace_expired',
    'new_alert',
  ];

  for (final name in events) {
    es.addEventListener(name, (event) {
      final e = event as html.MessageEvent;
      onMessage(name, e.data as String? ?? '{}');
    });
  }
}

void closeEventSource(Object es) {
  (es as html.EventSource).close();
}
