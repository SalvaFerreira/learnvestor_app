import 'package:http/http.dart' as http;

/// The browser demo only exists on the web (see demo_http_client_web.dart).
class DemoHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnsupportedError('DEMO builds only run in the browser (flutter build web)');
}
