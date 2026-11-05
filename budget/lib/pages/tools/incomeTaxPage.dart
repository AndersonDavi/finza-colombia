import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/incomeTaxData.dart';
import 'package:budget/pages/tools/incomeTaxMath.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Declaración de renta of personas naturales residentes: whether the year
// has to be filed, from the app's data, and an estimate of the tax. Every
// figure can be corrected since the app may not have everything.

class IncomeTaxPage extends StatefulWidget {
  const IncomeTaxPage({super.key});

  @override
  State<IncomeTaxPage> createState() => _IncomeTaxPageState();
}

class _IncomeTaxPageState extends State<IncomeTaxPage> {
  // What is filed now is the year before
  int year = DateTime.now().year - 1;
  bool loading = true;
  bool started = false;

  final grossIncome = TextEditingController();
  final purchases = TextEditingController();
  final creditCard = TextEditingController();
  final deposits = TextEditingController();
  final grossEquity = TextEditingController();

  final laborIncome = TextEditingController();
  final contributions = TextEditingController();
  final housingInterest = TextEditingController();
  final prepaidHealth = TextEditingController();
  final voluntaryPension = TextEditingController();
  final invoicePurchases = TextEditingController();
  final withholdings = TextEditingController();
  int dependents = 0;

  // Until edited, labor income follows gross income and the contributions
  // follow labor income
  bool laborEdited = false;
  bool contributionsEdited = false;

  List<TextEditingController> get controllers => [
        grossIncome,
        purchases,
        creditCard,
        deposits,
        grossEquity,
        laborIncome,
        contributions,
        housingInterest,
        prepaidHealth,
        voluntaryPension,
        invoicePurchases,
        withholdings,
      ];

  @override
  void dispose() {
    for (TextEditingController c in controllers) c.dispose();
    super.dispose();
  }

  List<int> get years {
    int now = DateTime.now().year;
    return {...colombiaYears.keys, now - 1}.where((y) => y <= now).toList()
      ..sort();
  }

  double uvt() => colombiaYear(year).uvt;

  Future<void> load(AllWallets allWallets) async {
    setState(() => loading = true);
    int loadingYear = year;
    IncomeTaxData data = await database.getIncomeTaxData(year, allWallets);
    if (!mounted || loadingYear != year) return;
    setState(() {
      setAmount(grossIncome, data.filing.grossIncome);
      setAmount(purchases, data.filing.purchases);
      setAmount(creditCard, data.filing.creditCard);
      setAmount(deposits, data.filing.deposits);
      setAmount(grossEquity, data.filing.grossEquity);
      setAmount(invoicePurchases, data.electronicInvoicePurchases);
      laborEdited = false;
      contributionsEdited = false;
      setAmount(laborIncome, data.filing.grossIncome);
      followLaborIncome();
      loading = false;
    });
  }

  void setAmount(TextEditingController controller, double value) {
    controller.text = formatTaxNumber(value.roundToDouble());
  }

  double amountOf(TextEditingController controller) =>
      parseTaxAmount(controller.text);

  void followLaborIncome() {
    if (contributionsEdited) return;
    setAmount(contributions,
        amountOf(laborIncome) * employeeMandatoryContributionRate);
  }

