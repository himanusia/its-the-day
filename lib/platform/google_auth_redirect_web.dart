import 'package:web/web.dart' as web;

void redirectToGoogleAuth(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    throw ArgumentError.value(url, 'url', 'Expected an absolute OAuth URL.');
  }
  web.window.location.assign(url);
}
