import 'dart:async';
import 'dart:io';

import 'package:budget/functions.dart';

// Listens on 127.0.0.1 for the browser coming back from the ChatGPT sign-in

const bool loopbackSupported = true;

class LoopbackResult {
  LoopbackResult(this.query, this.redirectUri);
  final Map<String, String> query;
  final String redirectUri;
}

const String callbackPath = "/auth/callback";

const String doneHtml = """<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Finza</title></head>
<body style="font-family:sans-serif;text-align:center;padding:48px">
<h2>Listo</h2><p>Ya puedes volver a Finza.</p></body></html>""";

Future<LoopbackResult> runLoopbackSignIn(
    Uri Function(String redirectUri) authorizeUrl) async {
  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  String redirectUri =
      "http://127.0.0.1:" + server.port.toString() + callbackPath;
  try {
    await openUrl(authorizeUrl(redirectUri).toString());
    await for (HttpRequest request
        in server.timeout(Duration(minutes: 5), onTimeout: (sink) {
      sink.close();
    })) {
      // Only the browser coming back to this exact address counts
      if (request.uri.path != callbackPath ||
          request.headers.host != "127.0.0.1") {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(doneHtml);
      await request.response.close();
      return LoopbackResult(request.uri.queryParameters, redirectUri);
    }
    throw TimeoutException("ChatGPT sign-in took too long");
  } finally {
    await server.close(force: true);
  }
}
