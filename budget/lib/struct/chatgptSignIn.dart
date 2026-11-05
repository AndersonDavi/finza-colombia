import 'dart:convert';
import 'dart:math';

import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/chatgptLoopback.dart'
    if (dart.library.html) 'package:budget/struct/chatgptLoopbackWeb.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

// Sign in with ChatGPT, the variant that lets an open-source app use the
// user's ChatGPT plan instead of an API key. Built from OpenAI's docs:
// https://developers.openai.com/siwc/token-sharing-open-source
// The browser comes back to http://127.0.0.1:<port>/auth/callback, so it only
// works where the app can listen on the device: Windows and Android, not web.

const String chatGptIssuer = "https://auth.openai.com";
const String chatGptAuthorizeUrl =
    "https://auth.openai.com/api/accounts/authorize";
const String chatGptTokenUrl =
    "https://auth.openai.com/api/accounts/oauth/token";
const String chatGptRevokeUrl =
    "https://auth.openai.com/api/accounts/oauth/revoke";
const String chatGptResource = "https://api.openai.com/v1";
const String chatGptPlanScope = "chatgpt.tokens.use.direct";
const String chatGptScopes =
    "openid profile email offline_access resource.invoke " + chatGptPlanScope;
const String chatGptUsageUrl = "https://chatgpt.com/settings/usage";

bool get chatGptSignInSupported => loopbackSupported;

String randomUrlSafe([int bytes = 32]) {
  Random random = Random.secure();
  return base64Url
      .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
      .replaceAll("=", "");
}

String pkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll(
          "=",
          "",
        );

// The payload of a JWT. The ID token comes straight from the token endpoint
// over TLS, so its claims are checked without verifying the signature
Map<String, dynamic> jwtPayload(String token) {
  List<String> parts = token.split(".");
  if (parts.length != 3) return {};
  String payload = parts[1];
  payload = payload.padRight((payload.length + 3) ~/ 4 * 4, "=");
  return jsonDecode(utf8.decode(base64Url.decode(payload)));
}

class ChatGptSession {
  static const String storageKey = "chatgpt-session";
  static const String hostIdKey = "chatgpt-host-id";
  static const String clientIdKey = "chatgpt-client-id";

  // An opaque id for this install, made once before the first sign-in
  static Future<String> hostId() async {
    String? id = await secureStorage.read(key: hostIdKey);
    if (id != null) return id;
    Random random = Random.secure();
    List<int> b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex = b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();
    id = "urn:uuid:" +
        [
          hex.substring(0, 8),
          hex.substring(8, 12),
          hex.substring(12, 16),
          hex.substring(16, 20),
          hex.substring(20)
        ].join("-");
    await secureStorage.write(key: hostIdKey, value: id);
    return id;
  }

