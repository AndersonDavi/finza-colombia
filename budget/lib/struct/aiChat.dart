import 'dart:convert';

import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/chatgptSignIn.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// The chat about the user's own money. Gemini and OpenAI take an API key;
// "chatgpt" uses the user's ChatGPT plan through Sign in with ChatGPT.
// finza: Gemini through Finza's own server (ai-proxy/), which keeps the key,
// so nobody has to create one
// In the order the chat page offers them: the free and easy ones first.
// openrouter and deepseek speak OpenAI's Chat Completions; claude speaks
// Anthropic's Messages API
enum AiProvider { finza, gemini, chatgpt, openrouter, claude, openai, deepseek }

const String finzaAiServer = "https://finza-ia.andesondavid17.workers.dev";
// The shared free assistant stays off until its server has a key; while off
// it is not offered
const bool finzaAiEnabled = false;

// The services offered in the chat page
List<AiProvider> get offeredAiProviders => [
      for (AiProvider p in AiProvider.values)
        if (p != AiProvider.finza || finzaAiEnabled) p
    ];

// The request format a provider speaks. Every request switches on this, so a
// new provider only has to be mapped here and in the helpers below
enum AiApi { gemini, responses, chatgptPlan, anthropic, chatCompletions }

AiApi aiApiOf(AiProvider provider) => switch (provider) {
      AiProvider.gemini => AiApi.gemini,
      AiProvider.openai => AiApi.responses,
      AiProvider.chatgpt => AiApi.chatgptPlan,
      AiProvider.finza => AiApi.gemini,
      AiProvider.claude => AiApi.anthropic,
      AiProvider.openrouter => AiApi.chatCompletions,
      AiProvider.deepseek => AiApi.chatCompletions,
    };

// Providers that need an API key saved on the device
bool aiNeedsApiKey(AiProvider provider) =>
    provider != AiProvider.chatgpt && provider != AiProvider.finza;

// DeepSeek's chat models read text only
bool aiReadsImages(AiProvider provider) => provider != AiProvider.deepseek;

// Where each provider hands out keys, for the "get my key" button
String? aiKeyUrl(AiProvider provider) => switch (provider) {
      AiProvider.gemini => "https://aistudio.google.com/apikey",
      AiProvider.openrouter => "https://openrouter.ai/keys",
      AiProvider.claude => "https://console.anthropic.com/settings/keys",
      AiProvider.openai => "https://platform.openai.com/api-keys",
      AiProvider.deepseek => "https://platform.deepseek.com/api_keys",
      _ => null,
    };

String chatCompletionsBaseUrl(AiProvider provider) =>
    provider == AiProvider.deepseek
        ? "https://api.deepseek.com"
        : "https://openrouter.ai/api/v1";

Future<Map<String, String>> chatCompletionsHeaders(AiProvider provider) async =>
    {
      "Authorization": "Bearer " + await requireKey(provider),
      "Content-Type": "application/json",
      // OpenRouter shows these on its activity page
      if (provider == AiProvider.openrouter) ...{
        "HTTP-Referer": "https://finza.pages.dev",
        "X-Title": "Finza",
      },
    };

const String anthropicApiVersion = "2026-10-21";
// Models that take the server-side fallback on a refusal
const List<String> anthropicFallbackModels = [
  "claude-fable-5-2",
  "claude-fable-5-1",
  "claude-opus-5-5",
  "claude-opus-5",
  "claude-sonnet-5-5",
];

Future<Map<String, String>> anthropicHeaders(AiProvider provider,
        {String? model}) async =>
    {
      "x-api-key": await requireKey(provider),
      "anthropic-version": anthropicApiVersion,
      "Content-Type": "application/json",
      // The web app calls the API straight from the browser
      "anthropic-dangerous-direct-browser-access": "true",
      if (model != null && anthropicFallbackModels.contains(model))
        "anthropic-beta": "server-side-fallback-2026-07-01",
    };

Map<String, dynamic> anthropicBody(String model, String instructions,
        List<Map<String, dynamic>> messages) =>
    {
      "model": model,
      "max_tokens": 16000,
      "system": instructions,
      "messages": messages,
      if (anthropicFallbackModels.contains(model)) "fallbacks": "default",
    };

String anthropicOutputText(Map body) {
  if (body["stop_reason"] == "refusal") throw AiError("ai-refused");
  return [
    for (Map block in body["content"] ?? [])
      if (block["type"] == "text") block["text"] ?? ""
  ].join();
}

String chatCompletionsOutputText(Map body) =>
    (body["choices"]?[0]?["message"]?["content"] ?? "").toString();

// Base URL of a provider speaking the Gemini API, without a trailing slash.
// Model names come as "models/<id>"
String geminiBaseUrl(AiProvider provider) => provider == AiProvider.finza
    ? finzaAiServer + "/v1beta"
    : "https://generativelanguage.googleapis.com/v1beta";

// Auth headers for a provider speaking the Gemini API
Future<Map<String, String>> geminiHeaders(AiProvider provider) async => {
      if (aiNeedsApiKey(provider)) "x-goog-api-key": await requireKey(provider),
    };

