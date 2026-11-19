import 'package:budget/struct/colombia.dart';

// Income tax of personas naturales residentes, cédula general (rentas de
// trabajo). Pure math, no Flutter, so it can be tested on its own. All the
// figures come from colombia.dart.

// Employee share of the mandatory contributions: 4% health + 4% pension
const double employeeMandatoryContributionRate = 0.08;

// Independents pay health and pension in full on 40% of what they bill
double get independentMandatoryContributionRate =>
    independentBaseRate * (healthRate + pensionRate);

enum IncomeTaxWorkerKind { employee, independent }

double mandatoryContributionRate(IncomeTaxWorkerKind kind) =>
    kind == IncomeTaxWorkerKind.independent
        ? independentMandatoryContributionRate
        : employeeMandatoryContributionRate;

// One of the conditions of arts. 592 to 594-3 ET
class FilingCheck {
  const FilingCheck({
    required this.value,
    required this.thresholdUVT,
    required this.uvt,
    this.inclusive = false,
  });
  final double value;
  final double thresholdUVT;
  final double uvt;
  // Gross income obliges when it is equal or above, the rest when above
  final bool inclusive;

  double get threshold => thresholdUVT * uvt;
  double get valueUVT => uvt == 0 ? 0 : value / uvt;
  bool get obliges => inclusive ? value >= threshold : value > threshold;
}

class FilingValues {
  const FilingValues({
    this.grossIncome = 0,
    this.purchases = 0,
    this.creditCard = 0,
    this.deposits = 0,
    this.grossEquity = 0,
  });
  final double grossIncome;
  final double purchases;
  final double creditCard;
  final double deposits;
  final double grossEquity;
}

class FilingChecks {
  FilingChecks(FilingValues v, double uvt)
      : grossEquity = FilingCheck(
            value: v.grossEquity, thresholdUVT: filingGrossEquityUVT, uvt: uvt),
        grossIncome = FilingCheck(
            value: v.grossIncome,
            thresholdUVT: filingGrossIncomeUVT,
            uvt: uvt,
            inclusive: true),
        creditCard = FilingCheck(
            value: v.creditCard, thresholdUVT: filingCreditCardUVT, uvt: uvt),
        purchases = FilingCheck(
            value: v.purchases, thresholdUVT: filingPurchasesUVT, uvt: uvt),
        deposits = FilingCheck(
            value: v.deposits, thresholdUVT: filingDepositsUVT, uvt: uvt);

  final FilingCheck grossEquity;
  final FilingCheck grossIncome;
  final FilingCheck creditCard;
  final FilingCheck purchases;
  final FilingCheck deposits;

  List<FilingCheck> get all =>
      [grossIncome, purchases, creditCard, deposits, grossEquity];
  // Any one of them is enough
  bool get mustFile => all.any((c) => c.obliges);
}

class IncomeTaxInput {
  const IncomeTaxInput({
    required this.uvt,
    this.kind = IncomeTaxWorkerKind.employee,
    this.deductCosts = false,
    this.costs = 0,
    this.laborIncome = 0,
    this.otherIncome = 0,
    this.mandatoryContributions = 0,
    this.dependents = 0,
    this.housingInterest = 0,
    this.prepaidHealth = 0,
    this.voluntaryPension = 0,
    this.electronicInvoicePurchases = 0,
    this.withholdings = 0,
  });
  final double uvt;
  final IncomeTaxWorkerKind kind;
  // Rentas de trabajo no laborales: real costs and expenses instead of the
  // 25% exempt income, never both (art. 336 ET, Decreto 2231 de 2023)
  final bool deductCosts;
  final double costs;
  final double laborIncome;
  // Rest of the cédula general (rents, interest...), already net of its own
  // costs. No 25% exempt income on it
  final double otherIncome;
  // Health and pension, ingresos no constitutivos de renta (arts. 55 and 56)
  final double mandatoryContributions;
  final int dependents;
  final double housingInterest;
  final double prepaidHealth;
  // AFC / FPV
  final double voluntaryPension;
  final double electronicInvoicePurchases;
  final double withholdings;
}

