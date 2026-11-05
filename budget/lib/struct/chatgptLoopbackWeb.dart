// A page on the web cannot listen on 127.0.0.1, so there is no ChatGPT
// sign-in there; the API key providers still work

const bool loopbackSupported = false;

class LoopbackResult {
  LoopbackResult(this.query, this.redirectUri);
  final Map<String, String> query;
  final String redirectUri;
}

Future<LoopbackResult> runLoopbackSignIn(
    Uri Function(String redirectUri) authorizeUrl) {
  throw UnsupportedError("ChatGPT sign-in needs the Windows or Android app");
}
