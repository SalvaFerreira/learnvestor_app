import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;

@JS('learnvestorDemoApi')
external JSPromise<_DemoResponse> _demoApi(JSString method, JSString url, JSString headersJson, JSString body);

extension type _DemoResponse(JSObject _) implements JSObject {
  external int get status;
  external String get body;
}

/// DEMO builds only: answers every Supabase request in the browser through
/// `window.learnvestorDemoApi` (tools/web-demo/browser.mjs, loaded by the demo's
/// index.html), which runs the real database and RPCs on PGlite. Nothing goes to a server.
class DemoHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final response = await _demoApi(
      request.method.toJS,
      request.url.toString().toJS,
      jsonEncode(request.headers).toJS,
      body.toJS,
    ).toDart;
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}