Uri geminiGenerateUri(AiProvider provider, String model) =>
    Uri.parse(geminiBaseUrl(provider) + "/" + model + ":generateContent");

const FlutterSecureStorage secureStorage = FlutterSecureStorage();

class ChatMessage {
  ChatMessage(this.fromUser, this.text, {this.attachment});
  final bool fromUser;
  String text;
  // A file sent with this message
  final AiAttachment? attachment;
}

class AiError implements Exception {
  AiError(this.message, {this.manageUsage = false});
  final String message;
  // The ChatGPT plan ran out: the page links to the usage settings
  final bool manageUsage;
  @override
  String toString() => message;
}

AiProvider selectedAiProvider() => offeredAiProviders.firstWhere(
      (p) => p.name == appStateSettings["aiProvider"],
      orElse: () => AiProvider.gemini,
    );

String apiKeyStorageKey(AiProvider provider) => "ai-key-" + provider.name;

Future<String?> readApiKey(AiProvider provider) =>
    secureStorage.read(key: apiKeyStorageKey(provider));

Future<void> saveApiKey(AiProvider provider, String? key) async {
  // Another key may see other models
  clearModelCache(provider);
  if (key == null || key.trim() == "") {
    await secureStorage.delete(key: apiKeyStorageKey(provider));
  } else {
    await secureStorage.write(
        key: apiKeyStorageKey(provider), value: key.trim());
  }
}

String? selectedModel(AiProvider provider) =>
    appStateSettings["aiModel-" + provider.name];

Future<void> setSelectedModel(AiProvider provider, String model) =>
    updateSettings("aiModel-" + provider.name, model, updateGlobalState: false);

// What a model can take besides text, for the model picker and to grey out
// what the selected model can't read
class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.label,
    this.readsImages = false,
    this.readsPdf = false,
    this.free = false,
    this.fast = false,
  });
  // Sent in requests
  final String id;
  // Shown in the picker
  final String label;
  final bool readsImages;
  final bool readsPdf;
  final bool free;
  final bool fast;
}

const Map<String, String> _modelWords = {
  "gemini": "Gemini",
  "gemma": "Gemma",
  "claude": "Claude",
  "deepseek": "DeepSeek",
  "openai": "OpenAI",
  "chatgpt": "ChatGPT",
  "llama": "Llama",
  "qwen": "Qwen",
};

// A readable name from a model id: "gemini-3.5-flash-lite" is
// "Gemini 3.5 Flash-Lite", "claude-opus-5-5" is "Claude Opus 5.5" and
// "gpt-5-mini-2025-08-07" is "GPT-5 Mini"
String aiModelLabel(String id) {
  String name = id.replaceFirst("models/", "");
  name = name.substring(name.lastIndexOf("/") + 1);
  name = name.replaceFirst(RegExp(r":free$"), "");
  List<String> tokens =
      name.split(RegExp(r"[-_:]")).where((t) => t.isNotEmpty).toList();
  RegExp twoDigits = RegExp(r"^\d{2}$");
  RegExp shortNumber = RegExp(r"^(0|[1-9]\d?)$");
  List<String> words = [];
  bool lastWasNumber = false;
  for (int i = 0; i < tokens.length; i++) {
    String token = tokens[i];
    String lower = token.toLowerCase();
    // Release dates: 20250929 or 2025-08-07
    if (RegExp(r"^\d{8}$").hasMatch(token)) continue;
    if (RegExp(r"^\d{4}$").hasMatch(token) &&
        i + 2 < tokens.length &&
        twoDigits.hasMatch(tokens[i + 1]) &&
        twoDigits.hasMatch(tokens[i + 2])) {
      i += 2;
      continue;
    }
    bool isNumber = shortNumber.hasMatch(token);
    if (lower == "gpt" && i + 1 < tokens.length) {
      String next = tokens[++i];
      words.add("GPT-" +
          (RegExp(r"^[a-zA-Z]+$").hasMatch(next)
              ? next.toUpperCase()
              : next.toLowerCase()));
      lastWasNumber = false;
    } else if (lower == "lite" && words.isNotEmpty && words.last == "Flash") {
      words.last = "Flash-Lite";
      lastWasNumber = false;
    } else if (isNumber && lastWasNumber) {
      // Versions written with dashes: claude-opus-5-5
      words.last += "." + token;
      lastWasNumber = false;
    } else if (RegExp(r"^o\d").hasMatch(lower)) {
      words.add(lower);
      lastWasNumber = false;
    } else {
      words.add(_modelWords[lower] ??
          token.substring(0, 1).toUpperCase() + token.substring(1));
      lastWasNumber = isNumber;
    }
  }
  return words.isEmpty ? id : words.join(" ");
}

bool _fastModelName(String id) => RegExp(r"flash|haiku|mini|nano|lite")
    .hasMatch(id.toLowerCase().replaceFirst("gemini", ""));

