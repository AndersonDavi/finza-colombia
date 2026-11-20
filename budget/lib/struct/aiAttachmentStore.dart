import 'dart:convert';
import 'dart:io';

import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// The latest file of each saved chat (only that one goes to the model), kept
// so reopening a chat from the history can keep asking about it. On the phone
// and the computer it is a file in the app's own folder; on the web, where
// there are no files, only small ones are kept in the browser storage

const int maxWebStoredAttachment = 1500000;

Future<File?> _file(String conversationId) async {
  if (kIsWeb) return null;
  Directory folder = Directory(
      (await getApplicationSupportDirectory()).path + "/ai_attachments");
  if (!await folder.exists()) await folder.create(recursive: true);
  return File(folder.path + "/" + conversationId + ".json");
}

String _webKey(String conversationId) => "aiAttachment_" + conversationId;

Future<void> saveChatAttachment(
    String conversationId, int messageIndex, AiAttachment attachment) async {
  try {
    String data = jsonEncode({
      "index": messageIndex,
      "name": attachment.name,
      "kind": attachment.kind.name,
      "mime": attachment.mimeType,
      if (attachment.text != null) "text": attachment.text,
      if (attachment.bytes != null) "bytes": attachment.base64Data,
    });
    File? file = await _file(conversationId);
    if (file != null) {
      await file.writeAsString(data);
    } else if (data.length <= maxWebStoredAttachment) {
      await sharedPreferences.setString(_webKey(conversationId), data);
    }
  } catch (e) {
    print("Could not keep the chat file: " + e.toString());
  }
}

// The file and the position of its message, or null
Future<(int, AiAttachment)?> loadChatAttachment(String conversationId) async {
  try {
    File? file = await _file(conversationId);
    String? data = file != null
        ? (await file.exists() ? await file.readAsString() : null)
        : sharedPreferences.getString(_webKey(conversationId));
    if (data == null) return null;
    Map json = jsonDecode(data);
    String name = json["name"].toString();
    AiAttachment? attachment = switch (json["kind"]) {
      "image" => AiAttachment.image(
          name,
          AiImage(base64Decode(json["bytes"]), json["mime"].toString()),
        ),
      "pdf" => AiAttachment.pdf(name, base64Decode(json["bytes"])),
      "text" => AiAttachment.text(name, json["text"].toString()),
      _ => null,
    };
    if (attachment == null) return null;
    return (json["index"] as int, attachment);
  } catch (e) {
    print("Could not read the chat file: " + e.toString());
    return null;
  }
}

Future<void> deleteChatAttachment(String conversationId) async {
  try {
    File? file = await _file(conversationId);
    if (file != null) {
      if (await file.exists()) await file.delete();
    } else {
      await sharedPreferences.remove(_webKey(conversationId));
    }
  } catch (e) {}
}
