import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// CDT math ---------------------------------------------------------------------

enum CdtInterestPayment { atMaturity, monthly }

// The effective rate for a term, from an effective annual rate
double effectiveRateForDays(double annualRate, double days) {
  return pow(1 + annualRate, days / 365).toDouble() - 1;
}

class CdtResult {
  const CdtResult({
    required this.grossInterest,
    required this.withholding,
    required this.netInterest,
    required this.finalAmount,
    required this.netAnnualRate,
    this.realReturn,
  });
  final double grossInterest;
  final double withholding;
  final double netInterest;
  // Capital plus net interest
  final double finalAmount;
  final double netAnnualRate;
  // Net annual rate after inflation, when inflation is known
  final double? realReturn;

  bool? get beatsInflation => realReturn == null ? null : realReturn! > 0;
}

// Rates are fractions: 0.11 for 11% EA. Monthly payments are 30 day periods,
// paid out and not reinvested
CdtResult? simulateCdt({
  required double amount,
  required double annualRate,
  required double days,
  CdtInterestPayment payment = CdtInterestPayment.atMaturity,
  double withholdingRate = cdtWithholdingRate,
  double? inflation,
}) {
  if (amount <= 0 || days <= 0 || annualRate <= -1) return null;
  double grossInterest;
  double netAnnualRate;
  if (payment == CdtInterestPayment.monthly) {
    double monthlyRate = effectiveRateForDays(annualRate, 30);
    grossInterest = amount * monthlyRate * days / 30;
    double netMonthlyRate = monthlyRate * (1 - withholdingRate);
    netAnnualRate = pow(1 + netMonthlyRate, 365 / 30).toDouble() - 1;
  } else {
    grossInterest = amount * effectiveRateForDays(annualRate, days);
    double netTermRate = grossInterest * (1 - withholdingRate) / amount;
    netAnnualRate = pow(1 + netTermRate, 365 / days).toDouble() - 1;
  }
  double withholding = grossInterest * withholdingRate;
  double netInterest = grossInterest - withholding;
  double? realReturn;
  if (inflation != null && inflation > -1) {
    realReturn = (1 + netAnnualRate) / (1 + inflation) - 1;
  }
  return CdtResult(
    grossInterest: grossInterest,
    withholding: withholding,
    netInterest: netInterest,
    finalAmount: amount + netInterest,
    netAnnualRate: netAnnualRate,
    realReturn: realReturn,
  );
}

// Page -------------------------------------------------------------------------

class CdtSimulatorPage extends StatefulWidget {
  const CdtSimulatorPage({super.key});

  @override
  State<CdtSimulatorPage> createState() => _CdtSimulatorPageState();
}

class _CdtSimulatorPageState extends State<CdtSimulatorPage> {
  static const List<int> dayPresets = [90, 180, 360, 540];

  final TextEditingController amountController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController daysController =
      TextEditingController(text: "360");
  final TextEditingController inflationController = TextEditingController();
  late final TextEditingController withholdingController =
      TextEditingController(text: toolNumberToInput(cdtWithholdingRate * 100));
  CdtInterestPayment payment = CdtInterestPayment.atMaturity;

  @override
  void dispose() {
    amountController.dispose();
    rateController.dispose();
    daysController.dispose();
    inflationController.dispose();
    withholdingController.dispose();
    super.dispose();
  }

  void refresh(_) => setState(() {});

