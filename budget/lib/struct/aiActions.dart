import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/struct/aiChat.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:image_picker/image_picker.dart';

// Requests behind the assistant actions of the AI chat: a receipt photo, a
// sentence or voice note, a bank message, a loan offer and the month summary.
// The model answers JSON that is parsed defensively here; whatever it reads
// goes to a screen where the user reviews it before anything is saved.

// Name of the tag the income tax tool counts as an electronic invoice
const String electronicInvoiceTagName = "Factura electrónica";

// Photos are resized on the device before they are sent
const double aiImageMaxSide = 1600;
const int aiImageQuality = 80;

// Picks or takes a photo, resized and compressed. Null when cancelled. On the
// web the camera may open a file picker instead
Future<AiImage?> pickAiImage(ImageSource source) async {
  XFile? file = await ImagePicker().pickImage(
    source: source,
    maxWidth: aiImageMaxSide,
    maxHeight: aiImageMaxSide,
    imageQuality: aiImageQuality,
  );
  if (file == null) return null;
  Uint8List bytes = await file.readAsBytes();
  if (bytes.isEmpty) return null;
  return AiImage(bytes, imageMimeType(bytes, fallback: file.mimeType));
}

// The type from the first bytes, since pickers do not always say it
String imageMimeType(Uint8List bytes, {String? fallback}) {
  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return "image/jpeg";
  }
  if (bytes.length > 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return "image/png";
  }
  if (bytes.length > 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == "RIFF" &&
      String.fromCharCodes(bytes.sublist(8, 12)) == "WEBP") {
    return "image/webp";
  }
  if (fallback != null && fallback.startsWith("image/")) return fallback;
  return "image/jpeg";
}

// Parsing

// The JSON object in a model answer. Tolerates code fences and text around
// it; null when there is no object to read
Map<String, dynamic>? decodeAiJson(String? text) {
  if (text == null) return null;
  String s = text.trim();
  RegExpMatch? fence =
      RegExp(r"```(?:json|JSON)?\s*([\s\S]*?)```").firstMatch(s);
  if (fence != null) s = fence.group(1)!.trim();
  int start = s.indexOf("{");
  int end = s.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    dynamic decoded = jsonDecode(s.substring(start, end + 1));
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (e) {}
  return null;
}

String removeAccents(String s) {
  const Map<String, String> plain = {
    "á": "a",
    "é": "e",
    "í": "i",
    "ó": "o",
    "ú": "u",
    "ü": "u",
    "ñ": "n",
    "Á": "A",
    "É": "E",
    "Í": "I",
    "Ó": "O",
    "Ú": "U",
    "Ü": "U",
    "Ñ": "N",
  };
  return s.split("").map((c) => plain[c] ?? c).join();
}

String normalizeName(String s) => removeAccents(s.toLowerCase())
    .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
    .trim();

// Index of the name that best matches what the model wrote: the same name
// ignoring case and accents, else one containing the other (longest first)
int? bestNameMatch(String? wanted, List<String> names) {
  if (wanted == null) return null;
  String target = normalizeName(wanted);
  if (target.isEmpty) return null;
  for (int i = 0; i < names.length; i++) {
    if (normalizeName(names[i]) == target) return i;
  }
  List<int> order = List.generate(names.length, (i) => i)
    ..sort((a, b) => names[b].length.compareTo(names[a].length));
  for (int i in order) {
    String name = normalizeName(names[i]);
    if (name.isEmpty) continue;
    if (target.contains(name) || name.contains(target)) return i;
  }
  return null;
}

String? cleanText(dynamic value) {
  if (value == null) return null;
  String s = value.toString().trim();
  if (s.isEmpty || s.toLowerCase() == "null") return null;
  return s;
}

bool parseAiBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  String s = normalizeName(value?.toString() ?? "");
  return ["true", "si", "yes", "1"].contains(s);
}

// A number written the Colombian way or the US way: "45.900", "45,900",
// "1.500.000", "1'500.000", "45.900,50", "45,900.00", "12.5" and "1,5". A
// single separator is a thousands one when three digits follow it
double? parseAmountNumber(String text) {
  String s = text.replaceAll(RegExp(r"[\s$'’]"), "");
  if (s.isEmpty) return null;
  int lastDot = s.lastIndexOf(".");
  int lastComma = s.lastIndexOf(",");
  if (lastDot >= 0 && lastComma >= 0) {
    // Whichever comes last is the decimal mark
    s = lastComma > lastDot
        ? s.replaceAll(".", "").replaceAll(",", ".")
        : s.replaceAll(",", "");
  } else if (lastDot >= 0 || lastComma >= 0) {
    String mark = lastDot >= 0 ? "." : ",";
    int last = lastDot >= 0 ? lastDot : lastComma;
    bool several = mark.allMatches(s).length > 1;
    bool threeAfter = s.length - last - 1 == 3;
    bool groups = several || (threeAfter && s.substring(0, last) != "0");
    s = groups ? s.replaceAll(mark, "") : s.replaceAll(mark, ".");
  }
  double? value = double.tryParse(s);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}