// Capabilities of a model. displayName is the provider's own name when the
// list has one; openRouter is the model's entry in OpenRouter's list
AiModelInfo aiModelInfoFor(
  AiProvider provider,
  String id, {
  String? displayName,
  Map? openRouter,
}) {
  String lower = id.toLowerCase();
  String label = displayName == null || displayName.trim().isEmpty
      ? aiModelLabel(id)
      : displayName.replaceFirst(RegExp(r"\s*\(free\)$"), "").trim();
  bool fast = _fastModelName(id);
  switch (aiApiOf(provider)) {
    case AiApi.gemini:
      bool gemini = lower.contains("gemini");
      return AiModelInfo(
        id: id,
        label: label,
        readsImages: true,
        readsPdf: gemini,
        // Finza's server is free; a Gemini key has a free tier for Flash
        free:
            provider == AiProvider.finza || (gemini && lower.contains("flash")),
        fast: fast,
      );
    case AiApi.responses:
      String name = lower.replaceFirst("models/", "");
      bool vision = (name.startsWith("gpt-") && !name.startsWith("gpt-3.5")) ||
          (RegExp(r"^o\d").hasMatch(name) &&
              !["o1-mini", "o1-preview", "o3-mini"]
                  .any((m) => name.startsWith(m)));
      return AiModelInfo(
        id: id,
        label: label,
        readsImages: vision,
        readsPdf: vision,
        fast: fast,
      );
    case AiApi.chatgptPlan:
      return AiModelInfo(id: id, label: label, readsImages: true, fast: fast);
    case AiApi.anthropic:
      return AiModelInfo(
        id: id,
        label: label,
        readsImages: true,
        readsPdf: true,
        fast: lower.contains("haiku"),
      );
    case AiApi.chatCompletions:
      if (provider == AiProvider.deepseek) {
        return AiModelInfo(id: id, label: label);
      }
      if (openRouter == null) {
        // Not in the list (yet): let the request try, a rejection is
        // explained by decodeOrThrow
        return AiModelInfo(
          id: id,
          label: label,
          readsImages: true,
          readsPdf: true,
          free: lower.endsWith(":free"),
          fast: fast,
        );
      }
      List inputs = openRouter["architecture"]?["input_modalities"] ?? [];
      Map pricing = openRouter["pricing"] ?? {};
      bool zero(dynamic price) => double.tryParse(price.toString()) == 0;
      return AiModelInfo(
        id: id,
        label: label,
        readsImages: inputs.contains("image"),
        readsPdf: inputs.contains("file"),
        free: lower.endsWith(":free") ||
            (zero(pricing["prompt"] ?? "") &&
                zero(pricing["completion"] ?? "0")),
        fast: fast,
      );
  }
}

// Model lists of this session, so the picker and the capability checks don't
// ask the provider again
final Map<AiProvider, List<AiModelInfo>> _modelCache = {};

void clearModelCache(AiProvider provider) => _modelCache.remove(provider);

// The selected model's capabilities, from the list when it was loaded
AiModelInfo selectedModelInfo(AiProvider provider) {
  String? id = selectedModel(provider);
  List<AiModelInfo>? models = _modelCache[provider];
  if (models != null && models.isNotEmpty) {
    return models.firstWhere((m) => m.id == id, orElse: () => models.first);
  }
  if (id == null) {
    // Nothing chosen nor listed yet: what the provider usually takes
    return AiModelInfo(
      id: "",
      label: "",
      readsImages: aiReadsImages(provider),
      readsPdf: aiReadsImages(provider) && provider != AiProvider.chatgpt,
    );
  }
  return aiModelInfoFor(provider, id);
}

AiModelInfo modelInfo(AiProvider provider, String id) =>
    _modelCache[provider]?.where((m) => m.id == id).firstOrNull ??
    aiModelInfoFor(provider, id);

// Models the provider offers for chatting, best guess first
Future<List<AiModelInfo>> listModels(AiProvider provider,
    {bool refresh = false}) async {
  if (refresh == false && _modelCache[provider] != null) {
    return _modelCache[provider]!;
  }
  List<AiModelInfo> models = await _fetchModels(provider);
  _modelCache[provider] = models;
  return models;
}

