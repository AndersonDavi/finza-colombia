import 'dart:convert';

import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/databaseGlobal.dart';

// The AI chats kept on this device, so leaving the page or the app does not
// lose them. They are stored apart from the settings (those are saved on
// every change and go into backups) and never leave the phone. Attached files
// are not kept: only their name, shown in the bubble

const String aiConversationsKey = "aiConversations";
const int maxSavedConversations = 30;
const int maxSavedMessages = 200;

class SavedMessage {
  SavedMessage(this.fromUser, this.text,
      {this.attachmentName,
      this.summary = false,
      this.changeStatus = const {},
      this.hidden = false});
  final bool fromUser;
  final String text;
  final String? attachmentName;
  // A month summary, shown as a card
  final bool summary;
  // Proposed changes already confirmed or cancelled, by position
  final Map<int, String> changeStatus;
  final bool hidden;

  Map<String, dynamic> toJson() => {
        "u": fromUser,
        "t": text,
        if (attachmentName != null) "a": attachmentName,
        if (summary) "s": true,
        if (hidden) "h": true,
        if (changeStatus.isNotEmpty)
          "c": {
            for (MapEntry<int, String> e in changeStatus.entries)
              e.key.toString(): e.value
          },
      };

  static SavedMessage fromJson(Map json) => SavedMessage(
        json["u"] == true,
        json["t"]?.toString() ?? "",
        attachmentName: json["a"]?.toString(),
        summary: json["s"] == true,
        hidden: json["h"] == true,
        changeStatus: {
          if (json["c"] is Map)
            for (MapEntry e in (json["c"] as Map).entries)
              if (int.tryParse(e.key.toString()) != null)
                int.parse(e.key.toString()): e.value.toString()
        },
      );
}

class AiConversation {
  AiConversation({
    required this.id,
    required this.title,
    required this.updated,
    required this.messages,
  });
  final String id;
  String title;
  DateTime updated;
  List<SavedMessage> messages;

  Map<String, dynamic> toJson() => {
        "id": id,
        "title": title,
        "updated": updated.toIso8601String(),
        "messages": [for (SavedMessage m in messages) m.toJson()],
      };

  static AiConversation? fromJson(Map json) {
    String? id = json["id"]?.toString();
    if (id == null) return null;
    return AiConversation(
      id: id,
      title: json["title"]?.toString() ?? "",
      updated: DateTime.tryParse(json["updated"]?.toString() ?? "") ??
          DateTime.now(),
      messages: [
        for (dynamic m in json["messages"] ?? [])
          if (m is Map) SavedMessage.fromJson(m)
      ],
    );
  }
}

// Newest first
List<AiConversation> loadAiConversations() {
  try {
    String? raw = sharedPreferences.getString(aiConversationsKey);
    if (raw == null) return [];
    List<AiConversation> list = [
      for (dynamic c in jsonDecode(raw))
        if (c is Map) AiConversation.fromJson(c)
    ].whereType<AiConversation>().toList();
    list.sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  } catch (e) {
    print("Could not read the AI chats: " + e.toString());
    return [];
  }
}

Future<void> _store(List<AiConversation> list) async {
  list.sort((a, b) => b.updated.compareTo(a.updated));
  if (list.length > maxSavedConversations) {
    list = list.sublist(0, maxSavedConversations);
  }
  await sharedPreferences.setString(aiConversationsKey,
      jsonEncode([for (AiConversation c in list) c.toJson()]));
}

// The title is the start of the first question
String conversationTitle(List<ChatMessage> messages) {
  String first = messages
          .where((m) => m.fromUser && m.text.trim() != "")
          .firstOrNull
          ?.text
          .trim() ??
      messages.firstOrNull?.attachment?.name ??
      "";
  first = first.replaceAll(RegExp(r"\s+"), " ");
  return first.length > 60 ? first.substring(0, 57) + "..." : first;
}

Future<void> saveAiConversation(String id, List<ChatMessage> messages,
    {Set<ChatMessage> summaries = const {}}) async {
  if (messages.isEmpty) return;
  List<ChatMessage> kept = messages.length > maxSavedMessages
      ? messages.sublist(messages.length - maxSavedMessages)
      : messages;
  List<AiConversation> list = loadAiConversations()
    ..removeWhere((c) => c.id == id);
  list.add(AiConversation(
    id: id,
    title: conversationTitle(messages),
    updated: DateTime.now(),
    messages: [
      for (ChatMessage m in kept)
        SavedMessage(m.fromUser, m.text,
            attachmentName: m.attachment?.name ?? m.attachmentName,
            summary: summaries.contains(m),
            changeStatus: Map.of(m.changeStatus),
            hidden: m.hidden)
    ],
  ));
  await _store(list);
}

Future<void> deleteAiConversation(String id) async {
  await _store(loadAiConversations()..removeWhere((c) => c.id == id));
}
