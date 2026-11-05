import 'dart:math';

// Interest-rate and loan math for the tools pages. Plain Dart, no Flutter,
// so it can be tested on its own. Rates are fractions: 0.02 means 2%.

enum RateType { ea, nmv, nama, em, natv }

// Every conversion goes through the effective monthly rate (EM)
double rateToMonthlyEffective(double rate, RateType type) {
  switch (type) {
    case RateType.ea:
      return pow(1 + rate, 1 / 12) - 1;
    case RateType.nmv:
      return rate / 12;
    case RateType.nama:
      // Anticipated monthly ia = i / (1 + i), so i = ia / (1 - ia)
      double anticipated = rate / 12;
      return anticipated / (1 - anticipated);
    case RateType.em:
      return rate;
    case RateType.natv:
      return pow(1 + rate / 4, 1 / 3) - 1;
  }
}

double monthlyEffectiveToRate(double monthly, RateType type) {
  switch (type) {
    case RateType.ea:
      return pow(1 + monthly, 12) - 1;
    case RateType.nmv:
      return monthly * 12;
    case RateType.nama:
      return monthly / (1 + monthly) * 12;
    case RateType.em:
      return monthly;
    case RateType.natv:
      return (pow(1 + monthly, 3) - 1) * 4;
  }
}

double convertRate(double rate, RateType from, RateType to) =>
    monthlyEffectiveToRate(rateToMonthlyEffective(rate, from), to);

// NAMA only makes sense below 1200% (ia must stay under 100% a month)
bool isValidRate(double rate, RateType type) {
  if (rate.isNaN || rate.isInfinite || rate < 0) return false;
  if (type == RateType.nama && rate / 12 >= 1) return false;
  return true;
}

class RateEquivalents {
  RateEquivalents(this.monthly)
      : ea = monthlyEffectiveToRate(monthly, RateType.ea),
        nmv = monthlyEffectiveToRate(monthly, RateType.nmv),
        nama = monthlyEffectiveToRate(monthly, RateType.nama),
        natv = monthlyEffectiveToRate(monthly, RateType.natv),
        daily = pow(1 + monthly, 12 / 365) - 1;

  factory RateEquivalents.from(double rate, RateType type) =>
      RateEquivalents(rateToMonthlyEffective(rate, type));

  final double monthly;
  final double ea;
  final double nmv;
  final double nama;
  final double natv;
  // Effective daily, on a 365-day year
  final double daily;

  double of(RateType type) {
    switch (type) {
      case RateType.ea:
        return ea;
      case RateType.nmv:
        return nmv;
      case RateType.nama:
        return nama;
      case RateType.em:
        return monthly;
      case RateType.natv:
        return natv;
    }
  }
}

// Reads "1.500.000", "1500000", "2,1", "2.1" and "1.500,5". A comma is the
// decimal mark. Without one, dots are thousands separators when there are
// several or, for amounts, when a single one is followed by three digits.
double? parseColombianNumber(String text, {bool amount = false}) {
  String value = text.replaceAll(RegExp(r'[\s$%]'), '');
  if (value.isEmpty) return null;
  int commas = ','.allMatches(value).length;
  int dots = '.'.allMatches(value).length;
  if (commas > 1 && dots == 0) {
    // 1,500,000
    value = value.replaceAll(',', '');
  } else if (commas > 0) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  } else if (dots > 1 ||
      (amount && RegExp(r'^\d{1,3}\.\d{3}$').hasMatch(value))) {
    value = value.replaceAll('.', '');
  }
  return double.tryParse(value);
}

// Loans

enum AmortizationSystem { fixedInstallment, constantPrincipal }

enum ExtraPaymentMode { reduceTerm, reduceInstallment }

class AmortizationRow {
  const AmortizationRow({
    required this.month,
    required this.interest,
    required this.principal,
    required this.fee,
    required this.extra,
    required this.balance,
  });
  final int month;
  final double interest;
  final double principal;
  final double fee;
  final double extra;
  final double balance;

  // What is paid that month without the extra payment
  double get installment => interest + principal + fee;
}

class LoanResult {
  const LoanResult(this.amount, this.rows);
  final double amount;
  final List<AmortizationRow> rows;

  int get months => rows.length;
  double get totalInterest => rows.fold(0, (sum, row) => sum + row.interest);
  double get totalFees => rows.fold(0, (sum, row) => sum + row.fee);
  double get totalExtra => rows.fold(0, (sum, row) => sum + row.extra);
  double get totalPaid => amount + totalInterest + totalFees;
  double get costOverAmount => amount == 0 ? 0 : totalPaid / amount - 1;
  double get firstInstallment => rows.isEmpty ? 0 : rows.first.installment;
  double get lastInstallment => rows.isEmpty ? 0 : rows.last.installment;
}

// French system: the same payment every month
double fixedInstallment(double principal, double monthlyRate, int months) {
  if (months <= 0) return principal;
  if (monthlyRate == 0) return principal / months;
  return principal * monthlyRate / (1 - pow(1 + monthlyRate, -months));
}

LoanResult simulateLoan({
  required double amount,
  required double monthlyRate,
  required int months,
  AmortizationSystem system = AmortizationSystem.fixedInstallment,
  double monthlyFee = 0,
  double extraAmount = 0,
  int extraMonth = 0,
  ExtraPaymentMode extraMode = ExtraPaymentMode.reduceTerm,
}) {
  List<AmortizationRow> rows = [];
  if (amount <= 0 || months <= 0) return LoanResult(amount, rows);

  double balance = amount;
  double payment = fixedInstallment(amount, monthlyRate, months);
  double principalPart = amount / months;

  for (int month = 1; month <= months && balance > 0.005; month++) {
    double interest = balance * monthlyRate;
    double principal = system == AmortizationSystem.fixedInstallment
        ? payment - interest
        : principalPart;
    if (principal > balance || month == months) principal = balance;
    balance -= principal;

    double extra = 0;
    if (extraAmount > 0 && month == extraMonth && balance > 0) {
      extra = min(extraAmount, balance);
      balance -= extra;
      int remaining = months - month;
      if (extraMode == ExtraPaymentMode.reduceInstallment && remaining > 0) {
        payment = fixedInstallment(balance, monthlyRate, remaining);
        principalPart = balance / remaining;
      }
    }

    rows.add(AmortizationRow(
      month: month,
      interest: interest,
      principal: principal,
      fee: monthlyFee,
      extra: extra,
      balance: balance < 0.005 ? 0 : balance,
    ));
  }
  return LoanResult(amount, rows);
}
