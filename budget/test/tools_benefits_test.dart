import 'dart:math';

import 'package:budget/pages/tools/benefitsCalculatorPage.dart';
import 'package:budget/pages/tools/cdtSimulatorPage.dart';
import 'package:budget/pages/tools/pilaCalculatorPage.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/colombia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("parseToolNumber", () {
    test("reads Colombian and plain formats", () {
      expect(parseToolNumber("1.500.000"), 1500000);
      expect(parseToolNumber("1'500.000"), 1500000);
      expect(parseToolNumber("\$ 2.000.000,50"), 2000000.5);
      expect(parseToolNumber("1,500,000"), 1500000);
      expect(parseToolNumber("1,500,000.25"), 1500000.25);
      expect(parseToolNumber("1.500"), 1500);
      expect(parseToolNumber("4,5"), 4.5);
      expect(parseToolNumber("12.5"), 12.5);
      expect(parseToolNumber("0.125"), 0.125);
      expect(parseToolNumber("10,5 %"), 10.5);
      expect(parseToolNumber(""), null);
      expect(parseToolNumber("abc"), null);
    });
  });

  group("CDT", () {
    test("rate for the term", () {
      expect(effectiveRateForDays(0.10, 365), closeTo(0.10, 1e-12));
      expect(effectiveRateForDays(0.10, 180), closeTo(0.048124, 1e-5));
    });

    test("at maturity", () {
      CdtResult r = simulateCdt(
        amount: 10000000,
        annualRate: 0.10,
        days: 365,
        withholdingRate: 0.04,
        inflation: 0.05,
      )!;
      expect(r.grossInterest, closeTo(1000000, 1e-6));
      expect(r.withholding, closeTo(40000, 1e-6));
      expect(r.netInterest, closeTo(960000, 1e-6));
      expect(r.finalAmount, closeTo(10960000, 1e-6));
      expect(r.netAnnualRate, closeTo(0.096, 1e-9));
      expect(r.realReturn, closeTo(1.096 / 1.05 - 1, 1e-9));
      expect(r.beatsInflation, true);
    });

    test("monthly payments earn less than compounding at maturity", () {
      CdtResult monthly = simulateCdt(
        amount: 10000000,
        annualRate: 0.10,
        days: 360,
        payment: CdtInterestPayment.monthly,
      )!;
      CdtResult maturity = simulateCdt(
        amount: 10000000,
        annualRate: 0.10,
        days: 360,
      )!;
      double monthlyRate = effectiveRateForDays(0.10, 30);
      expect(monthly.grossInterest, closeTo(10000000 * monthlyRate * 12, 1e-6));
      expect(monthly.grossInterest, lessThan(maturity.grossInterest));
      expect(monthly.withholding,
          closeTo(monthly.grossInterest * cdtWithholdingRate, 1e-6));
      // Net annual rate as if each net payment were reinvested
      expect(monthly.netAnnualRate,
          closeTo(pow(1 + monthlyRate * (1 - cdtWithholdingRate), 365 / 30) - 1,
              1e-12));
    });

    test("losing to inflation and missing inflation", () {
      CdtResult r = simulateCdt(
        amount: 1000000,
        annualRate: 0.05,
        days: 90,
        inflation: 0.06,
      )!;
      expect(r.beatsInflation, false);
      expect(simulateCdt(amount: 1000000, annualRate: 0.05, days: 90)!
          .beatsInflation, null);
      expect(simulateCdt(amount: 0, annualRate: 0.05, days: 90), null);
    });
  });

  group("prestaciones", () {
    test("360 day count", () {
      expect(days360(DateTime(2026, 1, 1), DateTime(2026, 6, 30)), 180);
      expect(days360(DateTime(2026, 1, 1), DateTime(2026, 12, 31)), 360);
      expect(days360(DateTime(2026, 7, 1), DateTime(2026, 12, 20)), 170);
      expect(days360(DateTime(2026, 2, 1), DateTime(2026, 2, 28)), 30);
      expect(days360(DateTime(2026, 2, 28), DateTime(2026, 3, 1)), 2);
      expect(days360(DateTime(2025, 3, 15), DateTime(2026, 3, 14)), 360);
      expect(days360(DateTime(2026, 5, 1), DateTime(2026, 4, 1)), 0);
    });

    test("transport aid and salario integral thresholds", () {
      double wage = colombiaYear(2026).minimumWage;
      expect(defaultsToTransportAid(2 * wage, 2026), true);
      expect(defaultsToTransportAid(2 * wage + 1, 2026), false);
      expect(reachesIntegralSalary(13 * wage, 2026), true);
      expect(reachesIntegralSalary(13 * wage - 1, 2026), false);
    });

    test("a full year", () {
      double salary = colombiaYear(2026).minimumWage;
      double aid = colombiaYear(2026).transportAid;
      BenefitsResult r = benefitsBetweenDates(
        salary: salary,
        aid: aid,
        start: DateTime(2026, 1, 1),
        cutoff: DateTime(2026, 12, 31),
      );
      expect(r.primaDays, 180);
      expect(r.severanceDays, 360);
      expect(r.vacationDays, 360);
      expect(r.prima, closeTo((salary + aid) / 2, 1e-6));
      expect(r.severance, closeTo(salary + aid, 1e-6));
      expect(r.severanceInterest,
          closeTo((salary + aid) * severanceInterestRate, 1e-6));
      expect(r.vacation, closeTo(salary / 2, 1e-6));
      expect(r.primaPaymentDate, DateTime(2026, 12, 20));
      expect(r.severanceInterestDate, DateTime(2027, 1, 31));
      expect(r.severanceDepositDate, DateTime(2027, 2, 14));
    });

    test("started mid semester", () {
      BenefitsResult r = benefitsBetweenDates(
        salary: 3000000,
        aid: 0,
        start: DateTime(2025, 11, 1),
        cutoff: DateTime(2026, 3, 30),
      );
      expect(r.primaDays, 90);
      expect(r.severanceDays, 90);
      expect(r.vacationDays, 150);
      expect(r.prima, closeTo(750000, 1e-6));
      expect(r.severance, closeTo(750000, 1e-6));
      expect(r.severanceInterest, closeTo(750000 * 90 * 0.12 / 360, 1e-6));
      expect(r.vacation, closeTo(3000000 * 150 / 720, 1e-6));
      expect(r.primaPaymentDate, DateTime(2026, 6, 30));
    });

    test("by days and salario integral", () {
      BenefitsResult r = benefitsForDays(salary: 2000000, aid: 0, days: 90);
      expect(r.prima, closeTo(500000, 1e-6));
      expect(r.primaPaymentDate, null);
      BenefitsResult integral = benefitsForDays(
          salary: 30000000, aid: 0, days: 360, integralSalary: true);
      expect(integral.prima, 0);
      expect(integral.severance, 0);
      expect(integral.severanceInterest, 0);
      expect(integral.vacation, closeTo(15000000, 1e-6));
    });
  });

  group("PILA", () {
    double wage = colombiaYear(2026).minimumWage;

    test("40% of the income", () {
      PilaResult r = calculatePila(income: 5000000, arlClass: 1, year: 2026);
      expect(r.contributionBase, 2000000);
      expect(r.health, 250000);
      expect(r.pension, 320000);
      expect(r.arl, 10500); // 10.440 rounded up to the next 100
      expect(r.total, 580500);
      expect(r.shareOfIncome, closeTo(0.1161, 1e-9));
      expect(r.belowMinimumWage, false);
    });

    test("never below one minimum wage", () {
      PilaResult r = calculatePila(income: 1000000, year: 2026);
      expect(r.contributionBase, wage.ceilToDouble());
      expect(r.arl, 0);
      expect(r.belowMinimumWage, true);
      expect(r.health, roundUpToHundred(wage * healthRate));
    });

    test("never above 25 minimum wages", () {
      PilaResult r = calculatePila(income: 1000 * wage, arlClass: 5, year: 2026);
      expect(r.contributionBase, (25 * wage).ceilToDouble());
      expect(r.cappedAtMaximum, true);
      expect(r.arl, roundUpToHundred(r.contributionBase * arlRates[4]));
    });

    test("rounding", () {
      expect(roundUpToHundred(10440), 10500);
      expect(roundUpToHundred(10400), 10400);
      expect(roundUpToHundred(0), 0);
    });
  });
}