  void changeYear(int newYear) {
    if (newYear == year) return;
    year = newYear;
    load(Provider.of<AllWallets>(context, listen: false));
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    if (!started) {
      started = true;
      Future.microtask(() => load(allWallets));
    }
    String money(double amount) =>
        convertToMoney(allWallets, amount.roundToDouble());
    ColombiaYear uvtYear = colombiaYear(year);

    FilingChecks checks = FilingChecks(
      FilingValues(
        grossIncome: amountOf(grossIncome),
        purchases: amountOf(purchases),
        creditCard: amountOf(creditCard),
        deposits: amountOf(deposits),
        grossEquity: amountOf(grossEquity),
      ),
      uvtYear.uvt,
    );
    IncomeTaxResult result = computeIncomeTax(IncomeTaxInput(
      uvt: uvtYear.uvt,
      laborIncome: amountOf(laborIncome),
      mandatoryContributions: amountOf(contributions),
      dependents: dependents,
      housingInterest: amountOf(housingInterest),
      prepaidHealth: amountOf(prepaidHealth),
      voluntaryPension: amountOf(voluntaryPension),
      electronicInvoicePurchases: amountOf(invoicePurchases),
      withholdings: amountOf(withholdings),
    ));

    Widget filingField(
        String labelKey, TextEditingController controller, FilingCheck check,
        {ValueChanged<String>? onChanged}) {
      return _TaxCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  check.obliges
                      ? Icons.error_rounded
                      : Icons.check_circle_rounded,
                  color: check.obliges
                      ? getColor(context, "expenseAmount")
                      : getColor(context, "incomeAmount"),
                  size: 22,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: TextFont(
                    text: labelKey.tr(),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            _AmountInput(
              controller: controller,
              onChanged: (text) {
                onChanged?.call(text);
                setState(() {});
              },
            ),
            SizedBox(height: 6),
            TextFont(
              text: "tax-threshold-line".tr(namedArgs: {
                "uvt": formatTaxNumber(check.valueUVT, decimals: 1),
                "limitUvt": formatTaxNumber(check.thresholdUVT),
                "limit": money(check.threshold),
              }),
              fontSize: 13,
              maxLines: 3,
              textColor: getColor(context, "textLight"),
            ),
          ],
        ),
      );
    }

    Widget estimateField(String labelKey, TextEditingController controller,
        {String? hint, ValueChanged<String>? onChanged}) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 5),
              child: TextFont(
                text: labelKey.tr(),
                fontSize: 15,
                fontWeight: FontWeight.bold,
                maxLines: 2,
              ),
            ),
            _AmountInput(
              controller: controller,
              onChanged: (text) {
                onChanged?.call(text);
                setState(() {});
              },
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
                child: TextFont(
                  text: hint,
                  fontSize: 13,
                  maxLines: 3,
                  textColor: getColor(context, "textLight"),
                ),
              ),
          ],
        ),
      );
    }

    String pct(double rate) => formatTaxNumber(rate * 100);
    String uvtOf(double amount) =>
        formatTaxNumber(uvtYear.uvt == 0 ? 0 : amount / uvtYear.uvt,
                decimals: 1) +
            " UVT";
    bool toPay = result.balance >= 0;

    return PageFramework(
      title: "tax-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      resizeToAvoidBottomInset: true,
      getExtraHorizontalPadding: (_) => 13,
      listWidgets: [
        _TaxCard(
          color: getColor(context, "warningOrange").withValues(alpha: 0.15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: getColor(context, "warningOrange")),
              SizedBox(width: 10),
              Expanded(
                child: TextFont(
                  text: "tax-disclaimer".tr(),
                  fontSize: 14,
                  maxLines: 10,
                ),
              ),
            ],
          ),
        ),
        _SectionTitle("tax-taxable-year".tr()),
        SelectChips<int>(
          items: years,
          allowMultipleSelected: false,
          getSelected: (y) => y == year,
          onSelected: changeYear,
          getLabel: (y) => y.toString(),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, top: 6),
          child: TextFont(
            text: uvtYear.year == year
                ? "tax-uvt-of-year".tr(namedArgs: {
                    "year": year.toString(),
                    "uvt": money(uvtYear.uvt),
                  })
                : "tax-uvt-missing".tr(namedArgs: {
                    "year": year.toString(),
                    "used": uvtYear.year.toString(),
                    "uvt": money(uvtYear.uvt),
                  }),
            fontSize: 14,
            maxLines: 3,
            textColor: uvtYear.year == year
                ? getColor(context, "textLight")
                : getColor(context, "warningOrange"),
          ),
        ),
        _SectionTitle("tax-must-file-question".tr()),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: TextFont(
            text: "tax-from-your-data".tr(),
            fontSize: 14,
            maxLines: 4,
            textColor: getColor(context, "textLight"),
          ),
        ),
        if (loading)
          Padding(
            padding: const EdgeInsetsDirectional.all(20),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          filingField("tax-gross-income", grossIncome, checks.grossIncome,
              onChanged: (text) {
            if (laborEdited) return;
            laborIncome.text = text;
            followLaborIncome();
          }),
          filingField("tax-purchases", purchases, checks.purchases),
          filingField("tax-credit-card", creditCard, checks.creditCard),
          filingField("tax-deposits", deposits, checks.deposits),
          filingField("tax-gross-equity", grossEquity, checks.grossEquity),
          _TaxCard(
            color: (checks.mustFile
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"))
                .withValues(alpha: 0.18),
            child: Row(
              children: [
                Icon(
                  checks.mustFile
                      ? Icons.assignment_late_rounded
                      : Icons.verified_rounded,
                  color: checks.mustFile
                      ? getColor(context, "expenseAmount")
                      : getColor(context, "incomeAmount"),
                  size: 28,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextFont(
                    text: (checks.mustFile
                            ? "tax-must-file"
                            : "tax-no-need-to-file")
                        .tr(namedArgs: {"year": year.toString()}),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 4,
                  ),
                ),
              ],
            ),
          ),
          _SectionTitle("tax-estimate".tr()),
          estimateField("tax-labor-income", laborIncome, onChanged: (_) {
            laborEdited = true;
            followLaborIncome();
          }),
          estimateField(
            "tax-mandatory-contributions",
            contributions,
            hint: "tax-mandatory-contributions-hint".tr(namedArgs: {
              "rate": pct(employeeMandatoryContributionRate),
            }),
            onChanged: (_) => contributionsEdited = true,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 5),
            child: TextFont(
              text: "tax-dependents".tr(),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SelectChips<int>(
            items: List.generate(dependentDeductionMax + 1, (i) => i),
            allowMultipleSelected: false,
            getSelected: (n) => n == dependents,
            onSelected: (n) => setState(() => dependents = n),
            getLabel: (n) => n.toString(),
          ),
          SizedBox(height: 12),
          estimateField("tax-housing-interest", housingInterest),
          estimateField("tax-prepaid-health", prepaidHealth),
          estimateField("tax-voluntary-pension", voluntaryPension),
          estimateField(
            "tax-electronic-invoice-purchases",
            invoicePurchases,
            hint: "tax-electronic-invoice-hint".tr(),
          ),
          estimateField("tax-withholdings", withholdings),
          _SectionTitle("tax-breakdown".tr()),
          _TaxCard(
            child: Column(
              children: [
                _BreakdownRow("tax-labor-income".tr(), money(result.grossIncome)),
                _BreakdownRow("tax-mandatory-contributions".tr(),
                    money(-result.mandatoryContributions)),
                _BreakdownRow("tax-net-income".tr(), money(result.netIncome),
                    bold: true),
                _BreakdownDivider(),
                _BreakdownRow(
                  "tax-labor-exempt".tr(namedArgs: {
                    "rate": pct(laborExemptRate),
                    "cap": formatTaxNumber(laborExemptCapUVT),
                  }),
                  money(result.laborExempt),
                ),
                _BreakdownRow(
                  "tax-housing-deduction".tr(namedArgs: {
                    "cap": formatTaxNumber(housingInterestCapUVT),
                  }),
                  money(result.housingInterest),
                ),
                _BreakdownRow(
                  "tax-prepaid-health-deduction".tr(namedArgs: {
                    "cap": formatTaxNumber(prepaidHealthCapUVT),
                  }),
                  money(result.prepaidHealth),
                ),
                _BreakdownRow(
                  "tax-voluntary-pension-exempt".tr(namedArgs: {
                    "rate": pct(voluntaryPensionRate),
                    "cap": formatTaxNumber(voluntaryPensionCapUVT),
                  }),
                  money(result.voluntaryPension),
                ),
                _BreakdownRow(
                    "tax-subject-to-cap".tr(), money(result.subjectToCap)),
                _BreakdownRow(
                  "tax-cap".tr(namedArgs: {
                    "rate": pct(exemptAndDeductionsCapRate),
                    "cap": formatTaxNumber(exemptAndDeductionsCapUVT),
                  }),
                  money(result.cap),
                ),
                _BreakdownRow(
                  "tax-allowed".tr(),
                  money(-result.allowedWithinCap),
                  bold: true,
                  note: result.capBinds
                      ? "tax-cap-binds".tr(namedArgs: {
                          "amount":
                              money(result.subjectToCap - result.cap),
                        })
                      : null,
                ),
                _BreakdownDivider(),
                _BreakdownRow(
                  "tax-dependents-deduction".tr(namedArgs: {
                    "count": dependents.toString(),
                    "uvt": formatTaxNumber(dependentDeductionUVT),
                  }),
                  money(-result.dependents),
                ),
                _BreakdownRow(
                  "tax-electronic-invoice-deduction".tr(namedArgs: {
                    "rate": pct(electronicInvoiceRate),
                    "cap": formatTaxNumber(electronicInvoiceCapUVT),
                  }),
                  money(-result.electronicInvoice),
                ),
                _BreakdownDivider(),
                _BreakdownRow(
                  "tax-taxable-income".tr(),
                  money(result.taxableIncome),
                  bold: true,
                  note: uvtOf(result.taxableIncome),
                ),
                _BreakdownRow(
                  "tax-income-tax".tr(),
                  money(result.tax),
                  bold: true,
                  note: formatTaxNumber(result.taxUVT, decimals: 1) + " UVT",
                ),
                _BreakdownRow(
                    "tax-withholdings".tr(), money(-result.withholdings)),
              ],
            ),
          ),
          _TaxCard(
            color: (toPay
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"))
                .withValues(alpha: 0.18),
            child: Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: (toPay ? "tax-balance-to-pay" : "tax-balance-in-favor")
                        .tr(),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 3,
                  ),
                ),
                SizedBox(width: 10),
                TextFont(
                  text: money(result.balance.abs()),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  textColor: toPay
                      ? getColor(context, "expenseAmount")
                      : getColor(context, "incomeAmount"),
                ),
              ],
            ),
          ),
          SizedBox(height: 30),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 22, bottom: 8),
      child: TextFont(
        text: text,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        maxLines: 2,
      ),
    );
  }
}

class _TaxCard extends StatelessWidget {
  const _TaxCard({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: color ?? getColor(context, "standardContainerColor"),
        borderRadius: BorderRadiusDirectional.circular(15),
      ),
      child: child,
    );
  }
}

// Takes "1.500.000" and decimal commas, see parseTaxAmount
class _AmountInput extends StatelessWidget {
  const _AmountInput({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextInput(
      labelText: "0",
      controller: controller,
      onChanged: onChanged,
      prefix: "\$ ",
      padding: EdgeInsetsDirectional.zero,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow(this.label, this.value, {this.bold = false, this.note});
  final String label;
  final String value;
  final bool bold;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                  text: label,
                  fontSize: 14,
                  maxLines: 3,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
                if (note != null)
                  TextFont(
                    text: note!,
                    fontSize: 12,
                    maxLines: 2,
                    textColor: getColor(context, "textLight"),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10),
          TextFont(
            text: value,
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ],
      ),
    );
  }
}

class _BreakdownDivider extends StatelessWidget {
  const _BreakdownDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 14, color: getColor(context, "dividerColor"));
  }
}
