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
enum AiProvider { gemini, openai, chatgpt }

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
  switch (provider) {
    case AiProvider.gemini:
      String key = await requireKey(provider);
      http.Response response = await http.get(
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/models"),
        headers: {"x-goog-api-key": key},
      );
      Map body = decodeOrThrow(response);
      List<String> models = [
        for (Map model in body["models"] ?? [])
          if ((model["supportedGenerationMethods"] ?? [])
              .contains("generateContent"))
            model["name"].toString()
      ];
      // Flash models are fast and cheap, enough for questions about money
      models.sort((a, b) =>
          (b.contains("flash") ? 1 : 0).compareTo(a.contains("flash") ? 1 : 0));
      return models;
    case AiProvider.openai:
      String key = await requireKey(provider);
      http.Response response = await http.get(
        Uri.parse("https://api.openai.com/v1/models"),
        headers: {"Authorization": "Bearer " + key},
      );
      Map body = decodeOrThrow(response);
      return [for (Map model in body["data"] ?? []) model["id"].toString()]
        ..sort();
    case AiProvider.chatgpt:
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
  if (code == "subscription_sharing_usage_limit_exceeded") {
    throw AiError("ai-plan-limit-reached", manageUsage: true);
  }
  if (code == "subscription_sharing_user_not_eligible") {
    throw AiError("ai-plan-not-eligible");
  }
  String message = error is Map
      ? (error["message"] ?? response.reasonPhrase).toString()
      : response.reasonPhrase ?? response.statusCode.toString();
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
  String? model = selectedModel(provider);
  if (model == null) {
    List<String> models = await listModels(provider);
    if (models.isEmpty) throw AiError("ai-no-models");
    model = models.first;
    await setSelectedModel(provider, model);
  }
  String instructions = financeInstructions +
      (financeContext == null ? "" : "\n\nUser data:\n" + financeContext);

  switch (provider) {
    case AiProvider.gemini:
      String key = await requireKey(provider);
      http.Response response = await http.post(
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/" +
            model +
            ":generateContent"),
        headers: {"x-goog-api-key": key, "Content-Type": "application/json"},
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
      Map body = decodeOrThrow(response);
      List parts = body["candidates"]?[0]?["content"]?["parts"] ?? [];
      return parts.map((p) => p["text"] ?? "").join();
    case AiProvider.openai:
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
    case AiProvider.chatgpt:
      return await streamChatGptResponse(
        model: model,
        instructions: instructions,
        input: responsesInput(conversation),
        onDelta: onDelta,
      );
  }
}

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
  required List<Map<String, String>> input,
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
