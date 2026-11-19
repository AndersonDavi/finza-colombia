import 'dart:async';
import 'dart:io';

import 'package:budget/functions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Listens on 127.0.0.1 for the browser coming back from the ChatGPT sign-in

const bool loopbackSupported = true;

class LoopbackResult {
  LoopbackResult(this.query, this.redirectUri);
  final Map<String, String> query;
  final String redirectUri;
}

const String callbackPath = "/auth/callback";

// The page the browser shows at the end, in the app's own colors. On Android
// it is only seen if the redirect to the app is not followed, and its button
// uses the same link; elsewhere it just says to go back.
// cancelled: the sign-in was not finished or not allowed
String doneHtml(String? androidPackage, {bool cancelled = false}) {
  String title = cancelled ? "No se completó" : "¡Listo!";
  String message = cancelled
      ? "No se terminó el inicio de sesión. Vuelve a Finza e inténtalo otra vez."
      : "Tu cuenta de ChatGPT quedó conectada. Ya puedes volver a Finza.";
  String icon = cancelled
      ? """<path d="M12 8v5"/><path d="M12 16.5h.01"/>"""
      : """<path d="M7.5 12.5l3 3 6-6.5"/>""";
  String back = androidPackage == null
      ? ""
      : """<a class="button" href="${appReturnLink(androidPackage)}">Volver a Finza</a>""";
  return """<!doctype html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#0D0C17">
<title>Finza</title>
<style>
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body {
    background: #0D0C17; color: #E6E3FF;
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    display: flex; align-items: center; justify-content: center; padding: 24px;
  }
  .card {
    width: 100%; max-width: 420px; text-align: center;
    background: #1B1A2B; border-radius: 28px; padding: 40px 28px 32px;
  }
  .brand { font-weight: 800; font-size: 20px; letter-spacing: .3px;
    color: #C5C2FF; margin-bottom: 28px; }
  .icon { width: 76px; height: 76px; margin: 0 auto 22px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    background: ${cancelled ? "rgba(239,83,80,.16)" : "rgba(102,187,106,.16)"}; }
  .icon svg { width: 40px; height: 40px; fill: none;
    stroke: ${cancelled ? "#EF5350" : "#66BB6A"}; stroke-width: 2.4;
    stroke-linecap: round; stroke-linejoin: round; }
  h1 { margin: 0 0 10px; font-size: 28px; }
  p { margin: 0; font-size: 17px; line-height: 1.45; color: #B4B1D6; }
  .button { display: block; margin-top: 28px; padding: 17px 20px;
    border-radius: 18px; background: #C5C2FF; color: #1B1A2B;
    font-size: 17px; font-weight: 700; text-decoration: none; }
</style></head>
<body><main class="card">
<div class="brand">Finza</div>
<div class="icon"><svg viewBox="0 0 24 24">$icon</svg></div>
<h1>$title</h1><p>$message</p>$back
</main></body></html>""";
}

// The app's own link (its scheme is set in build.gradle.kts): the test build
// has its own so it never opens the real Finza
String appReturnLink(String androidPackage) =>
    (androidPackage.endsWith(".debug") ? "finzadebug" : "finza") +
    "://auth/done";

// On Android the sign-in opens in a browser tab on top of Finza, so going
// back lands in the app; elsewhere in the default browser
Future<void> openSignInPage(Uri url) async {
  if (Platform.isAndroid) {
    try {
      if (await launchUrl(url, mode: LaunchMode.inAppBrowserView)) return;
    } catch (e) {
      print("In-app browser tab failed: " + e.toString());
    }
  }
  await openUrl(url.toString());
}

Future<LoopbackResult> runLoopbackSignIn(
    Uri Function(String redirectUri) authorizeUrl) async {
  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  String redirectUri =
      "http://127.0.0.1:" + server.port.toString() + callbackPath;
  try {
    String? androidPackage = Platform.isAndroid
        ? (await PackageInfo.fromPlatform()).packageName
        : null;
    await openSignInPage(authorizeUrl(redirectUri));
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
      bool cancelled = request.uri.queryParameters["error"] != null;
      if (androidPackage != null) {
        // A redirect to the app's own link: Android opens Finza right away
        // (a page or a script cannot do it reliably). The page is only the
        // fallback if the browser does not follow it
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set(HttpHeaders.locationHeader, appReturnLink(androidPackage));
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(doneHtml(androidPackage, cancelled: cancelled));
      await request.response.close();
      return LoopbackResult(request.uri.queryParameters, redirectUri);
    }
    throw TimeoutException("ChatGPT sign-in took too long");
  } finally {
    await server.close(force: true);
  }
}
