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
  ChatMessage(this.fromUser, this.text);
  final bool fromUser;
  String text;
}

class AiError implements Exception {
  AiError(this.message, {this.manageUsage = false});
  final String message;
  // The ChatGPT plan ran out: the page links to the usage settings
  final bool manageUsage;
  @override
  String toString() => message;
}

AiProvider selectedAiProvider() => AiProvider.values.firstWhere(
      (p) => p.name == appStateSettings["aiProvider"],
      orElse: () => AiProvider.gemini,
    );

String apiKeyStorageKey(AiProvider provider) => "ai-key-" + provider.name;

Future<String?> readApiKey(AiProvider provider) =>
    secureStorage.read(key: apiKeyStorageKey(provider));

Future<void> saveApiKey(AiProvider provider, String? key) async {
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

// Models the provider offers for chatting, best guess first
Future<List<String>> listModels(AiProvider provider) async {
  switch (aiApiOf(provider)) {
    case AiApi.gemini:
      http.Response response = await http.get(
        Uri.parse(geminiBaseUrl(provider) + "/models"),
        headers: await geminiHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      List<String> models = [
        for (Map model in body["models"] ?? [])
          if ((model["supportedGenerationMethods"] ?? [])
              .contains("generateContent"))
            model["name"].toString()
      ];
      // Flash models are fast and cheap, enough for questions about money.
      // The shared free server prefers Flash-Lite, which has a larger daily
      // allowance
      String preferred = provider == AiProvider.finza ? "flash-lite" : "flash";
      models.sort((a, b) => (b.contains(preferred) ? 1 : 0)
          .compareTo(a.contains(preferred) ? 1 : 0));
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
      List<String> models = [
        for (Map model in body["data"] ?? [])
          if ((model["id"].toString().startsWith("gpt-") ||
                  RegExp(r"^o\d").hasMatch(model["id"].toString())) &&
              notChat.every((word) => !model["id"].toString().contains(word)))
            model["id"].toString()
      ]..sort((a, b) => b.compareTo(a));
      models.sort((a, b) =>
          (b.contains("mini") ? 1 : 0).compareTo(a.contains("mini") ? 1 : 0));
      return models;
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
          if (model["visibility"] == "list") model["slug"].toString()
      ];
    case AiApi.anthropic:
      http.Response response = await http.get(
        Uri.parse("https://api.anthropic.com/v1/models?limit=100"),
        headers: await anthropicHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      List<String> models = [
        for (Map model in body["data"] ?? []) model["id"].toString()
      ];
      // The current Opus first; the person can pick another in the list
      models.sort((a, b) => (b == "claude-opus-5-5" ? 1 : 0)
          .compareTo(a == "claude-opus-5-5" ? 1 : 0));
      return models;
    case AiApi.chatCompletions:
      http.Response response = await http.get(
        Uri.parse(chatCompletionsBaseUrl(provider) + "/models"),
        headers: await chatCompletionsHeaders(provider),
      );
      Map body = decodeOrThrow(response);
      List<String> models = [
        for (Map model in body["data"] ?? []) model["id"].toString()
      ];
      if (provider == AiProvider.openrouter) {
        // Models ending in ":free" cost nothing with a free OpenRouter key
        models.sort((a, b) => (b.endsWith(":free") ? 1 : 0)
            .compareTo(a.endsWith(":free") ? 1 : 0));
      } else {
        models.sort((a, b) => (b == "deepseek-chat" ? 1 : 0)
            .compareTo(a == "deepseek-chat" ? 1 : 0));
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
  if (response.statusCode >= 500) throw AiError("ai-provider-down");
  throw AiError(message);
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
Future<String> sendChat(
  List<ChatMessage> conversation, {
  required String? financeContext,
  void Function(String textSoFar)? onDelta,
}) async {
  AiProvider provider = selectedAiProvider();
  String model = await ensureModel(provider);
  String instructions = financeInstructions +
      (financeContext == null ? "" : "\n\nUser data:\n" + financeContext);

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
            for (ChatMessage message in conversation)
              {
                "role": message.fromUser ? "user" : "model",
                "parts": [
                  {"text": message.text}
                ]
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
          "input": responsesInput(conversation),
        }),
      );
      return responsesOutputText(decodeOrThrow(response));
    case AiApi.chatgptPlan:
      return await streamChatGptResponse(
        model: model,
        instructions: instructions,
        input: responsesInput(conversation),
        onDelta: onDelta,
      );
    case AiApi.anthropic:
      http.Response response = await http.post(
        Uri.parse("https://api.anthropic.com/v1/messages"),
        headers: await anthropicHeaders(provider, model: model),
        body: jsonEncode(anthropicBody(model, instructions, [
          for (ChatMessage message in conversation)
            {
              "role": message.fromUser ? "user" : "assistant",
              "content": message.text
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
            for (ChatMessage message in conversation)
              {
                "role": message.fromUser ? "user" : "assistant",
                "content": message.text
              }
          ],
        }),
      );
      return chatCompletionsOutputText(decodeOrThrow(response));
  }
}

// The model picked in the chat page, or the provider's first one
Future<String> ensureModel(AiProvider provider) async {
  String? model = selectedModel(provider);
  if (model != null) return model;
  List<String> models = await listModels(provider);
  if (models.isEmpty) throw AiError("ai-no-models");
  await setSelectedModel(provider, models.first);
  return models.first;
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

List<Map<String, String>> responsesInput(List<ChatMessage> conversation) => [
      for (ChatMessage message in conversation)
        {
          "role": message.fromUser ? "user" : "assistant",
          "content": message.text
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
