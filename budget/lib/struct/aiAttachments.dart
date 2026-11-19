import 'dart:convert';

import 'package:budget/struct/aiChat.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

// Files attached to a chat message. PDFs go as they are to the models that
// read them; CSV, Excel and text files become text here, so every model can
// read them.

// Past this the text is refused instead of cut, so the answer never comes
// from half a file
const int aiAttachmentMaxChars = 200000;
// Base64 grows a file by a third; this keeps requests well under the
// providers' limits
const int aiPdfMaxBytes = 10 * 1024 * 1024;
// Raw size checked before reading a data file
const int aiDataFileMaxBytes = 20 * 1024 * 1024;

const List<String> aiTextFileExtensions = ["csv", "txt", "xlsx", "xls"];

String fileExtension(String name) {
  int dot = name.lastIndexOf(".");
  return dot == -1 ? "" : name.substring(dot + 1).toLowerCase();
}

// UTF-8 (with or without BOM), UTF-16 with BOM, or else Latin-1, which is
// what older Excel and bank exports in Spanish usually use
String decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  Uint8List body = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF
      ? bytes.sublist(3)
      : bytes;
  try {
    return utf8.decode(body);
  } on FormatException {
    return latin1.decode(body);
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  List<int> units = [
    for (int i = 0; i + 1 < bytes.length; i += 2)
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1]
  ];
  return String.fromCharCodes(units);
}

String _cellText(CellValue? value) => switch (value) {
      null => "",
      DoubleCellValue(value: double v) =>
        v == v.roundToDouble() && v.abs() < 1e15
            ? v.toInt().toString()
            : v.toString(),
      DateCellValue() =>
        value.asDateTimeUtc().toIso8601String().substring(0, 10),
      _ => value.toString(),
    };

// Every sheet as CSV rows under its name, without empty rows or trailing
// empty cells. Throws when the bytes are not an .xlsx workbook
String excelToText(Uint8List bytes) {
  Excel excel = Excel.decodeBytes(bytes);
  StringBuffer out = StringBuffer();
  const ListToCsvConverter csv = ListToCsvConverter();
  for (MapEntry<String, Sheet> sheet in excel.tables.entries) {
    List<List<String>> rows = [];
    for (List<Data?> row in sheet.value.rows) {
      List<String> cells = [for (Data? cell in row) _cellText(cell?.value)];
      while (cells.isNotEmpty && cells.last.trim() == "") {
        cells.removeLast();
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isEmpty) continue;
    if (out.isNotEmpty) out.writeln();
    out.writeln("Sheet: " + sheet.key);
    out.writeln(csv.convert(rows));
    // Stop early on huge workbooks, the result is refused anyway
    if (out.length > aiAttachmentMaxChars) break;
  }
  return out.toString();
}

// Text that fits in a request; refused, never cut, when it doesn't
String checkAttachmentText(String text) {
  if (text.trim().isEmpty) throw AiError("ai-file-unreadable");
  if (text.length > aiAttachmentMaxChars) throw AiError("ai-file-too-big");
  return text;
}

// A picked file ready to send. Throws AiError with a translation key when it
// can't be read, is too big or is a kind the chat doesn't take
AiAttachment attachmentFromFile(String name, Uint8List bytes,
    {bool allowPdf = true}) {
  String extension = fileExtension(name);
  switch (extension) {
    case "pdf":
      if (allowPdf == false) throw AiError("ai-model-no-pdf");
      if (bytes.length > aiPdfMaxBytes) throw AiError("ai-file-too-big");
      if (bytes.length < 5 ||
          String.fromCharCodes(bytes.sublist(0, 5)) != "%PDF-") {
        throw AiError("ai-file-unreadable");
      }
      return AiAttachment.pdf(name, bytes);
    case "csv":
    case "txt":
      if (bytes.length > aiDataFileMaxBytes) throw AiError("ai-file-too-big");
      return AiAttachment.text(
          name, checkAttachmentText(decodeTextBytes(bytes)));
    case "xlsx":
    case "xls":
      if (bytes.length > aiDataFileMaxBytes) throw AiError("ai-file-too-big");
      String text;
      try {
        text = excelToText(bytes);
      } catch (e) {
        // The old binary .xls format can't be read on the device
        bool oldExcel = bytes.length > 4 &&
            bytes[0] == 0xD0 &&
            bytes[1] == 0xCF &&
            bytes[2] == 0x11 &&
            bytes[3] == 0xE0;
        throw AiError(oldExcel ? "ai-file-old-excel" : "ai-file-unreadable");
      }
      return AiAttachment.text(name, checkAttachmentText(text));
    default:
      throw AiError("ai-file-type-not-supported");
  }
}

// Picks a PDF (when the model reads them) or a CSV, Excel or text file.
// Null when cancelled
Future<AiAttachment?> pickAiFile({required bool allowPdf}) async {
  List<String> extensions = [if (allowPdf) "pdf", ...aiTextFileExtensions];
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
  } catch (e) {
    // Some Android file managers refuse a filter; the type is checked below
    print("File filter refused: " + e.toString());
    result = await FilePicker.platform.pickFiles(withData: true);
  }
  if (result == null || result.files.isEmpty) return null;
  PlatformFile file = result.files.single;
  if (fileExtension(file.name) == "pdf" && file.size > aiPdfMaxBytes) {
    throw AiError("ai-file-too-big");
  }
  if (file.size > aiDataFileMaxBytes) throw AiError("ai-file-too-big");
  Uint8List? bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) throw AiError("ai-file-unreadable");
  if (kIsWeb) return attachmentFromFile(file.name, bytes, allowPdf: allowPdf);
  // Large workbooks take a moment: convert away from the UI
  _Converted converted =
      await compute(_convert, _ToConvert(file.name, bytes, allowPdf));
  if (converted.error != null) throw AiError(converted.error!);
  return converted.attachment;
}

class _ToConvert {
  _ToConvert(this.name, this.bytes, this.allowPdf);
  final String name;
  final Uint8List bytes;
  final bool allowPdf;
}

class _Converted {
  _Converted(this.attachment, this.error);
  final AiAttachment? attachment;
  final String? error;
}

_Converted _convert(_ToConvert input) {
  try {
    return _Converted(
        attachmentFromFile(input.name, input.bytes, allowPdf: input.allowPdf),
        null);
  } on AiError catch (e) {
    return _Converted(null, e.message);
  } catch (e) {
    return _Converted(null, "ai-file-unreadable");
  }
}
