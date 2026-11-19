import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/pages/tools/incomeTaxData.dart';
import 'package:budget/pages/tools/incomeTaxMath.dart';
import 'package:budget/pages/tools/incomeTaxWidgets.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/incomeExpenseTabSelector.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/helpGuide.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Declaración de renta of personas naturales residentes, cédula general.
// Two modes: prefilled from the app's data for the taxable year, or a blank
// calculator. Step 1 checks whether the year has to be filed, step 2
// estimates the tax. Everything is an educational estimate.

enum IncomeTaxMode { fromData, calculator }

// Example case: an employee with one dependent, prepaid health and some
// purchases with electronic invoice
const double _exampleMonthlySalary = 8000000;
const double _exampleMonthlyPrepaidHealth = 250000;
const double _exampleMonthlyPurchases = 4000000;
const double _exampleCreditCardShare = 0.4;
const double _exampleInvoiceShare = 0.4;
const double _exampleGrossEquity = 150000000;
const double _exampleWithholdings = 600000;

class IncomeTaxPage extends StatefulWidget {
  const IncomeTaxPage({super.key});

  @override
  State<IncomeTaxPage> createState() => _IncomeTaxPageState();
}

class _IncomeTaxPageState extends State<IncomeTaxPage> {
  // What is filed now is the year before
  int year = DateTime.now().year - 1;
  IncomeTaxMode mode = IncomeTaxMode.fromData;
  bool loading = true;
  bool started = false;

  final grossIncome = TextEditingController();
  final purchases = TextEditingController();
  final creditCard = TextEditingController();
  final deposits = TextEditingController();
  final grossEquity = TextEditingController();

  final laborIncome = TextEditingController();
  final contributions = TextEditingController();
  final costs = TextEditingController();
  final otherIncome = TextEditingController();
  final housingInterest = TextEditingController();
  final prepaidHealth = TextEditingController();
  final voluntaryPension = TextEditingController();
  final invoicePurchases = TextEditingController();
  final withholdings = TextEditingController();
  int dependents = 0;
  IncomeTaxWorkerKind kind = IncomeTaxWorkerKind.employee;
  bool deductCosts = false;

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
        costs,
        otherIncome,
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

  Future<void> load() async {
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    setState(() => loading = true);
    int loadingYear = year;
    IncomeTaxData data = await database.getIncomeTaxData(year, allWallets);
    if (!mounted || loadingYear != year || mode != IncomeTaxMode.fromData) {
      return;
    }
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
    controller.text = value <= 0 ? "" : formatTaxNumber(value.roundToDouble());
  }

  double amountOf(TextEditingController controller) =>
      parseToolNumber(controller.text) ?? 0;

  void followLaborIncome() {
    if (contributionsEdited) return;
    setAmount(
        contributions, amountOf(laborIncome) * mandatoryContributionRate(kind));
  }

  void clearAll() {
    for (TextEditingController c in controllers) c.clear();
    dependents = 0;
    kind = IncomeTaxWorkerKind.employee;
    deductCosts = false;
    laborEdited = false;
    contributionsEdited = false;
  }

  void changeMode(IncomeTaxMode newMode) {
    if (newMode == mode) return;
    setState(() {
      mode = newMode;
      clearAll();
      loading = false;
    });
    if (newMode == IncomeTaxMode.fromData) load();
  }

  void changeYear(int newYear) {
    if (newYear == year) return;
    setState(() => year = newYear);
    if (mode == IncomeTaxMode.fromData) load();
  }

  void changeKind(IncomeTaxWorkerKind newKind) {
    if (newKind == kind) return;
    setState(() {
      kind = newKind;
      followLaborIncome();
    });
  }