Future<List<AiModelInfo>> _fetchModels(AiProvider provider) async {
  switch (aiApiOf(provider)) {
    case AiApi.gemini:
      http.Response response = await http.get(
        Uri.parse(geminiBaseUrl(provider) + "/models"),
        headers: await geminiHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      List<AiModelInfo> models = [
        for (Map model in body["models"] ?? [])
          if ((model["supportedGenerationMethods"] ?? [])
              .contains("generateContent"))
            aiModelInfoFor(provider, model["name"].toString(),
                displayName: model["displayName"]?.toString())
      ];
      // Flash models are fast and cheap, enough for questions about money.
      // The shared free server prefers Flash-Lite, which has a larger daily
      // allowance
      String preferred = provider == AiProvider.finza ? "flash-lite" : "flash";
      models.sort((a, b) => (b.id.contains(preferred) ? 1 : 0)
          .compareTo(a.id.contains(preferred) ? 1 : 0));
      return models;
    case AiApi.responses:
      String key = await requireKey(provider);
      http.Response response = await http.get(
        Uri.parse("https://api.openai.com/v1/models"),
        headers: {"Authorization": "Bearer " + key},
      );
      Map body = decodeOrThrow(response);
      // The list mixes chat models with audio, image and embedding ones; keep
      // the chat ones, small and cheap ("mini") first, newest names first
      const List<String> notChat = [
        "audio",
        "realtime",
        "tts",
        "transcribe",
        "image",
        "search",
        "embedding",
        "moderation",
        "whisper",
        "dall-e",
        "babbage",
        "davinci",
        "instruct",
        "codex",
        "computer-use",
      ];
      List<String> ids = [
        for (Map model in body["data"] ?? [])
          if ((model["id"].toString().startsWith("gpt-") ||
                  RegExp(r"^o\d").hasMatch(model["id"].toString())) &&
              notChat.every((word) => !model["id"].toString().contains(word)))
            model["id"].toString()
      ]..sort((a, b) => b.compareTo(a));
      ids.sort((a, b) =>
          (b.contains("mini") ? 1 : 0).compareTo(a.contains("mini") ? 1 : 0));
      return [for (String id in ids) aiModelInfoFor(provider, id)];
    case AiApi.chatgptPlan:
      String token = await ChatGptSession.accessToken();
      http.Response response = await http.get(
        Uri.parse("https://api.openai.com/v1/models"),
        headers: {"Authorization": "Bearer " + token},
      );
      Map body = decodeOrThrow(response);
      // Keep the server's order, it puts the recommended model first
      return [
        for (Map model in body["models"] ?? [])
          if (model["visibility"] == "list")
            aiModelInfoFor(provider, model["slug"].toString(),
                displayName: model["display_name"]?.toString())
      ];
    case AiApi.anthropic:
      http.Response response = await http.get(
        Uri.parse("https://api.anthropic.com/v1/models?limit=100"),
        headers: await anthropicHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      List<AiModelInfo> models = [
        for (Map model in body["data"] ?? [])
          aiModelInfoFor(provider, model["id"].toString(),
              displayName: model["display_name"]?.toString())
      ];
      // The current Opus first; the person can pick another in the list
      models.sort((a, b) => (b.id == "claude-opus-5-5" ? 1 : 0)
          .compareTo(a.id == "claude-opus-5-5" ? 1 : 0));
      return models;
    case AiApi.chatCompletions:
      http.Response response = await http.get(
        Uri.parse(chatCompletionsBaseUrl(provider) + "/models"),
        headers: await chatCompletionsHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      bool openRouter = provider == AiProvider.openrouter;
      List<AiModelInfo> models = [
        for (Map model in body["data"] ?? [])
          aiModelInfoFor(provider, model["id"].toString(),
              displayName: openRouter ? model["name"]?.toString() : null,
              openRouter: openRouter ? model : null)
      ];
      if (openRouter) {
        // Free models first; they cost nothing with a free OpenRouter key
        models.sort((a, b) => (b.free ? 1 : 0).compareTo(a.free ? 1 : 0));
      } else {
        models.sort((a, b) => (b.id == "deepseek-chat" ? 1 : 0)
            .compareTo(a.id == "deepseek-chat" ? 1 : 0));
      }
      return models;
  }
}

Future<String> requireKey(AiProvider provider) async {
  String? key = await readApiKey(provider);
  if (key == null) throw AiError("ai-missing-key");
  return key;
}

Map decodeOrThrow(http.Response response) {
  Map body = {};
  try {
    body = jsonDecode(utf8.decode(response.bodyBytes));
  } catch (e) {}
  if (response.statusCode >= 200 && response.statusCode < 300) return body;
  dynamic error = body["error"];
  String code = error is Map ? (error["code"] ?? "").toString() : "";
  // Anthropic names the kind of error in "type"
  String type = error is Map ? (error["type"] ?? "").toString() : "";
  if (code == "subscription_sharing_usage_limit_exceeded") {
    throw AiError("ai-plan-limit-reached", manageUsage: true);
  }
  if (code == "subscription_sharing_user_not_eligible") {
    throw AiError("ai-plan-not-eligible");
  }
  String status = error is Map ? (error["status"] ?? '').toString() : '';
  String message = error is Map
      ? (error["message"] ?? response.reasonPhrase).toString()
      : response.reasonPhrase ?? response.statusCode.toString();
  // Finza's server runs before its key is set up
  if (response.statusCode == 503 && message.contains("not set up")) {
    throw AiError("ai-free-not-ready");
  }
  // No balance left: OpenAI's code, OpenRouter's and DeepSeek's 402, and
  // Anthropic's message
  if (code == "insufficient_quota" ||
      response.statusCode == 402 ||
      message.contains("credit balance")) {
    throw AiError("ai-no-credit");
  }
  if (type == "authentication_error") throw AiError("ai-invalid-key");
  // Gemini's free allowance used up for now
  if (status == "RESOURCE_EXHAUSTED") throw AiError("ai-free-quota-used");
  if (response.statusCode == 429) throw AiError("ai-too-many-requests");
  if (response.statusCode == 401 ||
      code == "invalid_api_key" ||
      message.contains("API key not valid") ||
      message.contains("API_KEY_INVALID")) {
    throw AiError("ai-invalid-key");
  }
  if (response.statusCode == 413) throw AiError("ai-file-too-big");
  if (rejectsContent(response.statusCode, message)) {
    throw AiError("ai-content-not-supported");
  }
  if (response.statusCode >= 500) throw AiError("ai-provider-down");
  throw AiError(message);
}

// A provider refusing an image or file the model can't take, e.g. "does not
// support image input" or OpenRouter's "No endpoints found that support
// image input"
bool rejectsContent(int statusCode, String message) {
  if (statusCode != 400 &&
      statusCode != 404 &&
      statusCode != 415 &&
      statusCode != 422) {
    return false;
  }
  String m = message.toLowerCase();
  bool aboutContent =
      RegExp(r"image|vision|pdf|document|file input|input_file|modalit|mime")
          .hasMatch(m);
  bool refused =
      RegExp(r"support|not allowed|invalid|cannot|can't|unable").hasMatch(m);
  return aboutContent && refused;
}

const String financeInstructions = """
You are the assistant inside Finza, a personal finance app. Answer in the
user's language, short and concrete, using the data below when the question
is about their money. Amounts are in each pocket's currency. An account is
where the money is kept (a bank, a digital wallet, cash); pockets split the
money of an account. When the data does not answer the question, say so
instead of guessing. You give general information, not professional
financial or tax advice.""";

// Sends the conversation and returns the answer. onDelta gets the text as it
// arrives, for providers that stream it.
// Only the latest attachment goes with its message; older ones are replaced
// by a note with their name, which keeps requests small
Future<String> sendChat(
  List<ChatMessage> conversation, {
  required String? financeContext,
  void Function(String textSoFar)? onDelta,
}) async {
  AiProvider provider = selectedAiProvider();
  String model = await ensureModel(provider);
  String instructions = financeInstructions +
      (financeContext == null ? "" : "\n\nUser data:\n" + financeContext);
  AiApi api = aiApiOf(provider);
  AiModelInfo info = modelInfo(provider, model);
  int attached = conversation.lastIndexWhere((m) => m.attachment != null);
  if (attached != -1) {
    AiAttachment attachment = conversation[attached].attachment!;
    String? refusal = attachmentRefusal(attachment, info, api);
    if (refusal != null) {
      // Asked now: explain. Sent earlier with another model: drop it to a note
      if (attached == conversation.length - 1) throw AiError(refusal);
      attached = -1;
    }
  }
  List<AiChatTurn> turns = [
    for (int i = 0; i < conversation.length; i++)
      AiChatTurn.of(conversation[i], withAttachment: i == attached)
  ];

  switch (api) {
    case AiApi.gemini:
      http.Response response = await http.post(
        geminiGenerateUri(provider, model),
        headers: {
          ...await geminiHeaders(provider),
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "systemInstruction": {
            "parts": [
              {"text": instructions}
            ]
          },
          "contents": [
            for (AiChatTurn turn in turns)
              {
                "role": turn.fromUser ? "user" : "model",
                "parts": geminiParts(turn.text, turn.file),
              }
          ],
        }),
      );
      return geminiOutputText(decodeOrThrow(response));
    case AiApi.responses:
      String key = await requireKey(provider);
      http.Response response = await http.post(
        Uri.parse("https://api.openai.com/v1/responses"),
        headers: {
          "Authorization": "Bearer " + key,
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "model": model,
          "instructions": instructions,
          "input": responsesInput(turns),
        }),
      );
      return responsesOutputText(decodeOrThrow(response));
    case AiApi.chatgptPlan:
      return await streamChatGptResponse(
        model: model,
        instructions: instructions,
        input: responsesInput(turns),
        onDelta: onDelta,
      );
    case AiApi.anthropic:
      http.Response response = await http.post(
        Uri.parse("https://api.anthropic.com/v1/messages"),
        headers: await anthropicHeaders(provider, model: model),
        body: jsonEncode(anthropicBody(model, instructions, [
          for (AiChatTurn turn in turns)
            {
              "role": turn.fromUser ? "user" : "assistant",
              "content": anthropicContent(turn.text, turn.file),
            }
        ])),
      );
      return anthropicOutputText(decodeOrThrow(response));
    case AiApi.chatCompletions:
      http.Response response = await http.post(
        Uri.parse(chatCompletionsBaseUrl(provider) + "/chat/completions"),
        headers: await chatCompletionsHeaders(provider),
        body: jsonEncode({
          "model": model,
          "messages": [
            {"role": "system", "content": instructions},
            for (AiChatTurn turn in turns)
              {
                "role": turn.fromUser ? "user" : "assistant",
                "content": chatCompletionsContent(turn.text, turn.file),
              }
          ],
        }),
      );
      return chatCompletionsOutputText(decodeOrThrow(response));
  }
}

// Why the model can't take an attachment (a translation key), or null
String? attachmentRefusal(
    AiAttachment attachment, AiModelInfo info, AiApi api) {
  switch (attachment.kind) {
    case AiAttachmentKind.image:
      return info.readsImages ? null : "ai-model-no-photos";
    case AiAttachmentKind.pdf:
      // The ChatGPT plan route takes images only
      return info.readsPdf && api != AiApi.chatgptPlan
          ? null
          : "ai-model-no-pdf";
    case AiAttachmentKind.text:
      return null;
  }
}

// A message as sent: the text, with a text file folded in, and the image or
// PDF that goes as its own part
class AiChatTurn {
  AiChatTurn(this.fromUser, this.text, this.file);
  final bool fromUser;
  final String text;
  final AiAttachment? file;

  factory AiChatTurn.of(ChatMessage message, {required bool withAttachment}) {
    AiAttachment? attachment = message.attachment;
    if (attachment == null) {
      return AiChatTurn(message.fromUser, message.text, null);
    }
    String text = message.text.trim();
    String join(String extra) => text == "" ? extra : text + "\n\n" + extra;
    if (withAttachment == false) {
      return AiChatTurn(
          message.fromUser,
          join("[Attached earlier, not included now: ${attachment.name}]"),
          null);
    }
    if (attachment.kind == AiAttachmentKind.text) {
      return AiChatTurn(
          message.fromUser,
          join('Attached file "${attachment.name}":\n' + attachment.text!),
          null);
    }
    return AiChatTurn(message.fromUser,
        join("Attached file: " + attachment.name), attachment);
  }
}

List<Map<String, dynamic>> geminiParts(String text, AiAttachment? file) => [
      {"text": text},
      if (file != null)
        {
          "inline_data": {
            "mime_type": file.mimeType,
            "data": file.base64Data,
          }
        },
    ];

dynamic anthropicContent(String text, AiAttachment? file) {
  if (file == null) return text;
  return [
    // Files go before the question
    {
      "type": file.kind == AiAttachmentKind.pdf ? "document" : "image",
      "source": {
        "type": "base64",
        "media_type": file.mimeType,
        "data": file.base64Data,
      }
    },
    {"type": "text", "text": text},
  ];
}

dynamic chatCompletionsContent(String text, AiAttachment? file) {
  if (file == null) return text;
  return [
    {"type": "text", "text": text},
    if (file.kind == AiAttachmentKind.pdf)
      {
        "type": "file",
        "file": {"filename": file.name, "file_data": file.dataUrl}
      }
    else
      {
        "type": "image_url",
        "image_url": {"url": file.dataUrl}
      },
  ];
}

dynamic responsesContent(String text, AiAttachment? file) {
  if (file == null) return text;
  return [
    {"type": "input_text", "text": text},
    if (file.kind == AiAttachmentKind.pdf)
      {"type": "input_file", "filename": file.name, "file_data": file.dataUrl}
    else
      {"type": "input_image", "image_url": file.dataUrl},
  ];
}

// The model picked in the chat page, or the provider's first one
Future<String> ensureModel(AiProvider provider) async {
  String? model = selectedModel(provider);
  if (model != null) return model;
  List<AiModelInfo> models = await listModels(provider);
  if (models.isEmpty) throw AiError("ai-no-models");
  await setSelectedModel(provider, models.first.id);
  return models.first.id;
}

String geminiOutputText(Map body) {
  List parts = body["candidates"]?[0]?["content"]?["parts"] ?? [];
  return parts.map((p) => p["text"] ?? "").join();
}

// An image for the model, already resized
class AiImage {
  AiImage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;

  String get base64Data => base64Encode(bytes);
  String get dataUrl => "data:" + mimeType + ";base64," + base64Data;
}

enum AiAttachmentKind { image, pdf, text }

// A file sent with a chat message. Images and PDFs go as they are; CSV,
// Excel and text files are turned into text on the device first
class AiAttachment {
  AiAttachment.image(this.name, AiImage image)
      : kind = AiAttachmentKind.image,
        bytes = image.bytes,
        mimeType = image.mimeType,
        text = null;
  AiAttachment.pdf(this.name, Uint8List this.bytes)
      : kind = AiAttachmentKind.pdf,
        mimeType = "application/pdf",
        text = null;
  AiAttachment.text(this.name, String this.text)
      : kind = AiAttachmentKind.text,
        bytes = null,
        mimeType = "text/plain";

  final String name;
  final AiAttachmentKind kind;
  final Uint8List? bytes;
  final String mimeType;
  final String? text;

  // Plain base64, no line breaks
  String get base64Data => base64Encode(bytes ?? []);
  String get dataUrl => "data:" + mimeType + ";base64," + base64Data;
}

// One request with no history: instructions, a text and an optional image.
// Returns the model's text. With json the providers that allow it are asked
// for a JSON object; the prompt should ask for JSON too
Future<String> sendPrompt({
  required String instructions,
  required String text,
  AiImage? image,
  bool json = false,
}) async {
  AiProvider provider = selectedAiProvider();
  if (image != null && !aiReadsImages(provider)) throw AiError("ai-no-vision");
  String model = await ensureModel(provider);
  if (image != null && !modelInfo(provider, model).readsImages) {
    throw AiError("ai-model-no-photos");
  }
  switch (aiApiOf(provider)) {
    case AiApi.gemini:
      http.Response response = await http.post(
        geminiGenerateUri(provider, model),
        headers: {
          ...await geminiHeaders(provider),
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "systemInstruction": {
            "parts": [
              {"text": instructions}
            ]
          },
          "contents": [
            {
              "role": "user",
              "parts": [
                {"text": text},
                if (image != null)
                  {
                    "inline_data": {
                      "mime_type": image.mimeType,
                      "data": image.base64Data,
                    }
                  },
              ]
            }
          ],
          if (json)
            "generationConfig": {"responseMimeType": "application/json"},
        }),
      );
      return geminiOutputText(decodeOrThrow(response));
    case AiApi.responses:
      String key = await requireKey(provider);
      http.Response response = await http.post(
        Uri.parse("https://api.openai.com/v1/responses"),
        headers: {
          "Authorization": "Bearer " + key,
          "Content-Type": "application/json"
        },
        body: jsonEncode({
          "model": model,
          "instructions": instructions,
          "input": responsesPromptInput(text, image),
          if (json)
            "text": {
              "format": {"type": "json_object"}
            },
        }),
      );
      return responsesOutputText(decodeOrThrow(response));
    case AiApi.chatgptPlan:
      // The plan route takes no output options, the prompt asks for JSON
      return await streamChatGptResponse(
        model: model,
        instructions: instructions,
        input: responsesPromptInput(text, image),
      );
    case AiApi.anthropic:
      // No output option for free-form JSON here; the prompt asks for it and
      // the reply is parsed defensively
      http.Response response = await http.post(
        Uri.parse("https://api.anthropic.com/v1/messages"),
        headers: await anthropicHeaders(provider, model: model),
        body: jsonEncode(anthropicBody(model, instructions, [
          {
            "role": "user",
            "content": [
              if (image != null)
                {
                  "type": "image",
                  "source": {
                    "type": "base64",
                    "media_type": image.mimeType,
                    "data": image.base64Data,
                  }
                },
              {"type": "text", "text": text},
            ]
          }
        ])),
      );
      return anthropicOutputText(decodeOrThrow(response));
    case AiApi.chatCompletions:
      http.Response response = await http.post(
        Uri.parse(chatCompletionsBaseUrl(provider) + "/chat/completions"),
        headers: await chatCompletionsHeaders(provider),
        body: jsonEncode({
          "model": model,
          "messages": [
            {"role": "system", "content": instructions},
            {
              "role": "user",
              "content": image == null
                  ? text
                  : [
                      {"type": "text", "text": text},
                      {
                        "type": "image_url",
                        "image_url": {"url": image.dataUrl}
                      },
                    ]
            }
          ],
          if (json && provider == AiProvider.deepseek)
            "response_format": {"type": "json_object"},
        }),
      );
      return chatCompletionsOutputText(decodeOrThrow(response));
  }
}

