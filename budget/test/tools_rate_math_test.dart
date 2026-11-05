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

  expect(failures, 0);
}