// An amount in pesos from a model field: a number, "$45.900", "15 mil",
// "20 lucas", "1 palo", "medio palo", "1 palo y medio", "2,5 millones" or
// "1 millón 200 mil". Null when there is no amount
double? parseColombianAmount(dynamic value) {
  if (value == null || value is bool) return null;
  if (value is num) {
    if (value.isNaN || value.isInfinite) return null;
    return value.toDouble().abs();
  }
  String s = removeAccents(value.toString().toLowerCase());
  s = s
      .replaceAll(RegExp(r"\b(cop|pesos?|col)\b"), " ")
      .replaceAll(RegExp(r"\b(un|uno|una)\b"), "1")
      .replaceAll(RegExp(r"\bmedi[oa]\s+(?=palo|millon|luca)"), "0,5 ");
  const String millionWords = r"palos?|millones|millon|mill|mm";
  const String thousandWords = r"lucas?|mil|k";
  // "1 palo y medio" is 1,5 palos
  s = s.replaceAllMapped(
      RegExp(
          r"(\d+)\s*(" + millionWords + "|" + thousandWords + r")\s+y\s+medio"),
      (m) => m.group(1)! + ",5 " + m.group(2)!);

  Iterable<RegExpMatch> matches = RegExp(r"(\d[\d.,']*)\s*(" +
          millionWords +
          "|" +
          thousandWords +
          r")?(?![a-z])")
      .allMatches(s);
  if (matches.isEmpty) {
    // "mil pesos" alone
    return RegExp(r"^\s*mil\b").hasMatch(s) ? 1000 : null;
  }
  bool hasWord = matches.any((m) => m.group(2) != null);
  if (hasWord == false) {
    return parseAmountNumber(_trimSeparators(matches.first.group(1)!))?.abs();
  }
  double total = 0;
  for (RegExpMatch m in matches) {
    String? word = m.group(2);
    double? number =
        word == null ? null : parseAmountNumber(_trimSeparators(m.group(1)!));
    // Bare numbers next to "15 mil" are usually something else
    if (number == null) continue;
    double multiplier =
        RegExp("^(" + millionWords + r")$").hasMatch(word!) ? 1000000 : 1000;
    total += number * multiplier;
  }
  return total == 0 ? null : total;
}

// "45.900." at the end of a sentence
String _trimSeparators(String s) => s.replaceAll(RegExp(r"[.,']+$"), "");

// "2026-11-12", "12/11/2026" (day first), "hoy" and "ayer". Dates far in the
// future or before 2000 are taken as misread
DateTime? parseAiDate(dynamic value, {DateTime? today}) {
  String? s = cleanText(value);
  if (s == null) return null;
  DateTime now = today ?? DateTime.now();
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  String lower = normalizeName(s);
  if (lower == "hoy" || lower == "today") return day(now);
  if (lower == "ayer" || lower == "yesterday") {
    return day(now).subtract(Duration(days: 1));
  }
  DateTime? date;
  RegExpMatch? iso = RegExp(r"(\d{4})-(\d{1,2})-(\d{1,2})").firstMatch(s);
  RegExpMatch? dmy =
      RegExp(r"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})").firstMatch(s);
  if (iso != null) {
    date = _validDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
        int.parse(iso.group(3)!));
  } else if (dmy != null) {
    int year = int.parse(dmy.group(3)!);
    if (year < 100) year += 2000;
    date = _validDate(year, int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
  }
  if (date == null) return null;
  if (date.year < 2000 || date.isAfter(day(now).add(Duration(days: 1)))) {
    return null;
  }
  return date;
}

DateTime? _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  DateTime date = DateTime(year, month, day);
  // DateTime rolls 31/02 over to March
  if (date.month != month) return null;
  return date;
}

bool? parseIncome(Map<String, dynamic> json) {
  dynamic flag = json["isIncome"] ?? json["income"];
  if (flag is bool) return flag;
  String type = normalizeName((json["type"] ?? "").toString());
  if (["income", "ingreso", "entrada"].contains(type)) return true;
  if (["expense", "gasto", "egreso", "salida"].contains(type)) return false;
  return null;
}