  // Typed by hand, every figure a year
  void fillExample() {
    setState(() {
      mode = IncomeTaxMode.calculator;
      loading = false;
      clearAll();
      double salary = _exampleMonthlySalary * 12;
      double spending = _exampleMonthlyPurchases * 12;
      setAmount(grossEquity, _exampleGrossEquity);
      setAmount(grossIncome, salary);
      setAmount(purchases, spending);
      setAmount(creditCard, spending * _exampleCreditCardShare);
      setAmount(deposits, salary);
      setAmount(laborIncome, salary);
      followLaborIncome();
      dependents = 1;
      setAmount(prepaidHealth, _exampleMonthlyPrepaidHealth * 12);
      setAmount(invoicePurchases, spending * _exampleInvoiceShare);
      setAmount(withholdings, _exampleWithholdings);
    });
  }

  IncomeTaxInput taxInput(double uvt) => IncomeTaxInput(
        uvt: uvt,
        kind: kind,
        deductCosts: deductCosts,
        costs: amountOf(costs),
        laborIncome: amountOf(laborIncome),
        otherIncome: amountOf(otherIncome),
        mandatoryContributions: amountOf(contributions),
        dependents: dependents,
        housingInterest: amountOf(housingInterest),
        prepaidHealth: amountOf(prepaidHealth),
        voluntaryPension: amountOf(voluntaryPension),
        electronicInvoicePurchases: amountOf(invoicePurchases),
        withholdings: amountOf(withholdings),
      );

