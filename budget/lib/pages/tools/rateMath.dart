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

// An abono extraordinario: money paid to the principal on top of the
// installment of that month. Without a mode it uses the loan's
class ExtraPayment {
  const ExtraPayment({required this.month, required this.amount, this.mode});
  final int month;
  final double amount;
  final ExtraPaymentMode? mode;
}

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
  List<ExtraPayment> extraPayments = const [],
}) {
  List<AmortizationRow> rows = [];
  if (amount <= 0 || months <= 0) return LoanResult(amount, rows);

  // Extra payments grouped by month; the single extra payment is kept for
  // older callers
  Map<int, double> extraByMonth = {};
  Map<int, ExtraPaymentMode> modeByMonth = {};
  void addExtra(int month, double value, ExtraPaymentMode mode) {
    if (value <= 0 || month <= 0) return;
    extraByMonth[month] = (extraByMonth[month] ?? 0) + value;
    // Reducing the installment wins when two payments share a month
    if (modeByMonth[month] != ExtraPaymentMode.reduceInstallment) {
      modeByMonth[month] = mode;
    }
  }

  addExtra(extraMonth, extraAmount, extraMode);
  for (ExtraPayment payment in extraPayments) {
    addExtra(payment.month, payment.amount, payment.mode ?? extraMode);
  }

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
    double extraDue = extraByMonth[month] ?? 0;
    if (extraDue > 0 && balance > 0) {
      extra = min(extraDue, balance);
      balance -= extra;
      int remaining = months - month;
      if (modeByMonth[month] == ExtraPaymentMode.reduceInstallment &&
          remaining > 0) {
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

// How a loan offer states its rate. Monthly rates come "mes vencido" (paid
// at the end of the month) or "mes anticipado" (charged at the start).
// Everything is simulated with the equivalent effective monthly rate
enum LoanRateKind { ea, monthlyArrears, monthlyAnticipated, nmv, nama }

// An anticipated monthly rate ia costs the same as i = ia / (1 - ia) in
// arrears
double anticipatedToArrears(double anticipated) =>
    anticipated / (1 - anticipated);

double arrearsToAnticipated(double arrears) => arrears / (1 + arrears);

bool isValidLoanRate(double rate, LoanRateKind kind) {
  if (rate.isNaN || rate.isInfinite || rate < 0) return false;
  if (kind == LoanRateKind.monthlyAnticipated && rate >= 1) return false;
  if (kind == LoanRateKind.nama) return isValidRate(rate, RateType.nama);
  return true;
}

double loanRateToMonthlyEffective(double rate, LoanRateKind kind) {
  switch (kind) {
    case LoanRateKind.ea:
      return rateToMonthlyEffective(rate, RateType.ea);
    case LoanRateKind.monthlyArrears:
      return rate;
    case LoanRateKind.monthlyAnticipated:
      return anticipatedToArrears(rate);
    case LoanRateKind.nmv:
      return rateToMonthlyEffective(rate, RateType.nmv);
    case LoanRateKind.nama:
      return rateToMonthlyEffective(rate, RateType.nama);
  }
}

double monthlyEffectiveToLoanRate(double monthly, LoanRateKind kind) {
  switch (kind) {
    case LoanRateKind.ea:
      return monthlyEffectiveToRate(monthly, RateType.ea);
    case LoanRateKind.monthlyArrears:
      return monthly;
    case LoanRateKind.monthlyAnticipated:
      return arrearsToAnticipated(monthly);
    case LoanRateKind.nmv:
      return monthlyEffectiveToRate(monthly, RateType.nmv);
    case LoanRateKind.nama:
      return monthlyEffectiveToRate(monthly, RateType.nama);
  }
}

// Savings of a plan with extra payments against the same loan without them
class ExtraPaymentSavings {
  ExtraPaymentSavings(LoanResult base, LoanResult withExtra)
      : interest = base.totalInterest - withExtra.totalInterest,
        fees = base.totalFees - withExtra.totalFees,
        months = base.months - withExtra.months;
  final double interest;
  final double fees;
  final int months;

  double get total => interest + fees;
}

// Affordability. Common guidance: up to 30% of the monthly income going to
// debt installments is healthy, 30% to 40% calls for caution, above 40% is
// risky. It is a general guide, not a rule of any bank

enum DebtLevel { healthy, caution, risky }

const double debtHealthyLimit = 0.30;
const double debtCautionLimit = 0.40;

// Share of the monthly income that goes to installments, null without income
double? debtToIncomeRatio(double monthlyInstallments, double monthlyIncome) {
  if (monthlyIncome <= 0) return null;
  return monthlyInstallments / monthlyIncome;
}

DebtLevel debtLevel(double ratio) {
  if (ratio <= debtHealthyLimit + 1e-9) return DebtLevel.healthy;
  if (ratio <= debtCautionLimit + 1e-9) return DebtLevel.caution;
  return DebtLevel.risky;
}

// The biggest installment that stays within a share of the income, after
// the installments already being paid
double maxAffordableInstallment(
    double monthlyIncome, double currentInstallments,
    {double limit = debtHealthyLimit}) {
  return max(0, monthlyIncome * limit - currentInstallments);
}

enum PayFrequency { monthly, biweekly, variable }

// Monthly income from what is received each time: biweekly pay comes twice
double monthlyIncomeFrom(PayFrequency frequency, double amount) {
  if (amount <= 0) return 0;
  return frequency == PayFrequency.biweekly ? amount * 2 : amount;
}

// Dates

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

// The same day some months later, moved back to the last day when the month
// is shorter: Jan 31 + 1 month is Feb 28
DateTime addMonthsClamped(DateTime date, int months) {
  int monthIndex = date.month - 1 + months;
  int year = date.year + (monthIndex / 12).floor();
  int month = monthIndex % 12 + 1;
  return DateTime(year, month, min(date.day, daysInMonth(year, month)));
}

// The next date, from today on, that falls on that day of the month
// (clamped to the last day of short months)
DateTime nextDayOfMonth(DateTime from, int day) {
  DateTime today = DateTime(from.year, from.month, from.day);
  DateTime candidate = DateTime(
      today.year, today.month, min(day, daysInMonth(today.year, today.month)));
  if (candidate.isBefore(today)) {
    int year = today.month == 12 ? today.year + 1 : today.year;
    int month = today.month == 12 ? 1 : today.month + 1;
    candidate = DateTime(year, month, min(day, daysInMonth(year, month)));
  }
  return candidate;
}

// Monthly installments left from the next one up to the last one, both
// included
int remainingMonthlyInstallments(DateTime next, DateTime last) {
  if (last.isBefore(DateTime(next.year, next.month, next.day))) return 0;
  int months = (last.year - next.year) * 12 + last.month - next.month;
  if (last.day < next.day && last.day < daysInMonth(last.year, last.month))
    months--;
  return max(0, months + 1);
}