class IncomeTaxResult {
  IncomeTaxResult({
    required this.uvt,
    required this.laborIncome,
    required this.otherIncome,
    required this.grossIncome,
    required this.mandatoryContributions,
    required this.costs,
    required this.capBase,
    required this.netIncome,
    required this.housingInterest,
    required this.prepaidHealth,
    required this.voluntaryPension,
    required this.laborExempt,
    required this.subjectToCap,
    required this.cap,
    required this.allowedWithinCap,
    required this.dependents,
    required this.electronicInvoice,
    required this.taxableIncome,
    required this.taxableUVT,
    required this.taxUVT,
    required this.tax,
    required this.withholdings,
  });
  final double uvt;
  final double laborIncome;
  final double otherIncome;
  final double grossIncome;
  final double mandatoryContributions;
  final double costs;
  // Income minus ingresos no constitutivos, what the 40% is taken from
  final double capBase;
  // Renta líquida: also minus costs
  final double netIncome;
  // Each one already within its own cap
  final double housingInterest;
  final double prepaidHealth;
  final double voluntaryPension;
  final double laborExempt;
  // Exempt income and deductions that share the 40% / 1340 UVT cap
  final double subjectToCap;
  final double cap;
  final double allowedWithinCap;
  // Outside the cap
  final double dependents;
  final double electronicInvoice;
  final double taxableIncome;
  final double taxableUVT;
  final double taxUVT;
  final double tax;
  final double withholdings;

  // Positive: to pay. Negative: in favor
  double get balance => tax - withholdings;
  bool get capBinds => subjectToCap > cap;
  // Share of the gross income that goes to the tax
  double get effectiveRate => grossIncome <= 0 ? 0 : tax / grossIncome;
  int get bracketIndex => incomeTaxBracketIndex(taxableUVT);
  IncomeTaxBracket get bracket => incomeTaxBrackets[bracketIndex];
  // UVT left to reach the next bracket, null in the last one
  double? get uvtToNextBracket {
    int next = bracketIndex + 1;
    if (next >= incomeTaxBrackets.length) return null;
    return incomeTaxBrackets[next].fromUVT - taxableUVT;
  }
}

// Position in incomeTaxBrackets, same rule as incomeTaxUVT
int incomeTaxBracketIndex(double taxableUVT) {
  int index = 0;
  for (int i = 0; i < incomeTaxBrackets.length; i++) {
    if (taxableUVT > incomeTaxBrackets[i].fromUVT) index = i;
  }
  return index;
}

double _clamp0(double value) => value < 0 ? 0 : value;
double _min(double a, double b) => a < b ? a : b;