// A transaction read by the model, every field optional
class AiTransactionDraft {
  AiTransactionDraft({
    this.amount,
    this.income,
    this.title,
    this.category,
    this.pocket,
    this.date,
    this.note,
    this.electronicInvoice = false,
  });

  final double? amount;
  final bool? income;
  final String? title;
  final String? category;
  final String? pocket;
  final DateTime? date;
  final String? note;
  final bool electronicInvoice;

  factory AiTransactionDraft.fromJson(Map<String, dynamic> json,
      {DateTime? today}) {
    double? amount = parseColombianAmount(json["amount"] ?? json["total"]);
    return AiTransactionDraft(
      amount: amount == null || amount == 0 ? null : amount,
      income: parseIncome(json),
      title: cleanText(json["title"] ?? json["merchant"]),
      category: cleanText(json["category"]),
      pocket: cleanText(json["pocket"] ?? json["wallet"] ?? json["account"]),
      date: parseAiDate(json["date"], today: today),
      note: cleanText(json["note"] ?? json["notes"]),
      electronicInvoice: parseAiBool(json["isElectronicInvoice"]),
    );
  }

  bool get isEmpty => amount == null && title == null;
}

// A loan offer read from a photo
class AiLoanOffer {
  AiLoanOffer({
    this.amount,
    this.ratePercent,
    this.rateKind,
    this.months,
    this.installment,
    this.monthlyFees,
    this.otherCosts,
    this.bank,
  });

  final double? amount;
  // 26.5 means 26.5%
  final double? ratePercent;
  final LoanRateKind? rateKind;
  final int? months;
  final double? installment;
  final double? monthlyFees;
  final String? otherCosts;
  final String? bank;

  factory AiLoanOffer.fromJson(Map<String, dynamic> json) {
    double? rate = _percent(json["rate"]);
    LoanRateKind? kind = parseRateKind(json["rateType"] ?? json["rateKind"]);
    // Without a type, a small rate is monthly and a big one is annual
    if (rate != null && kind == null) {
      kind = rate <= 4 ? LoanRateKind.monthlyArrears : LoanRateKind.ea;
    }
    double? months = parseAmountNumber(cleanText(json["months"]) ?? "");
    double? amount = parseColombianAmount(json["amount"]);
    double? installment = parseColombianAmount(json["installment"]);
    double? fees = parseColombianAmount(json["monthlyFees"] ?? json["fees"]);
    return AiLoanOffer(
      amount: amount == 0 ? null : amount,
      ratePercent: rate,
      rateKind: rate == null ? null : kind,
      months:
          months == null || months <= 0 || months > 600 ? null : months.round(),
      installment: installment == 0 ? null : installment,
      monthlyFees: fees == 0 ? null : fees,
      otherCosts: cleanText(json["otherCosts"]),
      bank: cleanText(json["bank"]),
    );
  }

  bool get isEmpty => amount == null && ratePercent == null && months == null;

  // The rate as effective annual, in percent
  double? get effectiveAnnualPercent {
    if (ratePercent == null || rateKind == null) return null;
    if (isValidLoanRate(ratePercent! / 100, rateKind!) == false) return null;
    double monthly = loanRateToMonthlyEffective(ratePercent! / 100, rateKind!);
    return (pow(1 + monthly, 12) - 1) * 100;
  }
}

double? _percent(dynamic value) {
  if (value == null || value is bool) return null;
  if (value is num) return value.toDouble().abs();
  String? s = cleanText(value);
  if (s == null) return null;
  RegExpMatch? m = RegExp(r"\d+(?:[.,]\d+)?").firstMatch(s);
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(",", "."));
}

LoanRateKind? parseRateKind(dynamic value) {
  String? s = cleanText(value);
  if (s == null) return null;
  String key = removeAccents(s.toUpperCase()).replaceAll(RegExp(r"[^A-Z]"), "");
  if (key == "EA" || key.contains("EFECTIVAANUAL")) return LoanRateKind.ea;
  if (key == "NAMA") return LoanRateKind.nama;
  if (key == "NMV" || key.contains("NOMINALMENSUAL")) return LoanRateKind.nmv;
  if (key == "MA" || key.contains("ANTICIPAD")) {
    return LoanRateKind.monthlyAnticipated;
  }
  if (key == "MV" || key.contains("VENCID") || key.contains("MENSUAL")) {
    return LoanRateKind.monthlyArrears;
  }
  return null;
}

// Prompts

