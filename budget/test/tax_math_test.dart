import 'package:budget/pages/tools/incomeTaxMath.dart';
import 'package:budget/struct/colombia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final double uvt = colombiaYear(2025).uvt;
  double inUVT(double amount) => amount / uvt;

  group("tax table", () {
    test("one case per bracket", () {
      expect(incomeTaxUVT(500), 0);
      expect(incomeTaxUVT(1090), 0);
      expect(incomeTaxUVT(1500), closeTo((1500 - 1090) * 0.19, 1e-9));
      expect(incomeTaxUVT(3000), closeTo((3000 - 1700) * 0.28 + 116, 1e-9));
      expect(incomeTaxUVT(5000), closeTo((5000 - 4100) * 0.33 + 788, 1e-9));
      expect(incomeTaxUVT(10000), closeTo((10000 - 8670) * 0.35 + 2296, 1e-9));
      expect(
          incomeTaxUVT(20000), closeTo((20000 - 18970) * 0.37 + 5901, 1e-9));
      expect(
          incomeTaxUVT(40000), closeTo((40000 - 31000) * 0.39 + 10352, 1e-9));
    });

    test("the table has no jumps between brackets", () {
      for (IncomeTaxBracket b in incomeTaxBrackets.skip(1)) {
        expect(incomeTaxUVT(b.fromUVT + 0.001), closeTo(b.baseTaxUVT, 1));
      }
    });
  });

  group("estimate", () {
    test("taxable income below 1090 UVT pays nothing", () {
      IncomeTaxResult r = computeIncomeTax(
          IncomeTaxInput(uvt: uvt, laborIncome: 1000 * uvt));
      // 25% exempt, below the 40% cap
      expect(inUVT(r.laborExempt), closeTo(250, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(750, 1e-6));
      expect(r.tax, 0);
      expect(r.balance, 0);
    });

    test("mandatory contributions come off before everything", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 2000 * uvt,
        mandatoryContributions: 2000 * uvt * employeeMandatoryContributionRate,
      ));
      expect(inUVT(r.netIncome), closeTo(1840, 1e-6));
      expect(inUVT(r.laborExempt), closeTo(460, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(1380, 1e-6));
      expect(r.taxUVT, closeTo((1380 - 1090) * 0.19, 1e-6));
      expect(r.tax, closeTo(r.taxUVT * uvt, 1e-6));
    });

    test("the 40% cap binds", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 3000 * uvt,
        housingInterest: 1200 * uvt,
        prepaidHealth: 192 * uvt,
      ));
      // 25% of 3000 - 1200 - 192, plus both deductions
      expect(inUVT(r.subjectToCap), closeTo(402 + 1200 + 192, 1e-6));
      expect(inUVT(r.cap), closeTo(1200, 1e-6));
      expect(r.capBinds, true);
      expect(inUVT(r.taxableIncome), closeTo(1800, 1e-6));
      expect(r.taxUVT, closeTo(100 * 0.28 + 116, 1e-6));
    });

    test("the 1340 UVT cap binds, dependents and invoice go outside it", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 10000 * uvt,
        housingInterest: 1200 * uvt,
        dependents: 2,
        electronicInvoicePurchases: 10000 * uvt,
      ));
      expect(inUVT(r.laborExempt), closeTo(laborExemptCapUVT, 1e-6));
      expect(inUVT(r.cap), closeTo(exemptAndDeductionsCapUVT, 1e-6));
      expect(inUVT(r.allowedWithinCap), closeTo(1340, 1e-6));
      expect(inUVT(r.dependents), closeTo(144, 1e-6));
      expect(inUVT(r.electronicInvoice), closeTo(100, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(10000 - 1340 - 144 - 100, 1e-6));
      expect(r.taxUVT, closeTo((8416 - 4100) * 0.33 + 788, 1e-6));
    });

    test("dependents lower the tax even when the cap binds", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 3000 * uvt,
        housingInterest: 1200 * uvt,
        prepaidHealth: 192 * uvt,
        dependents: 6, // only 4 count
      ));
      expect(inUVT(r.dependents), closeTo(4 * dependentDeductionUVT, 1e-6));
      expect(r.capBinds, true);
      expect(inUVT(r.taxableIncome), closeTo(3000 - 1200 - 288, 1e-6));
    });

    test("each deduction stays within its own cap", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 20000 * uvt,
        housingInterest: 5000 * uvt,
        prepaidHealth: 500 * uvt,
        voluntaryPension: 9000 * uvt,
        electronicInvoicePurchases: 50000 * uvt,
      ));
      expect(inUVT(r.housingInterest), closeTo(housingInterestCapUVT, 1e-6));
      expect(inUVT(r.prepaidHealth), closeTo(prepaidHealthCapUVT, 1e-6));
      // 30% of 20000 is 6000, above 3800
      expect(inUVT(r.voluntaryPension), closeTo(voluntaryPensionCapUVT, 1e-6));
      expect(inUVT(r.electronicInvoice), closeTo(electronicInvoiceCapUVT, 1e-6));

      IncomeTaxResult small = computeIncomeTax(IncomeTaxInput(
          uvt: uvt, laborIncome: 2000 * uvt, voluntaryPension: 1000 * uvt));
      expect(inUVT(small.voluntaryPension), closeTo(600, 1e-6));
    });

    test("withholdings above the tax leave a balance in favor", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 3000 * uvt,
        withholdings: 500 * uvt,
      ));
      // 3000 - 750 exempt = 2250 UVT taxable
      expect(r.taxUVT, closeTo(550 * 0.28 + 116, 1e-6));
      expect(r.balance, lessThan(0));
      expect(r.balance, closeTo(r.tax - 500 * uvt, 1e-6));
    });

    test("nothing goes negative", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 100 * uvt,
        mandatoryContributions: 500 * uvt,
        dependents: 4,
      ));
      expect(r.netIncome, 0);
      expect(r.taxableIncome, 0);
      expect(r.tax, 0);
    });
  });

  group("independent worker", () {
    test("contributions on 40% of the income, health and pension in full", () {
      expect(independentMandatoryContributionRate, closeTo(0.114, 1e-9));
      expect(mandatoryContributionRate(IncomeTaxWorkerKind.employee),
          employeeMandatoryContributionRate);
    });

    test("with the 25% exempt it works like an employee", () {
      IncomeTaxInput independent = IncomeTaxInput(
        uvt: uvt,
        kind: IncomeTaxWorkerKind.independent,
        laborIncome: 3000 * uvt,
        mandatoryContributions: 3000 * uvt * 0.114,
        costs: 900 * uvt, // ignored without deductCosts
      );
      IncomeTaxResult r = computeIncomeTax(independent);
      IncomeTaxResult employee = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 3000 * uvt,
        mandatoryContributions: 3000 * uvt * 0.114,
      ));
      expect(r.costs, 0);
      expect(r.taxableIncome, closeTo(employee.taxableIncome, 1e-6));
      // 3000 - 342 = 2658, 25% = 664.5
      expect(inUVT(r.laborExempt), closeTo(664.5, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(2658 - 664.5, 1e-6));
    });

    test("real costs and the 25% exempt never go together", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        kind: IncomeTaxWorkerKind.independent,
        deductCosts: true,
        laborIncome: 3000 * uvt,
        mandatoryContributions: 342 * uvt,
        costs: 900 * uvt,
        prepaidHealth: 100 * uvt,
        dependents: 1,
      ));
      expect(r.laborExempt, 0);
      expect(inUVT(r.costs), closeTo(900, 1e-6));
      expect(inUVT(r.netIncome), closeTo(3000 - 342 - 900, 1e-6));
      // The 40% is taken before costs: 40% of 2658
      expect(inUVT(r.cap), closeTo(2658 * 0.4, 1e-6));
      expect(inUVT(r.allowedWithinCap), closeTo(100, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(1758 - 100 - 72, 1e-6));
      expect(r.taxUVT, closeTo((1586 - 1090) * 0.19, 1e-6));
    });

    test("costs can't go below zero income", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        kind: IncomeTaxWorkerKind.independent,
        deductCosts: true,
        laborIncome: 1000 * uvt,
        costs: 5000 * uvt,
        dependents: 2,
      ));
      expect(inUVT(r.costs), closeTo(1000, 1e-6));
      expect(r.dependents, 0);
      expect(r.taxableIncome, 0);
    });

    test("an employee can't take real costs", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        deductCosts: true,
        laborIncome: 3000 * uvt,
        costs: 900 * uvt,
      ));
      expect(r.costs, 0);
      expect(inUVT(r.laborExempt), closeTo(750, 1e-6));
    });

    test("comparing both options", () {
      IncomeTaxInput lowCosts = IncomeTaxInput(
        uvt: uvt,
        kind: IncomeTaxWorkerKind.independent,
        laborIncome: 3000 * uvt,
        costs: 300 * uvt,
      );
      IncomeTaxResult exempt = computeIncomeTax(lowCosts);
      IncomeTaxResult withCosts = computeOtherIndependentOption(lowCosts);
      // 750 exempt beats 300 of costs
      expect(exempt.tax, lessThan(withCosts.tax));
      IncomeTaxInput highCosts = IncomeTaxInput(
        uvt: uvt,
        kind: IncomeTaxWorkerKind.independent,
        deductCosts: true,
        laborIncome: 3000 * uvt,
        costs: 1500 * uvt,
      );
      expect(computeIncomeTax(highCosts).tax,
          lessThan(computeOtherIndependentOption(highCosts).tax));
    });
  });

  group("other income and brackets", () {
    test("other income gets no 25% exempt but counts for the 40%", () {
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: 2000 * uvt,
        otherIncome: 1000 * uvt,
      ));
      expect(inUVT(r.grossIncome), closeTo(3000, 1e-6));
      expect(inUVT(r.laborExempt), closeTo(500, 1e-6));
      expect(inUVT(r.cap), closeTo(1200, 1e-6));
      expect(inUVT(r.taxableIncome), closeTo(2500, 1e-6));
    });

    test("bracket, effective rate and distance to the next bracket", () {
      expect(incomeTaxBracketIndex(0), 0);
      expect(incomeTaxBracketIndex(1090), 0);
      expect(incomeTaxBracketIndex(1091), 1);
      expect(incomeTaxBracketIndex(50000), incomeTaxBrackets.length - 1);
      IncomeTaxResult r = computeIncomeTax(
          IncomeTaxInput(uvt: uvt, laborIncome: 2000 * uvt));
      // 1500 UVT taxable
      expect(r.bracket.rate, 0.19);
      expect(r.uvtToNextBracket, closeTo(200, 1e-6));
      expect(r.effectiveRate, closeTo(r.tax / (2000 * uvt), 1e-12));
      IncomeTaxResult top = computeIncomeTax(
          IncomeTaxInput(uvt: uvt, laborIncome: 100000 * uvt));
      expect(top.uvtToNextBracket, null);
      expect(computeIncomeTax(IncomeTaxInput(uvt: uvt)).effectiveRate, 0);
    });

    test("example case: 8 million a month, one dependent", () {
      double salary = 8000000.0 * 12;
      IncomeTaxResult r = computeIncomeTax(IncomeTaxInput(
        uvt: uvt,
        laborIncome: salary,
        mandatoryContributions: salary * employeeMandatoryContributionRate,
        dependents: 1,
        prepaidHealth: 250000.0 * 12,
        electronicInvoicePurchases: 4000000.0 * 12 * 0.4,
        withholdings: 600000,
      ));
      FilingChecks checks = FilingChecks(
          FilingValues(grossIncome: salary, deposits: salary), uvt);
      expect(checks.mustFile, true);
      expect(r.capBinds, false);
      expect(r.bracket.rate, 0.19);
      expect(r.tax, greaterThan(r.withholdings));
    });
  });

  group("filing", () {
    test("gross income obliges from 1400 UVT, the rest above the limit", () {
      FilingChecks atLimit = FilingChecks(
        FilingValues(
          grossIncome: filingGrossIncomeUVT * uvt,
          purchases: filingPurchasesUVT * uvt,
          creditCard: filingCreditCardUVT * uvt,
          deposits: filingDepositsUVT * uvt,
          grossEquity: filingGrossEquityUVT * uvt,
        ),
        uvt,
      );
      expect(atLimit.grossIncome.obliges, true);
      expect(atLimit.purchases.obliges, false);
      expect(atLimit.creditCard.obliges, false);
      expect(atLimit.deposits.obliges, false);
      expect(atLimit.grossEquity.obliges, false);
      expect(atLimit.mustFile, true);
    });

    test("all below the limits, no need to file", () {
      FilingChecks checks = FilingChecks(
        FilingValues(grossIncome: 1000 * uvt, grossEquity: 4000 * uvt),
        uvt,
      );
      expect(checks.mustFile, false);
      expect(checks.grossEquity.valueUVT, closeTo(4000, 1e-6));
      expect(checks.grossEquity.threshold, filingGrossEquityUVT * uvt);
    });

    test("any one figure is enough", () {
      FilingChecks checks = FilingChecks(
          FilingValues(creditCard: (filingCreditCardUVT + 1) * uvt), uvt);
      expect(checks.mustFile, true);
    });
  });

  group("amounts", () {
    test("parses Colombian and plain numbers", () {
      expect(parseTaxAmount("1.500.000"), 1500000);
      expect(parseTaxAmount("1.500.000,50"), 1500000.5);
      expect(parseTaxAmount("1500000"), 1500000);
      expect(parseTaxAmount("1500,5"), 1500.5);
      expect(parseTaxAmount("1.500"), 1500);
      expect(parseTaxAmount("1.5"), 1.5);
      expect(parseTaxAmount("\$ 2.000.000"), 2000000);
      expect(parseTaxAmount(""), 0);
      expect(parseTaxAmount("abc"), 0);
    });

    test("formats with dots and a decimal comma", () {
      expect(formatTaxNumber(1500000), "1.500.000");
      expect(formatTaxNumber(1234.5, decimals: 1), "1.234,5");
      expect(formatTaxNumber(1400, decimals: 1), "1.400");
      expect(formatTaxNumber(0), "0");
      expect(formatTaxNumber(-1500), "-1.500");
      expect(parseTaxAmount(formatTaxNumber(987654321)), 987654321);
    });
  });
}
