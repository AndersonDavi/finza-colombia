// Checks for model labels and capabilities in lib/struct/aiChat.dart and the
// file conversion in lib/struct/aiAttachments.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:budget/struct/aiAttachments.dart';
import 'package:budget/struct/aiChat.dart';

Matcher throwsAiError(String key) =>
    throwsA(isA<AiError>().having((e) => e.message, "message", key));

void main() {
  group("aiModelLabel", () {
    Map<String, String> cases = {
      "gemini-3.5-flash-lite": "Gemini 3.5 Flash-Lite",
      "models/gemini-2.5-flash": "Gemini 2.5 Flash",
      "models/gemini-2.5-pro": "Gemini 2.5 Pro",
      "claude-opus-5-5": "Claude Opus 5.5",
      "claude-sonnet-4-5-20250929": "Claude Sonnet 4.5",
      "claude-3-5-haiku-20241022": "Claude 3.5 Haiku",
      "claude-fable-5-2": "Claude Fable 5.2",
      "gpt-5-mini": "GPT-5 Mini",
      "gpt-5-mini-2025-08-07": "GPT-5 Mini",
      "gpt-4o": "GPT-4o",
      "gpt-4.1-nano": "GPT-4.1 Nano",
      "o3-mini": "o3 Mini",
      "deepseek-chat": "DeepSeek Chat",
      "deepseek-reasoner": "DeepSeek Reasoner",
      "google/gemini-2.5-flash:free": "Gemini 2.5 Flash",
      "meta-llama/llama-3.3-70b-instruct": "Llama 3.3 70b Instruct",
    };
    cases.forEach((id, label) {
      test(id, () => expect(aiModelLabel(id), label));
    });
  });

  group("aiModelInfoFor", () {
    test("Gemini reads photos and PDFs; Flash is fast and free", () {
      AiModelInfo flash =
          aiModelInfoFor(AiProvider.gemini, "models/gemini-3.5-flash-lite");
      expect(flash.label, "Gemini 3.5 Flash-Lite");
      expect(flash.id, "models/gemini-3.5-flash-lite");
      expect([flash.readsImages, flash.readsPdf, flash.fast, flash.free],
          [true, true, true, true]);
      AiModelInfo pro = aiModelInfoFor(AiProvider.gemini, "models/gemini-2.5-pro",
          displayName: "Gemini 2.5 Pro");
      expect([pro.readsImages, pro.readsPdf, pro.fast, pro.free],
          [true, true, false, false]);
    });

    test("Claude reads photos and PDFs; Haiku is fast", () {
      AiModelInfo opus = aiModelInfoFor(AiProvider.claude, "claude-opus-5-5");
      expect(opus.label, "Claude Opus 5.5");
      expect([opus.readsImages, opus.readsPdf, opus.fast], [true, true, false]);
      expect(aiModelInfoFor(AiProvider.claude, "claude-haiku-4-5").fast, true);
    });

    test("OpenAI: gpt models read photos and PDFs", () {
      AiModelInfo mini = aiModelInfoFor(AiProvider.openai, "gpt-5-mini");
      expect([mini.readsImages, mini.readsPdf, mini.fast], [true, true, true]);
      AiModelInfo old = aiModelInfoFor(AiProvider.openai, "gpt-3.5-turbo");
      expect([old.readsImages, old.readsPdf], [false, false]);
    });

    test("ChatGPT plan reads photos only", () {
      AiModelInfo plan = aiModelInfoFor(AiProvider.chatgpt, "gpt-5");
      expect([plan.readsImages, plan.readsPdf], [true, false]);
    });

    test("DeepSeek reads text only", () {
      AiModelInfo chat = aiModelInfoFor(AiProvider.deepseek, "deepseek-chat");
      expect(
          [chat.readsImages, chat.readsPdf, chat.free], [false, false, false]);
    });

    test("OpenRouter: from the list's modalities and pricing", () {
      AiModelInfo vision = aiModelInfoFor(
        AiProvider.openrouter,
        "google/gemini-2.5-flash:free",
        displayName: "Google: Gemini 2.5 Flash (free)",
        openRouter: {
          "architecture": {
            "input_modalities": ["text", "image", "file"]
          },
          "pricing": {"prompt": "0", "completion": "0"},
        },
      );
      expect(vision.label, "Google: Gemini 2.5 Flash");
      expect([vision.readsImages, vision.readsPdf, vision.free],
          [true, true, true]);
      AiModelInfo textOnly = aiModelInfoFor(
        AiProvider.openrouter,
        "deepseek/deepseek-chat",
        openRouter: {
          "architecture": {
            "input_modalities": ["text"]
          },
          "pricing": {"prompt": "0.00000027", "completion": "0.0000011"},
        },
      );
      expect([textOnly.readsImages, textOnly.readsPdf, textOnly.free],
          [false, false, false]);
    });
  });

  group("attachmentRefusal", () {
    AiAttachment pdf = AiAttachment.pdf(
        "extracto.pdf", Uint8List.fromList(utf8.encode("%PDF-1.7")));
    AiAttachment csv = AiAttachment.text("datos.csv", "a,b");
    test("text files go to any model", () {
      AiModelInfo deepseek =
          aiModelInfoFor(AiProvider.deepseek, "deepseek-chat");
      expect(
          attachmentRefusal(csv, deepseek, AiApi.chatCompletions), isNull);
      expect(attachmentRefusal(pdf, deepseek, AiApi.chatCompletions),
          "ai-model-no-pdf");
    });
    test("the ChatGPT plan takes no PDFs", () {
      AiModelInfo plan = aiModelInfoFor(AiProvider.openai, "gpt-5");
      expect(attachmentRefusal(pdf, plan, AiApi.chatgptPlan), "ai-model-no-pdf");
      expect(attachmentRefusal(pdf, plan, AiApi.responses), isNull);
    });
  });

  group("rejectsContent", () {
    test("provider refusals of images and files", () {
      expect(rejectsContent(404, "No endpoints found that support image input"),
          true);
      expect(rejectsContent(400, "This model does not support PDF input"), true);
      expect(rejectsContent(400, "Invalid model name"), false);
      expect(rejectsContent(500, "image processing does not support"), false);
    });
  });

  group("text files", () {
    test("UTF-8 with BOM", () {
      Uint8List bytes = Uint8List.fromList(
          [0xEF, 0xBB, 0xBF, ...utf8.encode("fecha,descripción\n1,café")]);
      expect(decodeTextBytes(bytes), "fecha,descripción\n1,café");
    });

    test("Latin-1 when it isn't UTF-8", () {
      Uint8List bytes = Uint8List.fromList(latin1.encode("año,señal\n2026,ñ"));
      expect(decodeTextBytes(bytes), "año,señal\n2026,ñ");
    });

    test("UTF-16 with BOM", () {
      String text = "Descripción\tValor";
      List<int> bytes = [0xFF, 0xFE];
      for (int unit in text.codeUnits) {
        bytes.addAll([unit & 0xFF, unit >> 8]);
      }
      expect(decodeTextBytes(Uint8List.fromList(bytes)), text);
    });

    test("a CSV becomes a text attachment", () {
      AiAttachment file = attachmentFromFile(
          "movimientos.csv", Uint8List.fromList(utf8.encode("a,b\n1,2")));
      expect(file.kind, AiAttachmentKind.text);
      expect(file.text, "a,b\n1,2");
      expect(file.name, "movimientos.csv");
    });

    test("an empty file can't be read", () {
      expect(() => attachmentFromFile("vacio.txt", Uint8List(0)),
          throwsAiError("ai-file-unreadable"));
    });
  });

  group("Excel", () {
    Uint8List workbook() {
      Excel excel = Excel.createExcel();
      Sheet sheet = excel["Gastos"];
      sheet.appendRow([
        TextCellValue("Fecha"),
        TextCellValue("Descripción"),
        TextCellValue("Valor"),
      ]);
      sheet.appendRow([
        DateCellValue(year: 2026, month: 11, day: 3),
        TextCellValue("Mercado, Éxito"),
        DoubleCellValue(45900),
      ]);
      sheet.appendRow([
        DateCellValue(year: 2026, month: 11, day: 5),
        TextCellValue("Taxi"),
        DoubleCellValue(12500.5),
      ]);
      excel.delete("Sheet1");
      return Uint8List.fromList(excel.encode()!);
    }

    test("each sheet as CSV rows", () {
      String text = excelToText(workbook());
      expect(text, contains("Sheet: Gastos"));
      expect(text, contains("Fecha,Descripción,Valor"));
      expect(text, contains('2026-11-03,"Mercado, Éxito",45900'));
      expect(text, contains("2026-11-05,Taxi,12500.5"));
    });

    test("an .xlsx becomes a text attachment", () {
      AiAttachment file = attachmentFromFile("noviembre.xlsx", workbook());
      expect(file.kind, AiAttachmentKind.text);
      expect(file.text, contains("Taxi"));
    });

    test("an old binary .xls is explained", () {
      Uint8List bytes = Uint8List.fromList(
          [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0]);
      expect(() => attachmentFromFile("viejo.xls", bytes),
          throwsAiError("ai-file-old-excel"));
    });

    test("a broken workbook can't be read", () {
      expect(
          () => attachmentFromFile(
              "roto.xlsx", Uint8List.fromList(utf8.encode("no es un zip"))),
          throwsAiError("ai-file-unreadable"));
    });
  });

  group("size limit", () {
    test("text right at the limit is accepted", () {
      String text = "a" * aiAttachmentMaxChars;
      expect(checkAttachmentText(text).length, aiAttachmentMaxChars);
    });

    test("longer text is refused, not cut", () {
      String text = "a" * (aiAttachmentMaxChars + 1);
      expect(() => checkAttachmentText(text), throwsAiError("ai-file-too-big"));
      expect(
          () => attachmentFromFile(
              "grande.csv", Uint8List.fromList(utf8.encode(text))),
          throwsAiError("ai-file-too-big"));
    });

    test("a PDF over the limit is refused", () {
      Uint8List bytes = Uint8List(aiPdfMaxBytes + 1)
        ..setAll(0, utf8.encode("%PDF-"));
      expect(() => attachmentFromFile("grande.pdf", bytes),
          throwsAiError("ai-file-too-big"));
    });

    test("PDFs only where the model reads them", () {
      Uint8List bytes = Uint8List.fromList(utf8.encode("%PDF-1.7 ..."));
      expect(attachmentFromFile("factura.pdf", bytes).kind,
          AiAttachmentKind.pdf);
      expect(() => attachmentFromFile("factura.pdf", bytes, allowPdf: false),
          throwsAiError("ai-model-no-pdf"));
      expect(() => attachmentFromFile("foto.heic", bytes),
          throwsAiError("ai-file-type-not-supported"));
    });

    test("PDF data is plain base64, no line breaks", () {
      AiAttachment file =
          AiAttachment.pdf("a.pdf", Uint8List.fromList(List.filled(300, 65)));
      expect(file.base64Data.contains("\n"), false);
      expect(file.dataUrl.startsWith("data:application/pdf;base64,"), true);
    });
  });
}