String _today(DateTime now) => now.toIso8601String().substring(0, 10);

String _list(List<String> names) =>
    names.isEmpty ? "(none)" : names.map((n) => "- " + n).join("\n");

const String _moneyTalk = """
Colombian money talk: "mil" is 1.000 ("15 mil" = 15000), "luca"/"lucas" is
1.000 ("20 lucas" = 20000), "k" is 1.000, "palo"/"palos" is one million
("1 palo" = 1000000, "medio palo" = 500000, "palo y medio" = 1500000).
Written amounts use dots for thousands and a comma for decimals
("\$45.900,00" = 45900).""";

const String _jsonOnly = """
Answer with the JSON object only: no Markdown, no code fences, no text before
or after it. Use null for anything you cannot tell.""";

String transactionTextInstructions({
  required List<String> categories,
  required List<String> pockets,
  required bool bankMessage,
  DateTime? today,
}) =>
    """
You turn ${bankMessage ? "a bank SMS or app notification (Bancolombia, Nequi, Daviplata, Davivienda, BBVA...)" : "a sentence a person wrote or said about their money"} into one transaction for a personal finance app in Colombia.
Today is ${_today(today ?? DateTime.now())}; resolve "hoy", "ayer" and weekdays from it.
$_moneyTalk
${bankMessage ? 'Purchases, payments, withdrawals and transfers sent ("Compraste", "Pagaste", "Retiraste", "Transferiste", "Enviaste") are expenses; money received ("Recibiste", "te consignaron", "abono") is income. The title is the merchant or the person. The pocket is the bank or wallet that sent the message when it matches one of the pockets.' : "Spending is an expense; being paid or receiving money is income."}

Return a JSON object with these keys:
{"amount": number in pesos without separators,
 "type": "expense" or "income",
 "title": short title, 2 to 5 words, like the merchant or what it was,
 "category": one of the category names below copied exactly, or null,
 "pocket": one of the pockets below copied exactly, or null,
 "date": "YYYY-MM-DD" or null when not said,
 "note": a short useful detail not in the title, or null}

Categories:
${_list(categories)}

Pockets:
${_list(pockets)}

$_jsonOnly""";

String receiptInstructions({
  required List<String> categories,
  DateTime? today,
}) =>
    """
You read a photo of a receipt or bill from Colombia for a personal finance app.
Today is ${_today(today ?? DateTime.now())}.
$_moneyTalk
The amount is the total paid (the "TOTAL", after taxes and tips), not a subtotal.
It is an electronic invoice ("factura electrónica de venta") when it says so or shows a CUFE code or a DIAN QR code.

Return a JSON object with these keys:
{"amount": total in pesos as a number without separators,
 "merchant": the store or company name, short,
 "date": "YYYY-MM-DD" or null,
 "category": one of the category names below copied exactly, or null,
 "isElectronicInvoice": true or false,
 "note": the invoice number or a short detail, or null}
If the photo is not a receipt or bill, return {"amount": null, "merchant": null}.

Categories:
${_list(categories)}

$_jsonOnly""";

const String loanOfferInstructions = """
You read a photo of a loan offer or loan simulation from a Colombian bank or
lender for a personal finance app.
$_moneyTalk

Return a JSON object with these keys:
{"amount": loan amount in pesos as a number,
 "rate": the interest rate as a percent number (26.5 means 26.5%),
 "rateType": "EA" (efectiva anual), "MV" (mensual vencida), "MA" (mensual anticipada), "NMV" (nominal mes vencido) or "NAMA",
 "months": term in months as a number,
 "installment": monthly installment in pesos as a number,
 "monthlyFees": insurance and fees charged every month, in pesos, or null,
 "otherCosts": one-time costs (study fee, commission) as short text, or null,
 "bank": the lender's name, or null}
When several rates appear, use the interest rate, not the "tasa de mora".
If the photo is not a loan offer, return {"amount": null, "rate": null, "months": null}.

$_jsonOnly""";

String monthlySummaryInstructions(String languageCode) => """
You are the assistant inside Finza, a personal finance app. Using the user's
data below, write a short summary of this month for someone who is not used
to finance words.
Write in the language with code "$languageCode"; for "es" use simple
Colombian Spanish and "tú".
Plain text only: no Markdown, no asterisks, no tables. Under 170 words.
Layout:
- Two or three sentences on where the money went this month (the biggest
  categories with amounts).
- One or two sentences comparing with last month, using the movements of last
  month in the data. If there is not enough data, say so briefly.
- Three concrete tips, numbered 1. 2. 3., each one line, based on their data.
Do not invent figures. This is general guidance, not professional advice.""";

