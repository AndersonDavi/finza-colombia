import 'package:budget/colors.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// PILA math --------------------------------------------------------------------

// The contribution base can't go over 25 minimum wages, Ley 797 de 2003 art. 5
const double contributionBaseMaxWages = 25;

// PILA rounds each contribution up to the next 100 pesos
double roundUpToHundred(double value) => (value / 100).ceilToDouble() * 100;

class PilaResult {
  const PilaResult({
    required this.contributionBase,
    required this.health,
    required this.pension,
    required this.arl,
    required this.belowMinimumWage,
    required this.cappedAtMaximum,
    required this.income,
  });
  final double contributionBase;
  final double health;
  final double pension;
  final double arl;
  final bool belowMinimumWage;
  final bool cappedAtMaximum;
  final double income;

  double get total => health + pension + arl;
  // Share of the gross income that goes to contributions
  double get shareOfIncome => income <= 0 ? 0 : total / income;
}

// arlClass is 1 to 5, or null without ARL
PilaResult calculatePila({
  required double income,
  int? arlClass,
  required int year,
}) {
  double minimumWage = colombiaYear(year).minimumWage;
  double base = income * independentBaseRate;
  bool cappedAtMaximum = base > contributionBaseMaxWages * minimumWage;
  if (base < minimumWage) base = minimumWage;
  if (cappedAtMaximum) base = contributionBaseMaxWages * minimumWage;
  base = base.ceilToDouble();
  double arlRate = arlClass == null ? 0 : arlRates[arlClass - 1];
  return PilaResult(
    contributionBase: base,
    health: roundUpToHundred(base * healthRate),
    pension: roundUpToHundred(base * pensionRate),
    arl: arlRate == 0 ? 0 : roundUpToHundred(base * arlRate),
    belowMinimumWage: income < minimumWage,
    cappedAtMaximum: cappedAtMaximum,
    income: income,
  );
}

// Page -------------------------------------------------------------------------

class PilaCalculatorPage extends StatefulWidget {
  const PilaCalculatorPage({super.key});

  @override
  State<PilaCalculatorPage> createState() => _PilaCalculatorPageState();
}

class _PilaCalculatorPageState extends State<PilaCalculatorPage> {
  static const List<String> riskClassNames = ["I", "II", "III", "IV", "V"];

  final TextEditingController incomeController = TextEditingController();
  // 0 is no ARL, 1 to 5 the risk class
  int arlClass = 1;

  @override
  void dispose() {
    incomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int year = DateTime.now().year;
    ColombiaYear figures = colombiaYear(year);
    double? income = parseToolNumber(incomeController.text);
    PilaResult? result = income == null || income <= 0
        ? null
        : calculatePila(
            income: income,
            arlClass: arlClass == 0 ? null : arlClass,
            year: year,
          );

    return PageFramework(
      title: "tools-pila-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      getExtraHorizontalPadding: (_) => 13,
      listWidgets: [
        ToolInputField(
          label: "tools-pila-income".tr(),
          hint: toolNumberToInput(figures.minimumWage * 3),
          prefix: "\$ ",
          controller: incomeController,
          onChanged: (_) => setState(() {}),
        ),
        ToolSectionTitle(text: "tools-pila-arl-class".tr()),
        SelectChips<int>(
          items: [0, 1, 2, 3, 4, 5],
          allowMultipleSelected: false,
          wrapped: true,
          padding: EdgeInsetsDirectional.zero,
          getLabel: (int item) => item == 0
              ? "tools-pila-no-arl".tr()
              : "tools-pila-risk-class"
                      .tr(namedArgs: {"class": riskClassNames[item - 1]}) +
                  " (" +
                  formatToolPercent(arlRates[item - 1], decimals: 3) +
                  ")",
          getSelected: (int item) => arlClass == item,
          onSelected: (int item) => setState(() => arlClass = item),
        ),
        if (result == null)
          ToolNote(text: "tools-pila-fill-in".tr())
        else ...[
          ToolSectionTitle(text: "tools-results".tr()),
          if (result.belowMinimumWage)
            ToolNote(
              text: "tools-pila-below-minimum".tr(namedArgs: {
                "amount": formatToolMoney(context, figures.minimumWage),
              }),
              color: getColor(context, "warningOrange"),
            ),
          ToolResultRow(
            label: "tools-pila-base".tr(),
            value: formatToolMoney(context, result.contributionBase),
            description: result.cappedAtMaximum
                ? "tools-pila-base-capped".tr()
                : "tools-pila-base-description".tr(namedArgs: {
                    "rate": formatToolPercent(independentBaseRate),
                  }),
          ),
          ToolResultRow(
            label: "tools-pila-health".tr(),
            value: formatToolMoney(context, result.health),
            description: formatToolPercent(healthRate),
          ),
          ToolResultRow(
            label: "tools-pila-pension".tr(),
            value: formatToolMoney(context, result.pension),
            description: formatToolPercent(pensionRate),
          ),
          if (arlClass != 0)
            ToolResultRow(
              label: "tools-pila-arl".tr(),
              value: formatToolMoney(context, result.arl),
              description: "tools-pila-risk-class".tr(
                      namedArgs: {"class": riskClassNames[arlClass - 1]}) +
                  ", " +
                  formatToolPercent(arlRates[arlClass - 1], decimals: 3),
            ),
          ToolResultRow(
            label: "tools-pila-total".tr(),
            value: formatToolMoney(context, result.total),
            description: "tools-pila-share-of-income".tr(namedArgs: {
              "percent": formatToolPercent(result.shareOfIncome),
            }),
            highlight: true,
          ),
          ToolNote(text: "tools-pila-note".tr()),
        ],
      ],
    );
  }
}
