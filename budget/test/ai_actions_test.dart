// Checks for the parsing in lib/struct/aiActions.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/struct/aiActions.dart';

void main() {
  group("parseColombianAmount", () {
    Map<dynamic, double?> cases = {
      "15 mil": 15000,
      "15mil": 15000,
      "1 palo": 1000000,
      "un palo": 1000000,
      "2 palos": 2000000,
      "medio palo": 500000,
      "1 palo y medio": 1500000,
      "1,5 palos": 1500000,
      "2.5 millones": 2500000,
      "1 millón 200 mil": 1200000,
      "20 lucas": 20000,
      "una luca": 1000,
      "\$45.900": 45900,
      "\$45.900,00": 45900,
      "\$45,900.00": 45900,
      "45,900": 45900,
      "COP 1.500.000": 1500000,
      "1'500.000": 1500000,
      "45900": 45900,
      "12.5": 12.5,
      "50k": 50000,
      "\$ 8.000.000 pesos": 8000000,
      "gasté 15 mil en un almuerzo": 15000,
      45900: 45900,
      45900.5: 45900.5,
      -12000: 12000,
      "": null,
      "null": null,
      "nada": null,
      null: null,
      true: null,
    };
    cases.forEach((input, expected) {
      test("$input", () {
        expect(parseColombianAmount(input), expected);
      });
    });
  });

  group("decodeAiJson", () {
    test("plain object", () {
      expect(decodeAiJson('{"amount": 15000}'), {"amount": 15000});
    });
    test("code fence", () {
      expect(
          decodeAiJson('```json\n{"amount": 15000, "type": "expense"}\n```'),
          {"amount": 15000, "type": "expense"});
    });
    test("text around it", () {
      expect(decodeAiJson('Claro, aquí está: {"title": "Almuerzo"} ¡Listo!'),
          {"title": "Almuerzo"});
    });
    test("broken or empty", () {
      expect(decodeAiJson('{"amount": 15000'), null);
      expect(decodeAiJson("No pude leer la foto"), null);
      expect(decodeAiJson(""), null);
      expect(decodeAiJson(null), null);
      expect(decodeAiJson("[1, 2]"), null);
    });
  });

  group("AiTransactionDraft", () {
    DateTime today = DateTime(2026, 11, 19);
    test("full answer", () {
      AiTransactionDraft draft = AiTransactionDraft.fromJson({
        "amount": "15 mil",
        "type": "expense",
        "title": " Almuerzo ",
        "category": "Comida",
        "pocket": "Nequi",
        "date": "ayer",
        "note": null,
      }, today: today);
      expect(draft.amount, 15000);
      expect(draft.income, false);
      expect(draft.title, "Almuerzo");
      expect(draft.category, "Comida");
      expect(draft.pocket, "Nequi");
      expect(draft.date, DateTime(2026, 11, 18));
      expect(draft.note, null);
      expect(draft.electronicInvoice, false);
      expect(draft.isEmpty, false);
    });
    test("receipt keys", () {
      AiTransactionDraft draft = AiTransactionDraft.fromJson({
        "amount": 45900,
        "merchant": "Éxito",
        "date": "12/11/2026",
        "isElectronicInvoice": "true",
      }, today: today);
      expect(draft.amount, 45900);
      expect(draft.title, "Éxito");
      expect(draft.date, DateTime(2026, 11, 12));
      expect(draft.electronicInvoice, true);
      expect(draft.income, null);
    });
    test("income", () {
      expect(AiTransactionDraft.fromJson({"type": "income"}).income, true);
      expect(AiTransactionDraft.fromJson({"type": "ingreso"}).income, true);
      expect(AiTransactionDraft.fromJson({"isIncome": false}).income, false);
    });
    test("missing fields", () {
      AiTransactionDraft draft = AiTransactionDraft.fromJson({});
      expect(draft.isEmpty, true);
      expect(draft.amount, null);
      expect(draft.date, null);
      expect(
          AiTransactionDraft.fromJson({"amount": null, "merchant": null})
              .isEmpty,
          true);
      expect(AiTransactionDraft.fromJson({"amount": 0}).amount, null);
    });
    test("dates that make no sense are dropped", () {
      expect(parseAiDate("2026-02-31", today: today), null);
      expect(parseAiDate("2030-01-01", today: today), null);
      expect(parseAiDate("1999-05-01", today: today), null);
      expect(parseAiDate("mañana o algo", today: today), null);
      expect(parseAiDate("2026-11-19", today: today), DateTime(2026, 11, 19));
      expect(parseAiDate("hoy", today: today), DateTime(2026, 11, 19));
    });
  });

  group("AiLoanOffer", () {
    test("EA offer", () {
      AiLoanOffer offer = AiLoanOffer.fromJson({
        "amount": "\$8.000.000",
        "rate": "26,5%",
        "rateType": "E.A.",
        "months": 36,
        "installment": 320000,
        "monthlyFees": "12.000",
      });
      expect(offer.amount, 8000000);
      expect(offer.ratePercent, 26.5);
      expect(offer.rateKind, LoanRateKind.ea);
      expect(offer.months, 36);
      expect(offer.installment, 320000);
      expect(offer.monthlyFees, 12000);
      expect(offer.effectiveAnnualPercent!, closeTo(26.5, 0.0001));
    });
    test("monthly rate", () {
      AiLoanOffer offer =
          AiLoanOffer.fromJson({"rate": 1.9, "rateType": "mes vencido"});
      expect(offer.rateKind, LoanRateKind.monthlyArrears);
      expect(offer.effectiveAnnualPercent!, closeTo(25.34, 0.01));
      expect(AiLoanOffer.fromJson({"rate": 2, "rateType": "MA"}).rateKind,
          LoanRateKind.monthlyAnticipated);
    });
    test("missing type guesses from the size", () {
      expect(AiLoanOffer.fromJson({"rate": 2.1}).rateKind,
          LoanRateKind.monthlyArrears);
      expect(AiLoanOffer.fromJson({"rate": 24}).rateKind, LoanRateKind.ea);
    });
    test("empty", () {
      expect(AiLoanOffer.fromJson({}).isEmpty, true);
      expect(AiLoanOffer.fromJson({"months": "doce"}).months, null);
    });
  });

  group("names", () {
    test("bestNameMatch", () {
      List<String> names = ["Comida", "Transporte", "Nequi / Principal"];
      expect(bestNameMatch("comida", names), 0);
      expect(bestNameMatch("TRANSPORTE", names), 1);
      expect(bestNameMatch("Nequi", names), 2);
      expect(bestNameMatch("Salud", names), null);
      expect(bestNameMatch(null, names), null);
      expect(bestNameMatch("Educación", ["Educacion"]), 0);
    });
  });
}