  static Future<Map<String, dynamic>?> read() async {
    String? raw = await secureStorage.read(key: storageKey);
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  static Future<bool> isSignedIn() async => (await read()) != null;

  static Future<String?> email() async => (await read())?["email"];

  static Future<void> signIn() async {
    if (chatGptSignInSupported == false) throw AiError("ai-plan-not-on-web");
    String? clientId = await secureStorage.read(key: clientIdKey);
    String verifier = randomUrlSafe();
    String state = randomUrlSafe();
    String nonce = randomUrlSafe();
    String host = await hostId();

    LoopbackResult result = await runLoopbackSignIn((String redirectUri) {
      return Uri.parse(chatGptAuthorizeUrl).replace(queryParameters: {
        "client_id": clientId ?? "dynamic_agent_client",
        if (clientId == null) "agent_name_hint": "Finza",
        "ext_agent_host_id": host,
        "response_type": "code",
        "redirect_uri": redirectUri,
        "scope": chatGptScopes,
        "resource": chatGptResource,
        "state": state,
        "nonce": nonce,
        "code_challenge": pkceChallenge(verifier),
        "code_challenge_method": "S256",
      });
    });

    Map<String, String> query = result.query;
    if (query["error"] != null) throw AiError("ai-plan-cancelled");
    if (query["state"] != state) throw AiError("ai-failed");
    String? issuedClientId = query["client_id"] ?? clientId;
    if (issuedClientId == null || query["code"] == null) {
      throw AiError("ai-failed");
    }
    if (clientId != null && issuedClientId != clientId) {
      throw AiError("ai-failed");
    }
    // Kept before the exchange so a retry reuses the same registration
    await secureStorage.write(key: clientIdKey, value: issuedClientId);

    http.Response response = await http.post(
      Uri.parse(chatGptTokenUrl),
      headers: {"Accept": "application/json"},
      body: {
        "grant_type": "authorization_code",
        "client_id": issuedClientId,
        "code": query["code"]!,
        "code_verifier": verifier,
        "redirect_uri": result.redirectUri,
        "resource": chatGptResource,
      },
    );
    Map tokens = decodeOrThrow(response);
    if ((tokens["scope"] ?? "").toString().contains(chatGptPlanScope) ==
        false) {
      throw AiError("ai-plan-not-shared");
    }
    Map<String, dynamic> claims = jwtPayload(tokens["id_token"] ?? "");
    if (claims["iss"] != chatGptIssuer ||
        claims["nonce"] != nonce ||
        (claims["aud"] is List
            ? !(claims["aud"] as List).contains(issuedClientId)
            : claims["aud"] != issuedClientId)) {
      throw AiError("ai-failed");
    }
    await save(tokens, email: claims["email"]);
  }

  static Future<void> save(Map tokens, {String? email}) async {
    Map<String, dynamic>? previous = await read();
    await secureStorage.write(
      key: storageKey,
      value: jsonEncode({
        "accessToken": tokens["access_token"],
        "refreshToken": tokens["refresh_token"] ?? previous?["refreshToken"],
        "expiresAt": DateTime.now()
            .add(Duration(seconds: (tokens["expires_in"] ?? 3600) - 60))
            .toIso8601String(),
        "email": email ?? previous?["email"],
      }),
    );
  }

  static Future<String>? refreshing;

  // A valid access token, refreshed when it is about to expire. Refreshes run
  // one at a time because the refresh token rotates
  static Future<String> accessToken() async {
    Map<String, dynamic>? session = await read();
    if (session == null) throw AiError("ai-plan-signed-out");
    if (DateTime.parse(session["expiresAt"]).isAfter(DateTime.now())) {
      return session["accessToken"];
    }
    return await (refreshing ??= refresh().whenComplete(() {
      refreshing = null;
    }));
  }

  static Future<String> refresh() async {
    Map<String, dynamic>? session = await read();
    String? clientId = await secureStorage.read(key: clientIdKey);
    if (session == null || clientId == null) {
      throw AiError("ai-plan-signed-out");
    }
    http.Response response = await http.post(
      Uri.parse(chatGptTokenUrl),
      headers: {"Accept": "application/json"},
      body: {
        "grant_type": "refresh_token",
        "refresh_token": session["refreshToken"],
        "client_id": clientId,
        "resource": chatGptResource,
      },
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      // invalid_grant, refresh_token_reused...: only a new sign-in fixes it
      await secureStorage.delete(key: storageKey);
      throw AiError("ai-plan-signed-out");
    }
    Map tokens = decodeOrThrow(response);
    await save(tokens);
    return tokens["access_token"];
  }

  // The registration (client id and host id) stays for the next sign-in
  static Future<void> signOut() async {
    Map<String, dynamic>? session = await read();
    String? clientId = await secureStorage.read(key: clientIdKey);
    if (session != null && clientId != null) {
      try {
        await http.post(Uri.parse(chatGptRevokeUrl), body: {
          "token": session["refreshToken"],
          "token_type_hint": "refresh_token",
          "client_id": clientId,
        });
      } catch (e) {}
    }
    await secureStorage.delete(key: storageKey);
  }
}