List<Map<String, dynamic>> responsesPromptInput(String text, AiImage? image) =>
    [
      {
        "role": "user",
        "content": [
          {"type": "input_text", "text": text},
          if (image != null)
            {"type": "input_image", "image_url": image.dataUrl},
        ]
      }
    ];

List<Map<String, dynamic>> responsesInput(List<AiChatTurn> turns) => [
      for (AiChatTurn turn in turns)
        {
          "role": turn.fromUser ? "user" : "assistant",
          "content": responsesContent(turn.text, turn.file),
        }
    ];

String responsesOutputText(Map body) {
  String text = "";
  for (Map item in body["output"] ?? []) {
    if (item["type"] != "message") continue;
    for (Map content in item["content"] ?? []) {
      if (content["type"] == "output_text") text += content["text"] ?? "";
    }
  }
  return text;
}

// The plan route only answers as a stream (store:false, stream:true) and a
// reply only counts once response.completed arrives
Future<String> streamChatGptResponse({
  required String model,
  required String instructions,
  required List<Map<String, dynamic>> input,
  void Function(String textSoFar)? onDelta,
}) async {
  String token = await ChatGptSession.accessToken();
  http.Request request =
      http.Request("POST", Uri.parse("https://api.openai.com/v1/responses"));
  request.headers.addAll({
    "Authorization": "Bearer " + token,
    "Content-Type": "application/json",
    "Accept": "text/event-stream",
  });
  request.body = jsonEncode({
    "model": model,
    "instructions": instructions,
    "input": input,
    "store": false,
    "stream": true,
  });
  http.StreamedResponse response = await http.Client().send(request);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    decodeOrThrow(await http.Response.fromStream(response));
  }
  String text = "";
  bool completed = false;
  String buffer = "";
  await for (String chunk in response.stream.transform(utf8.decoder)) {
    buffer += chunk;
    while (buffer.contains("\n")) {
      int end = buffer.indexOf("\n");
      String line = buffer.substring(0, end).trim();
      buffer = buffer.substring(end + 1);
      if (line.startsWith("data:") == false) continue;
      String data = line.substring(5).trim();
      if (data == "" || data == "[DONE]") continue;
      Map event;
      try {
        event = jsonDecode(data);
      } catch (e) {
        continue;
      }
      String type = event["type"] ?? "";
      if (type == "response.output_text.delta") {
        text += event["delta"] ?? "";
        onDelta?.call(text);
      } else if (type == "response.completed") {
        completed = true;
      } else if (type == "response.failed" || type == "error") {
        Map? error = event["response"]?["error"] ?? event["error"];
        String code = (error?["code"] ?? "").toString();
        if (code == "subscription_sharing_usage_limit_exceeded") {
          throw AiError("ai-plan-limit-reached", manageUsage: true);
        }
        throw AiError((error?["message"] ?? "ai-failed").toString());
      }
    }
  }
  if (completed == false) throw AiError("ai-failed");
  return text;
}