// Requests

Future<AiTransactionDraft> readTransactionText(
  String text, {
  required List<String> categories,
  required List<String> pockets,
  bool bankMessage = false,
}) async {
  String answer = await sendPrompt(
    instructions: transactionTextInstructions(
      categories: categories,
      pockets: pockets,
      bankMessage: bankMessage,
    ),
    text: text,
    json: true,
  );
  return _draftOrThrow(answer);
}

Future<AiTransactionDraft> readReceipt(
  AiImage image, {
  required List<String> categories,
}) async {
  String answer = await sendPrompt(
    instructions: receiptInstructions(categories: categories),
    text: "Read this receipt and answer with the JSON object.",
    image: image,
    json: true,
  );
  return _draftOrThrow(answer);
}

AiTransactionDraft _draftOrThrow(String answer) {
  Map<String, dynamic>? json = decodeAiJson(answer);
  if (json == null) throw AiError("ai-could-not-read");
  AiTransactionDraft draft = AiTransactionDraft.fromJson(json);
  if (draft.isEmpty) throw AiError("ai-could-not-read");
  return draft;
}

Future<AiLoanOffer> readLoanOffer(AiImage image) async {
  String answer = await sendPrompt(
    instructions: loanOfferInstructions,
    text: "Read this loan offer and answer with the JSON object.",
    image: image,
    json: true,
  );
  Map<String, dynamic>? json = decodeAiJson(answer);
  if (json == null) throw AiError("ai-could-not-read");
  AiLoanOffer offer = AiLoanOffer.fromJson(json);
  if (offer.isEmpty) throw AiError("ai-could-not-read");
  return offer;
}

Future<String> monthlySummary(String financeContext,
    {required String languageCode}) async {
  String answer = await sendPrompt(
    instructions: monthlySummaryInstructions(languageCode) +
        "\n\nUser data:\n" +
        financeContext,
    text: languageCode == "es"
        ? "Resúmeme este mes con 3 consejos."
        : "Summarize this month with 3 tips.",
  );
  String text = answer.replaceAll("**", "").replaceAll("##", "").trim();
  if (text.isEmpty) throw AiError("ai-failed");
  return text;
}

// The app's data the prompts choose from

class AiPocketOption {
  AiPocketOption(this.wallet, this.label, this.accountName);
  final TransactionWallet wallet;
  // "Account / Pocket", or the pocket alone without an account
  final String label;
  final String? accountName;
}

Future<List<AiPocketOption>> aiPocketOptions(AllWallets allWallets) async {
  Map<String, String> accounts = {};
  try {
    for (WalletGroup group in await database.getAllWalletGroups()) {
      accounts[group.walletGroupPk] = group.name;
    }
  } catch (e) {}
  return [
    for (TransactionWallet wallet in allWallets.list)
      if (wallet.archived == false)
        AiPocketOption(
          wallet,
          accounts[wallet.walletGroupFk] == null
              ? wallet.name
              : accounts[wallet.walletGroupFk]! + " / " + wallet.name,
          accounts[wallet.walletGroupFk],
        ),
  ];
}

// The pocket the model picked: its full label, the pocket name, or the first
// pocket of a matching account ("Nequi")
TransactionWallet? matchPocket(String? name, List<AiPocketOption> options) {
  if (name == null || options.isEmpty) return null;
  int? index = bestNameMatch(name, options.map((o) => o.label).toList()) ??
      bestNameMatch(name, options.map((o) => o.wallet.name).toList()) ??
      bestNameMatch(name, options.map((o) => o.accountName ?? "").toList());
  return index == null ? null : options[index].wallet;
}

TransactionCategory? matchCategory(
    String? name, List<TransactionCategory> categories) {
  int? index = bestNameMatch(name, categories.map((c) => c.name).toList());
  return index == null ? null : categories[index];
}

// The tag the income tax tool counts, created when missing. Null on a
// database without tag tables
Future<String?> electronicInvoiceTagPk() async {
  try {
    for (Tag tag in await database.getAllTags()) {
      if (normalizeName(tag.name) == normalizeName(electronicInvoiceTagName)) {
        return tag.tagPk;
      }
    }
    return await database.createOrUpdateTag(
      insert: true,
      Tag(
        tagPk: "-1",
        name: electronicInvoiceTagName,
        order: 0,
        archived: false,
        dateCreated: DateTime.now(),
      ),
    );
  } catch (e) {
    print("No tag for the electronic invoice: " + e.toString());
    return null;
  }
}
