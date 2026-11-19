// Checks for lib/pages/tools/rateMath.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:budget/pages/tools/rateMath.dart';

int failures = 0;

void expectClose(String name, double actual, double expected,
    {double tolerance = 1e-6}) {
  if ((actual - expected).abs() > tolerance) {
    failures++;
    print("FAIL $name: got $actual, expected $expected");
  } else {
    print("ok   $name");
  }
}

void expectTrue(String name, bool value) {
  if (!value) failures++;
  print("${value ? "ok  " : "FAIL"} $name");
}

void main() {
  test('rate math', runChecks);
}

void runChecks() {
  // Rate conversions, from 2% effective monthly
  RateEquivalents rates = RateEquivalents(0.02);
  expectClose("EM to EA", rates.ea, pow(1.02, 12) - 1);
  expectClose("EM to EA value", rates.ea, 0.268242, tolerance: 1e-6);
  expectClose("EM to NMV", rates.nmv, 0.24);
  expectClose("EM to NAMA", rates.nama, 0.02 / 1.02 * 12);
  expectClose("EM to NATV", rates.natv, (pow(1 + rates.ea, 0.25) - 1) * 4);
  expectClose("EM to daily", rates.daily, pow(1 + rates.ea, 1 / 365) - 1);
  expectClose(
      "NMV 24% to EM", rateToMonthlyEffective(0.24, RateType.nmv), 0.02);
  expectClose("EA to EM", rateToMonthlyEffective(rates.ea, RateType.ea), 0.02);
  for (RateType from in RateType.values) {
    for (RateType to in RateType.values) {
      double there = convertRate(0.25, from, to);
      expectClose("round trip ${from.name} -> ${to.name}",
          convertRate(there, to, from), 0.25);
    }
  }
  expectTrue("NAMA of 1200% is invalid", !isValidRate(12, RateType.nama));
  expectTrue("negative rate is invalid", !isValidRate(-0.1, RateType.ea));

  // Colombian number input
  expectClose(
      "1.500.000", parseColombianNumber("1.500.000", amount: true)!, 1500000);
  expectClose(
      "1.500 amount", parseColombianNumber("1.500", amount: true)!, 1500);
  expectClose("1.500 rate", parseColombianNumber("1.500")!, 1.5);
  expectClose("2,1", parseColombianNumber("2,1")!, 2.1);
  expectClose("2.1", parseColombianNumber("2.1", amount: true)!, 2.1);
  expectClose(
      "1.500,5", parseColombianNumber("1.500,5", amount: true)!, 1500.5);
  expectClose(
      "1,500,000", parseColombianNumber("1,500,000", amount: true)!, 1500000);
  expectTrue("empty is null", parseColombianNumber(" ") == null);

  // French system: 1.000.000 at 2% EM over 12 months
  LoanResult french =
      simulateLoan(amount: 1000000, monthlyRate: 0.02, months: 12);
  expectClose("french installment", french.firstInstallment, 94559.60,
      tolerance: 0.01);
  expectClose("french last installment", french.lastInstallment,
      french.firstInstallment,
      tolerance: 0.01);
  expectTrue("french 12 months", french.months == 12);
  expectClose("french ends at zero", french.rows.last.balance, 0);
  expectClose("french interest", french.totalInterest,
      french.firstInstallment * 12 - 1000000,
      tolerance: 0.01);

  // Constant principal: 1.200.000 at 1% over 12 months
  LoanResult constant = simulateLoan(
    amount: 1200000,
    monthlyRate: 0.01,
    months: 12,
    system: AmortizationSystem.constantPrincipal,
  );
  expectClose("constant principal interest", constant.totalInterest, 78000,
      tolerance: 0.01);
  expectClose("constant first installment", constant.firstInstallment, 112000,
      tolerance: 0.01);

  // Fee is added to every installment
  LoanResult withFee = simulateLoan(
      amount: 1000000, monthlyRate: 0.02, months: 12, monthlyFee: 10000);
  expectClose("fees total", withFee.totalFees, 120000);
  expectClose(
      "total paid with fees", withFee.totalPaid, french.totalPaid + 120000,
      tolerance: 0.01);

  // Extra payment at month 3
  LoanResult shorter = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraAmount: 300000,
    extraMonth: 3,
  );
  expectTrue("reduce term ends earlier", shorter.months < 12);
  expectTrue("reduce term saves interest",
      shorter.totalInterest < french.totalInterest);
  expectClose("reduce term ends at zero", shorter.rows.last.balance, 0);

  LoanResult lighter = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraAmount: 300000,
    extraMonth: 3,
    extraMode: ExtraPaymentMode.reduceInstallment,
  );
  expectTrue("reduce installment keeps term", lighter.months == 12);
  expectTrue("reduce installment lowers it",
      lighter.rows[3].installment < french.firstInstallment);
  expectTrue("reduce term saves more than reduce installment",
      shorter.totalInterest < lighter.totalInterest);
  expectClose(
      "principal adds up",
      lighter.rows.fold(0.0, (sum, row) => sum + row.principal + row.extra),
      1000000,
      tolerance: 0.01);

  // Several extra payments
  LoanResult twoExtras = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraPayments: const [
      ExtraPayment(month: 3, amount: 150000),
      ExtraPayment(month: 6, amount: 150000),
    ],
  );
  expectClose("two extras add up", twoExtras.totalExtra, 300000,
      tolerance: 0.01);
  expectTrue("two extras end earlier", twoExtras.months < 12);
  expectTrue("later extra saves less than an early one",
      twoExtras.totalInterest > shorter.totalInterest);
  expectClose("two extras end at zero", twoExtras.rows.last.balance, 0);
  LoanResult sameAsSingle = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraPayments: const [ExtraPayment(month: 3, amount: 300000)],
  );
  expectClose("list matches the single extra", sameAsSingle.totalInterest,
      shorter.totalInterest);
  LoanResult mixed = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraPayments: const [
      ExtraPayment(
          month: 3, amount: 300000, mode: ExtraPaymentMode.reduceInstallment),
    ],
  );
  expectClose("per payment mode", mixed.totalInterest, lighter.totalInterest);
  LoanResult tooMuch = simulateLoan(
    amount: 1000000,
    monthlyRate: 0.02,
    months: 12,
    extraPayments: const [ExtraPayment(month: 2, amount: 5000000)],
  );
  expectTrue("an extra bigger than the balance pays it off",
      tooMuch.months == 2 && tooMuch.rows.last.balance == 0);
  ExtraPaymentSavings savings = ExtraPaymentSavings(french, shorter);
  expectClose("savings interest", savings.interest,
      french.totalInterest - shorter.totalInterest);
  expectTrue("savings months", savings.months == 12 - shorter.months);

  // Loan rate kinds
  expectClose(
      "1% anticipated in arrears",
      loanRateToMonthlyEffective(0.01, LoanRateKind.monthlyAnticipated),
      0.01 / 0.99);
  expectClose("anticipated round trip",
      arrearsToAnticipated(anticipatedToArrears(0.018)), 0.018);
  expectClose(
      "12% NAMA is 1% anticipated",
      loanRateToMonthlyEffective(0.12, LoanRateKind.nama),
      loanRateToMonthlyEffective(0.01, LoanRateKind.monthlyAnticipated));
  expectClose("26% EA monthly",
      loanRateToMonthlyEffective(0.26, LoanRateKind.ea), pow(1.26, 1 / 12) - 1);
  expectClose("MV is the effective monthly",
      loanRateToMonthlyEffective(0.019, LoanRateKind.monthlyArrears), 0.019);
  expectTrue(
      "anticipated costs more than arrears",
      loanRateToMonthlyEffective(0.02, LoanRateKind.monthlyAnticipated) >
          loanRateToMonthlyEffective(0.02, LoanRateKind.monthlyArrears));
  for (LoanRateKind kind in LoanRateKind.values) {
    expectClose(
        "loan rate round trip ${kind.name}",
        monthlyEffectiveToLoanRate(loanRateToMonthlyEffective(0.2, kind), kind),
        0.2);
  }
  expectTrue("100% anticipated monthly is invalid",
      !isValidLoanRate(1, LoanRateKind.monthlyAnticipated));
  expectTrue("NAMA 1200% is invalid", !isValidLoanRate(12, LoanRateKind.nama));
  expectTrue("26% EA is valid", isValidLoanRate(0.26, LoanRateKind.ea));

  // Example: motorcycle of 8.000.000 at 26% EA over 36 months
  LoanResult motorcycle = simulateLoan(
    amount: 8000000,
    monthlyRate: loanRateToMonthlyEffective(0.26, LoanRateKind.ea),
    months: 36,
  );
  expectClose("motorcycle installment", motorcycle.firstInstallment, 313000,
      tolerance: 3000);
  expectTrue("motorcycle 36 months", motorcycle.months == 36);

  // Affordability
  expectTrue("no income gives no ratio", debtToIncomeRatio(100, 0) == null);
  expectClose("ratio", debtToIncomeRatio(600000, 2000000)!, 0.3);
  expectTrue("30% is healthy", debtLevel(0.30) == DebtLevel.healthy);
  expectTrue("35% is caution", debtLevel(0.35) == DebtLevel.caution);
  expectTrue("40% is caution", debtLevel(0.40) == DebtLevel.caution);
  expectTrue("41% is risky", debtLevel(0.41) == DebtLevel.risky);
  expectClose("max affordable installment",
      maxAffordableInstallment(2000000, 200000), 400000);
  expectClose("max affordable never negative",
      maxAffordableInstallment(1000000, 500000), 0);
  expectClose("biweekly income doubles",
      monthlyIncomeFrom(PayFrequency.biweekly, 900000), 1800000);
  expectClose("monthly income stays",
      monthlyIncomeFrom(PayFrequency.monthly, 1800000), 1800000);

  // Dates
  expectTrue("Jan 31 + 1 month is Feb 28",
      addMonthsClamped(DateTime(2027, 1, 31), 1) == DateTime(2027, 2, 28));
  expectTrue("Nov 19 + 35 months",
      addMonthsClamped(DateTime(2026, 11, 19), 35) == DateTime(2029, 10, 19));
  expectTrue("Dec + 1 month crosses the year",
      addMonthsClamped(DateTime(2026, 12, 5), 1) == DateTime(2027, 1, 5));
  expectTrue("next 15th from the 19th",
      nextDayOfMonth(DateTime(2026, 11, 19), 15) == DateTime(2026, 12, 15));
  expectTrue("next 30th from the 19th",
      nextDayOfMonth(DateTime(2026, 11, 19), 30) == DateTime(2026, 11, 30));
  expectTrue("payday today counts",
      nextDayOfMonth(DateTime(2026, 11, 15, 10), 15) == DateTime(2026, 11, 15));
  expectTrue("30th in February is the 28th",
      nextDayOfMonth(DateTime(2027, 2, 1), 30) == DateTime(2027, 2, 28));
  expectTrue("next 30th from Dec 31",
      nextDayOfMonth(DateTime(2026, 12, 31), 30) == DateTime(2027, 1, 30));
  expectTrue(
      "12 installments left",
      remainingMonthlyInstallments(
              DateTime(2026, 12, 15), DateTime(2027, 11, 15)) ==
          12);
  expectTrue(
      "last installment only",
      remainingMonthlyInstallments(
              DateTime(2026, 12, 15), DateTime(2026, 12, 15)) ==
          1);
  expectTrue(
      "none left",
      remainingMonthlyInstallments(
              DateTime(2026, 12, 15), DateTime(2026, 11, 15)) ==
          0);
  expectTrue(
      "short month end",
      remainingMonthlyInstallments(
              DateTime(2027, 1, 31), DateTime(2027, 2, 28)) ==
          2);

  expect(failures, 0);
}