// A compact summary of the user's money for the model: balances, this month
// by category, recent movements and what is coming up
Future<String> buildFinanceContext(AllWallets allWallets) async {
  StringBuffer out = StringBuffer();
  DateTime now = DateTime.now();
  out.writeln("Today: " + now.toIso8601String().substring(0, 10));
  out.writeln("Country: " + (livesInColombia() ? "Colombia" : "not set"));

  Map<String, TransactionCategory> categories = {
    for (TransactionCategory c in await database.getAllCategories())
      c.categoryPk: c
  };
  Map<String, WalletGroup> groups = {
    for (WalletGroup g in await database.getAllWalletGroups())
      g.walletGroupPk: g
  };

  final total = database.transactions.amount
      .sum(filter: database.transactions.paid.equals(true));
  List<TypedResult> rows = await (database.selectOnly(database.transactions)
        ..addColumns([database.transactions.walletFk, total])
        ..groupBy([database.transactions.walletFk]))
      .get();
  Map<String, double> balances = {
    for (TypedResult row in rows)
      row.read(database.transactions.walletFk)!: row.read(total) ?? 0
  };
  out.writeln("\nPockets (account / pocket: balance):");
  for (TransactionWallet wallet in allWallets.list) {
    if (wallet.archived) continue;
    String account = groups[wallet.walletGroupFk]?.name ?? "-";
    out.writeln("- $account / ${wallet.name}: " +
        convertToMoney(allWallets, balances[wallet.walletPk] ?? 0,
            currencyKey: wallet.currency));
  }

  List<Transaction> recent = await (database.select(database.transactions)
        ..where((t) =>
            t.paid.equals(true) &
            t.dateCreated
                .isBiggerOrEqualValue(DateTime(now.year, now.month - 2, 1)))
        ..orderBy([(t) => OrderingTerm.desc(t.dateCreated)]))
      .get();

  Map<String, double> monthByCategory = {};
  for (Transaction t in recent) {
    if (t.dateCreated.isBefore(DateTime(now.year, now.month, 1))) continue;
    if (t.categoryFk == "0") continue;
    String name = categories[t.categoryFk]?.name ?? "?";
    monthByCategory[(t.income ? "income: " : "expense: ") + name] =
        (monthByCategory[(t.income ? "income: " : "expense: ") + name] ?? 0) +
            t.amount;
  }
  out.writeln("\nThis month by category (primary currency):");
  for (MapEntry<String, double> entry in monthByCategory.entries) {
    out.writeln("- ${entry.key}: " + convertToMoney(allWallets, entry.value));
  }

  out.writeln("\nLast movements (date, title, category, pocket, amount):");
  for (Transaction t in recent.take(150)) {
    out.writeln([
      t.dateCreated.toIso8601String().substring(0, 10),
      t.name,
      categories[t.categoryFk]?.name ?? "",
      allWallets.indexedByPk[t.walletFk]?.name ?? "",
      convertToMoney(allWallets, t.amount,
          currencyKey: allWallets.indexedByPk[t.walletFk]?.currency),
    ].join(" | "));
  }

  List<Transaction> upcoming = await database.getAllUpcomingTransactions(
    startDate: now.subtract(Duration(days: 30)),
    endDate: now.add(Duration(days: 45)),
  );
  out.writeln("\nUpcoming and overdue payments:");
  for (Transaction t in upcoming) {
    out.writeln("- " +
        t.dateCreated.toIso8601String().substring(0, 10) +
        " " +
        t.name +
        ": " +
        convertToMoney(allWallets, t.amount,
            currencyKey: allWallets.indexedByPk[t.walletFk]?.currency));
  }
  return out.toString();
}