  @override
  Widget build(BuildContext context) {
    double? amount = parseToolNumber(amountController.text);
    double? rate = parseToolNumber(rateController.text);
    double? days = parseToolNumber(daysController.text);
    double? inflation = parseToolNumber(inflationController.text);
    double withholding =
        parseToolNumber(withholdingController.text) ?? cdtWithholdingRate * 100;
    CdtResult? result = amount == null || rate == null || days == null
        ? null
        : simulateCdt(
            amount: amount,
            annualRate: rate / 100,
            days: days,
            payment: payment,
            withholdingRate: withholding / 100,
            inflation: inflation == null ? null : inflation / 100,
          );

    return PageFramework(
      title: "tools-cdt-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      getExtraHorizontalPadding: (_) => 13,
      listWidgets: [
        ToolInputField(
          label: "tools-cdt-amount".tr(),
          hint: "1.000.000",
          prefix: "\$ ",
          controller: amountController,
          onChanged: refresh,
        ),
        ToolInputField(
          label: "tools-cdt-rate".tr(),
          hint: "10,5",
          suffix: "% EA",
          controller: rateController,
          onChanged: refresh,
        ),
        ToolInputField(
          label: "tools-cdt-term-days".tr(),
          suffix: "tools-days".tr(),
          controller: daysController,
          onChanged: refresh,
        ),
        SelectChips<int>(
          items: dayPresets,
          allowMultipleSelected: false,
          wrapped: true,
          padding: EdgeInsetsDirectional.zero,
          getLabel: (int item) => item.toString() + " " + "tools-days".tr(),
          getSelected: (int item) => days == item.toDouble(),
          onSelected: (int item) {
            daysController.text = item.toString();
            setState(() {});
          },
        ),
        ToolSectionTitle(text: "tools-cdt-interest-payment".tr()),
        SelectChips<CdtInterestPayment>(
          items: CdtInterestPayment.values,
          allowMultipleSelected: false,
          wrapped: true,
          padding: EdgeInsetsDirectional.zero,
          getLabel: (CdtInterestPayment item) =>
              item == CdtInterestPayment.monthly
                  ? "tools-cdt-payment-monthly".tr()
                  : "tools-cdt-payment-at-maturity".tr(),
          getSelected: (CdtInterestPayment item) => payment == item,
          onSelected: (CdtInterestPayment item) {
            setState(() {
              payment = item;
            });
          },
        ),
        SizedBox(height: 12),
        ToolInputField(
          label: "tools-cdt-inflation".tr(),
          hint: "tools-cdt-inflation-hint".tr(),
          suffix: "% EA",
          controller: inflationController,
          onChanged: refresh,
        ),
        ToolInputField(
          label: "tools-cdt-withholding".tr(),
          suffix: "%",
          controller: withholdingController,
          onChanged: refresh,
        ),
        if (result == null)
          ToolNote(text: "tools-cdt-fill-in".tr())
        else ...[
          ToolSectionTitle(text: "tools-results".tr()),
          ToolResultRow(
            label: "tools-cdt-gross-interest".tr(),
            value: formatToolMoney(context, result.grossInterest),
          ),
          ToolResultRow(
            label: "tools-cdt-withholding-amount".tr(),
            value: "-" + formatToolMoney(context, result.withholding),
          ),
          ToolResultRow(
            label: "tools-cdt-net-interest".tr(),
            value: formatToolMoney(context, result.netInterest),
            description: payment == CdtInterestPayment.monthly
                ? "tools-cdt-monthly-description".tr(namedArgs: {
                    "amount": formatToolMoney(
                        context, result.netInterest * 30 / days!),
                  })
                : null,
          ),
          ToolResultRow(
            label: "tools-cdt-final-amount".tr(),
            value: formatToolMoney(context, result.finalAmount),
            highlight: true,
          ),
          ToolResultRow(
            label: "tools-cdt-net-rate".tr(),
            value: formatToolPercent(result.netAnnualRate) + " EA",
          ),
          if (result.realReturn != null)
            ToolResultRow(
              label: "tools-cdt-real-return".tr(),
              value: formatToolPercent(result.realReturn!) + " EA",
            ),
          if (result.beatsInflation != null)
            ToolNote(
              text: result.beatsInflation!
                  ? "tools-cdt-beats-inflation".tr()
                  : "tools-cdt-loses-to-inflation".tr(),
              color: result.beatsInflation!
                  ? getColor(context, "incomeAmount")
                  : getColor(context, "expenseAmount"),
            ),
        ],
      ],
    );
  }
}