// Art. 336 ET as left by Ley 2277 de 2022
IncomeTaxResult computeIncomeTax(IncomeTaxInput input) {
  double uvt = input.uvt;
  double labor = _clamp0(input.laborIncome);
  double other = _clamp0(input.otherIncome);
  double gross = labor + other;
  // Contributions come out of the labor income
  double contributions = _min(_clamp0(input.mandatoryContributions), labor);
  double capBase = gross - contributions;
  bool withCosts =
      input.kind == IncomeTaxWorkerKind.independent && input.deductCosts;
  double costs =
      withCosts ? _min(_clamp0(input.costs), labor - contributions) : 0;
  double laborNet = labor - contributions - costs;
  double net = capBase - costs;

  // Deductions and other exempt income, each within its own cap
  double housing =
      _min(_clamp0(input.housingInterest), housingInterestCapUVT * uvt);
  double prepaid =
      _min(_clamp0(input.prepaidHealth), prepaidHealthCapUVT * uvt);
  double voluntary = _min(_clamp0(input.voluntaryPension),
      _min(voluntaryPensionRate * gross, voluntaryPensionCapUVT * uvt));
  // 72 UVT each, only against rentas de trabajo
  int dependentsCount = input.dependents.clamp(0, dependentDeductionMax);
  double dependents =
      _min(dependentsCount * dependentDeductionUVT * uvt, laborNet);

  // 25% exempt, worked out once the other deductions and exempt income are
  // taken off (art. 206 num. 10), capped a year. Not with real costs
  double laborExempt = 0;
  if (withCosts == false) {
    double exemptBase =
        _clamp0(laborNet - housing - prepaid - voluntary - dependents);
    laborExempt = _min(exemptBase * laborExemptRate, laborExemptCapUVT * uvt);
  }

  double subjectToCap = laborExempt + housing + prepaid + voluntary;
  double cap = _min(
      capBase * exemptAndDeductionsCapRate, exemptAndDeductionsCapUVT * uvt);
  double allowed = _min(subjectToCap, cap);

  // Art. 336 par. 5: 1% of the purchases backed by an electronic invoice
  double invoice = _min(
      _clamp0(input.electronicInvoicePurchases) * electronicInvoiceRate,
      electronicInvoiceCapUVT * uvt);

  double taxable = _clamp0(net - allowed - dependents - invoice);
  double taxableUVT = uvt == 0 ? 0 : taxable / uvt;
  double taxUVT = incomeTaxUVT(taxableUVT);
  return IncomeTaxResult(
    uvt: uvt,
    laborIncome: labor,
    otherIncome: other,
    grossIncome: gross,
    mandatoryContributions: contributions,
    costs: costs,
    capBase: capBase,
    netIncome: net,
    housingInterest: housing,
    prepaidHealth: prepaid,
    voluntaryPension: voluntary,
    laborExempt: laborExempt,
    subjectToCap: subjectToCap,
    cap: cap,
    allowedWithinCap: allowed,
    dependents: dependents,
    electronicInvoice: invoice,
    taxableIncome: taxable,
    taxableUVT: taxableUVT,
    taxUVT: taxUVT,
    tax: taxUVT * uvt,
    withholdings: _clamp0(input.withholdings),
  );
}

// Same input with the other independent option, to compare both
IncomeTaxResult computeOtherIndependentOption(IncomeTaxInput input) {
  return computeIncomeTax(IncomeTaxInput(
    uvt: input.uvt,
    kind: input.kind,
    deductCosts: !input.deductCosts,
    costs: input.costs,
    laborIncome: input.laborIncome,
    otherIncome: input.otherIncome,
    mandatoryContributions: input.mandatoryContributions,
    dependents: input.dependents,
    housingInterest: input.housingInterest,
    prepaidHealth: input.prepaidHealth,
    voluntaryPension: input.voluntaryPension,
    electronicInvoicePurchases: input.electronicInvoicePurchases,
    withholdings: input.withholdings,
  ));
}

// Reads "1.500.000", "1500000", "1.500.000,50" or "1500.5". A single dot
// followed by three digits is a thousands separator.
double parseTaxAmount(String text) {
  String t = text.replaceAll(RegExp(r"[\s$]"), "").replaceAll("COP", "");
  if (t.isEmpty) return 0;
  if (t.contains(",")) {
    t = t.replaceAll(".", "").replaceAll(",", ".");
  } else if (".".allMatches(t).length > 1 ||
      RegExp(r"^-?\d{1,3}\.\d{3}$").hasMatch(t)) {
    t = t.replaceAll(".", "");
  }
  return double.tryParse(t) ?? 0;
}

// 1500000 -> "1.500.000", decimals after a comma
String formatTaxNumber(double value, {int decimals = 0}) {
  bool negative = value < 0;
  String fixed = value.abs().toStringAsFixed(decimals);
  List<String> parts = fixed.split(".");
  String digits = parts[0];
  StringBuffer grouped = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(".");
    grouped.write(digits[i]);
  }
  String result = grouped.toString();
  if (parts.length > 1 && int.parse(parts[1]) != 0) {
    result += "," + parts[1];
  }
  return (negative ? "-" : "") + result;
}