  @override
  Widget build(BuildContext context) {
    if (livesInColombia() == false) {
      return _OutsideColombia(onBack: () => setState(() {}));
    }
    if (!started) {
      started = true;
      Future.microtask(load);
    }
    ColombiaYear uvtYear = colombiaYear(year);
    String money(double amount) => formatToolMoney(context, amount);
    String uvtOf(double amount) =>
        formatTaxNumber(uvtYear.uvt == 0 ? 0 : amount / uvtYear.uvt,
            decimals: 1) +
        " UVT";
    String pct(double rate) => formatTaxNumber(rate * 100, decimals: 1);
    bool independent = kind == IncomeTaxWorkerKind.independent;

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
    IncomeTaxInput input = taxInput(uvtYear.uvt);
    IncomeTaxResult result = computeIncomeTax(input);
    IncomeTaxResult? otherOption = independent && result.laborIncome > 0
        ? computeOtherIndependentOption(input)
        : null;
    bool hasIncome = result.grossIncome > 0;
    bool toPay = result.balance >= 0;

    Widget filingField(String labelKey, String helpKey,
        TextEditingController controller, FilingCheck check,
        {ValueChanged<String>? onChanged}) {
      return IncomeTaxFilingField(
        label: labelKey.tr(),
        help: helpKey.tr(namedArgs: {
          "year": year.toString(),
          "next": (year + 1).toString(),
        }),
        controller: controller,
        check: check,
        onChanged: (text) {
          onChanged?.call(text);
          setState(() {});
        },
      );
    }

    Widget amountField(
        String labelKey, String help, TextEditingController controller,
        {Widget? below, ValueChanged<String>? onChanged}) {
      return IncomeTaxAmountField(
        label: labelKey.tr(),
        help: help,
        controller: controller,
        below: below,
        onChanged: (text) {
          onChanged?.call(text);
          setState(() {});
        },
      );
    }

    Widget smallText(String text, {Color? color}) => TextFont(
          text: text,
          fontSize: 13,
          maxLines: 4,
          textColor: color ?? getColor(context, "textLight"),
        );

    Widget label(String text) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 5, bottom: 6),
          child: TextFont(
            text: text,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            maxLines: 3,
          ),
        );

    String figuresSource = "tax-figures-source".tr(namedArgs: {
      "year": year.toString(),
      "uvtYear": uvtYear.year.toString(),
      "uvt": money(uvtYear.uvt),
    });

    List<Widget> stepOne = [
      IncomeTaxStepHeader(number: 1, title: "tax-must-file-question".tr()),
      ToolNote(
        text: "tax-thresholds-intro".tr(namedArgs: {"year": year.toString()}),
      ),
      filingField("tax-gross-equity", "tax-help-gross-equity", grossEquity,
          checks.grossEquity),
      filingField("tax-gross-income", "tax-help-gross-income", grossIncome,
          checks.grossIncome, onChanged: (text) {
        if (laborEdited) return;
        laborIncome.text = text;
        followLaborIncome();
      }),
      filingField(
          "tax-purchases", "tax-help-purchases", purchases, checks.purchases),
      filingField("tax-credit-card", "tax-help-credit-card", creditCard,
          checks.creditCard),
      filingField(
          "tax-deposits", "tax-help-deposits", deposits, checks.deposits),
      IncomeTaxCard(
        color: (checks.mustFile
                ? getColor(context, "expenseAmount")
                : getColor(context, "incomeAmount"))
            .withOpacity(0.18),
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
                text:
                    (checks.mustFile ? "tax-must-file" : "tax-no-need-to-file")
                        .tr(namedArgs: {"year": year.toString()}),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                maxLines: 4,
              ),
            ),
          ],
        ),
      ),
    ];

    List<Widget> stepTwo = [
      IncomeTaxStepHeader(number: 2, title: "tax-how-much-question".tr()),
      label("tax-income-kind".tr()),
      IncomeExpenseTabSelector(
        onTabChanged: (isIndependent) => changeKind(isIndependent
            ? IncomeTaxWorkerKind.independent
            : IncomeTaxWorkerKind.employee),
        initialTabIsIncome: independent,
        syncWithInitial: true,
        showIcons: false,
        expenseLabel: "tax-employee".tr(),
        incomeLabel: "tax-independent".tr(),
        expenseCustomIcon: Icon(Icons.badge_outlined, size: 19),
        incomeCustomIcon: Icon(Icons.work_outline_rounded, size: 19),
      ),
      SizedBox(height: 14),
      amountField(
        independent ? "tax-independent-income" : "tax-labor-income",
        (independent ? "tax-help-independent-income" : "tax-help-labor-income")
            .tr(),
        laborIncome,
        below: amountOf(laborIncome) > 0
            ? smallText("tax-monthly-equivalent".tr(namedArgs: {
                "amount": money(amountOf(laborIncome) / 12),
              }))
            : null,
        onChanged: (_) {
          laborEdited = true;
          followLaborIncome();
        },
      ),
      amountField(
        "tax-mandatory-contributions",
        (independent
                ? "tax-help-contributions-independent"
                : "tax-help-contributions")
            .tr(),
        contributions,
        below: smallText("tax-mandatory-contributions-hint".tr(namedArgs: {
          "rate": pct(mandatoryContributionRate(kind)),
        })),
        onChanged: (_) => contributionsEdited = true,
      ),
      _ShowAnimated(
        show: independent,
        children: [
          label("tax-independent-option".tr()),
          SelectChips<bool>(
            items: [false, true],
            allowMultipleSelected: false,
            wrapped: true,
            padding: EdgeInsetsDirectional.zero,
            getSelected: (withCosts) => withCosts == deductCosts,
            onSelected: (withCosts) => setState(() => deductCosts = withCosts),
            getLabel: (withCosts) => withCosts
                ? "tax-option-costs".tr()
                : "tax-option-exempt".tr(namedArgs: {
                    "rate": pct(laborExemptRate),
                  }),
          ),
          SizedBox(height: 8),
          ToolNote(
            text: "tax-options-exclusive".tr(namedArgs: {
              "rate": pct(laborExemptRate),
              "cap": formatTaxNumber(laborExemptCapUVT),
            }),
          ),
          if (deductCosts)
            amountField("tax-costs", "tax-help-costs".tr(), costs),
          if (otherOption != null && otherOption.tax < result.tax - 1)
            ToolNote(
              text: "tax-better-option".tr(namedArgs: {
                "option":
                    (deductCosts ? "tax-option-exempt" : "tax-option-costs")
                        .tr(namedArgs: {"rate": pct(laborExemptRate)}),
                "amount": money(result.tax - otherOption.tax),
              }),
              color: getColor(context, "incomeAmount"),
            ),
        ],
      ),
      label("tax-dependents".tr()),
      SelectChips<int>(
        items: List.generate(dependentDeductionMax + 1, (i) => i),
        allowMultipleSelected: false,
        wrapped: true,
        padding: EdgeInsetsDirectional.zero,
        getSelected: (n) => n == dependents,
        onSelected: (n) => setState(() => dependents = n),
        getLabel: (n) => n.toString(),
      ),
      IncomeTaxHelp(
        text: "tax-help-dependents".tr(namedArgs: {
          "uvt": formatTaxNumber(dependentDeductionUVT),
          "max": dependentDeductionMax.toString(),
        }),
      ),
      SizedBox(height: 10),
      amountField(
        "tax-housing-interest",
        "tax-help-housing-interest".tr(namedArgs: {
          "cap": formatTaxNumber(housingInterestCapUVT),
        }),
        housingInterest,
      ),
      amountField(
        "tax-prepaid-health",
        "tax-help-prepaid-health".tr(namedArgs: {
          "cap": formatTaxNumber(prepaidHealthCapUVT),
        }),
        prepaidHealth,
      ),
      amountField(
        "tax-voluntary-pension",
        "tax-help-voluntary-pension".tr(namedArgs: {
          "rate": pct(voluntaryPensionRate),
          "cap": formatTaxNumber(voluntaryPensionCapUVT),
        }),
        voluntaryPension,
      ),
      amountField(
        "tax-electronic-invoice-purchases",
        "tax-help-electronic-invoice".tr(namedArgs: {
          "rate": pct(electronicInvoiceRate),
          "cap": formatTaxNumber(electronicInvoiceCapUVT),
        }),
        invoicePurchases,
        below: mode == IncomeTaxMode.fromData
            ? smallText("tax-electronic-invoice-hint".tr())
            : null,
      ),
      amountField(
        "tax-other-income",
        "tax-help-other-income".tr(namedArgs: {"rate": pct(laborExemptRate)}),
        otherIncome,
        below: smallText("tax-other-income-note".tr()),
      ),
      amountField(
        "tax-withholdings",
        "tax-help-withholdings".tr(),
        withholdings,
      ),
    ];

    List<Widget> results = [
      IncomeTaxStepHeader(number: 3, title: "tax-result".tr()),
      if (hasIncome == false)
        ToolNote(text: "tax-fill-in".tr())
      else ...[
        IncomeTaxDisclaimer(extra: figuresSource),
        ToolResultRow(
          label: "tax-taxable-income".tr(),
          value: money(result.taxableIncome),
          description: uvtOf(result.taxableIncome),
        ),
        ToolResultRow(
          label: "tax-income-tax".tr(),
          value: money(result.tax),
          description: "tax-table-241".tr(namedArgs: {
            "uvt": formatTaxNumber(result.taxUVT, decimals: 1),
          }),
        ),
        ToolResultRow(
          label: "tax-withholdings".tr(),
          value: money(-result.withholdings),
        ),
        AnimatedContainer(
          duration: Duration(milliseconds: 300),
          margin: const EdgeInsetsDirectional.only(bottom: 10),
          padding: const EdgeInsetsDirectional.all(16),
          decoration: BoxDecoration(
            color: (toPay
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"))
                .withOpacity(0.18),
            borderRadius: BorderRadiusDirectional.circular(15),
          ),
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
                fontSize: 21,
                fontWeight: FontWeight.bold,
                textColor: toPay
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "incomeAmount"),
              ),
            ],
          ),
        ),
        IncomeTaxBracketBar(result: result),
        ToolSectionTitle(text: "tax-breakdown".tr()),
        IncomeTaxCard(
          child: Column(
            children: [
              IncomeTaxBreakdownRow(
                  (independent ? "tax-independent-income" : "tax-labor-income")
                      .tr(),
                  money(result.laborIncome)),
              if (result.otherIncome > 0)
                IncomeTaxBreakdownRow(
                    "tax-other-income".tr(), money(result.otherIncome)),
              IncomeTaxBreakdownRow("tax-mandatory-contributions".tr(),
                  money(-result.mandatoryContributions)),
              if (result.costs > 0)
                IncomeTaxBreakdownRow("tax-costs".tr(), money(-result.costs)),
              IncomeTaxBreakdownRow(
                  "tax-net-income".tr(), money(result.netIncome),
                  bold: true),
              IncomeTaxBreakdownDivider(),
              IncomeTaxBreakdownRow(
                "tax-labor-exempt".tr(namedArgs: {
                  "rate": pct(laborExemptRate),
                  "cap": formatTaxNumber(laborExemptCapUVT),
                }),
                money(result.laborExempt),
                note: independent && deductCosts
                    ? "tax-labor-exempt-not-with-costs".tr()
                    : null,
              ),
              IncomeTaxBreakdownRow(
                "tax-housing-deduction".tr(namedArgs: {
                  "cap": formatTaxNumber(housingInterestCapUVT),
                }),
                money(result.housingInterest),
              ),
              IncomeTaxBreakdownRow(
                "tax-prepaid-health-deduction".tr(namedArgs: {
                  "cap": formatTaxNumber(prepaidHealthCapUVT),
                }),
                money(result.prepaidHealth),
              ),
              IncomeTaxBreakdownRow(
                "tax-voluntary-pension-exempt".tr(namedArgs: {
                  "rate": pct(voluntaryPensionRate),
                  "cap": formatTaxNumber(voluntaryPensionCapUVT),
                }),
                money(result.voluntaryPension),
              ),
              IncomeTaxBreakdownRow(
                  "tax-subject-to-cap".tr(), money(result.subjectToCap)),
              IncomeTaxBreakdownRow(
                "tax-cap".tr(namedArgs: {
                  "rate": pct(exemptAndDeductionsCapRate),
                  "cap": formatTaxNumber(exemptAndDeductionsCapUVT),
                }),
                money(result.cap),
              ),
              IncomeTaxBreakdownRow(
                "tax-allowed".tr(),
                money(-result.allowedWithinCap),
                bold: true,
                note: result.capBinds
                    ? "tax-cap-binds".tr(namedArgs: {
                        "amount": money(result.subjectToCap - result.cap),
                      })
                    : null,
              ),
              IncomeTaxBreakdownDivider(),
              IncomeTaxBreakdownRow(
                "tax-dependents-deduction".tr(namedArgs: {
                  "count": dependents.toString(),
                  "uvt": formatTaxNumber(dependentDeductionUVT),
                }),
                money(-result.dependents),
              ),
              IncomeTaxBreakdownRow(
                "tax-electronic-invoice-deduction".tr(namedArgs: {
                  "rate": pct(electronicInvoiceRate),
                  "cap": formatTaxNumber(electronicInvoiceCapUVT),
                }),
                money(-result.electronicInvoice),
              ),
              IncomeTaxBreakdownDivider(),
              IncomeTaxBreakdownRow(
                "tax-taxable-income".tr(),
                money(result.taxableIncome),
                bold: true,
                note: uvtOf(result.taxableIncome),
              ),
              IncomeTaxBreakdownRow(
                "tax-income-tax".tr(),
                money(result.tax),
                bold: true,
                note: formatTaxNumber(result.taxUVT, decimals: 1) + " UVT",
              ),
              IncomeTaxBreakdownRow(
                  "tax-withholdings".tr(), money(-result.withholdings)),
            ],
          ),
        ),
      ],
    ];

    return PageFramework(
      title: "tax-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      resizeToAvoidBottomInset: true,
      getExtraHorizontalPadding: (_) => 13,
      actions: [HelpGuideButton(guide: HelpGuides.incomeTax())],
      listWidgets: [
        IncomeTaxDisclaimer(),
        IncomeExpenseTabSelector(
          onTabChanged: (isCalculator) => changeMode(
              isCalculator ? IncomeTaxMode.calculator : IncomeTaxMode.fromData),
          initialTabIsIncome: mode == IncomeTaxMode.calculator,
          syncWithInitial: true,
          showIcons: false,
          expenseLabel: "tax-mode-from-data".tr(),
          incomeLabel: "tax-mode-calculator".tr(),
          expenseCustomIcon: Icon(Icons.receipt_long_rounded, size: 19),
          incomeCustomIcon: Icon(Icons.calculate_outlined, size: 19),
        ),
        SizedBox(height: 10),
        ToolNote(
          text: (mode == IncomeTaxMode.fromData
                  ? "tax-from-your-data"
                  : "tax-calculator-intro")
              .tr(),
        ),
        Row(
          children: [
            Expanded(
              child: Button(
                label: "tax-try-example".tr(),
                icon: Icons.auto_awesome_rounded,
                onTap: fillExample,
                flexibleLayout: true,
              ),
            ),
            if (mode == IncomeTaxMode.calculator) ...[
              SizedBox(width: 8),
              Button(
                label: "tax-clear".tr(),
                icon: Icons.restart_alt_rounded,
                onTap: () => setState(clearAll),
                color: getColor(context, "lightDarkAccent"),
                textColor: getColor(context, "black"),
                iconColor: getColor(context, "black"),
              ),
            ],
          ],
        ),
        ToolSectionTitle(text: "tax-taxable-year".tr()),
        SelectChips<int>(
          items: years,
          allowMultipleSelected: false,
          wrapped: true,
          padding: EdgeInsetsDirectional.zero,
          getSelected: (y) => y == year,
          onSelected: changeYear,
          getLabel: (y) => y.toString(),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 5, top: 6),
          child: smallText(
            uvtYear.year == year
                ? "tax-uvt-of-year".tr(namedArgs: {
                    "year": year.toString(),
                    "uvt": money(uvtYear.uvt),
                  })
                : "tax-uvt-missing".tr(namedArgs: {
                    "year": year.toString(),
                    "used": uvtYear.year.toString(),
                    "uvt": money(uvtYear.uvt),
                  }),
            color: uvtYear.year == year
                ? null
                : getColor(context, "warningOrange"),
          ),
        ),
        if (loading)
          Padding(
            padding: const EdgeInsetsDirectional.all(30),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          ...stepOne,
          ...stepTwo,
          ...results,
          SizedBox(height: 30),
        ],
      ],
    );
  }
}

// Shows the children with a size animation, nothing when hidden
class _ShowAnimated extends StatelessWidget {
  const _ShowAnimated({required this.show, required this.children});
  final bool show;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: show
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            )
          : SizedBox(width: double.infinity),
    );
  }
}

// The tool follows Colombian law only
class _OutsideColombia extends StatelessWidget {
  const _OutsideColombia({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "tax-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      getExtraHorizontalPadding: (_) => 13,
      listWidgets: [
        IncomeTaxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.public_rounded,
                  size: 34, color: Theme.of(context).colorScheme.primary),
              SizedBox(height: 10),
              TextFont(
                text: "tax-colombia-only".tr(),
                fontSize: 16,
                maxLines: 10,
              ),
              SizedBox(height: 14),
              Button(
                label: "tax-open-settings".tr(),
                icon: Icons.settings_rounded,
                flexibleLayout: true,
                onTap: () async {
                  await pushRoute(context, MoreOptionsPagePreferences());
                  // Back from Ajustes, the country may have changed
                  onBack();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
