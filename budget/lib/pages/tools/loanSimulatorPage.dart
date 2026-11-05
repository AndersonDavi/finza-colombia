import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/rateCalculatorPage.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;
import 'package:provider/provider.dart';

class LoanSimulatorPage extends StatefulWidget {
  const LoanSimulatorPage({super.key});

  @override
  State<LoanSimulatorPage> createState() => _LoanSimulatorPageState();
}

class _LoanSimulatorPageState extends State<LoanSimulatorPage> {
  String amountText = "";
  String rateText = "";
  String monthsText = "";
  String feeText = "";
  String extraAmountText = "";
  String extraMonthText = "";
  RateType rateType = RateType.ea;
  AmortizationSystem system = AmortizationSystem.fixedInstallment;
  ExtraPaymentMode extraMode = ExtraPaymentMode.reduceTerm;

  final List<TextInputFormatter> digitsOnly = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  @override
  Widget build(BuildContext context) {
    double amount = parseColombianNumber(amountText, amount: true) ?? 0;
    double? ratePercent = parseColombianNumber(rateText);
    int months = int.tryParse(monthsText) ?? 0;
    double fee = parseColombianNumber(feeText, amount: true) ?? 0;
    double extraAmount =
        parseColombianNumber(extraAmountText, amount: true) ?? 0;
    int extraMonth = int.tryParse(extraMonthText) ?? 0;

    bool validRate =
        ratePercent != null && isValidRate(ratePercent / 100, rateType);
    double monthlyRate =
        validRate ? rateToMonthlyEffective(ratePercent / 100, rateType) : 0;
    bool canSimulate = amount > 0 && months > 0 && months <= 1200 && validRate;

    LoanResult? result;
    LoanResult? withoutExtra;
    if (canSimulate) {
      result = simulateLoan(
        amount: amount,
        monthlyRate: monthlyRate,
        months: months,
        system: system,
        monthlyFee: fee,
        extraAmount: extraAmount,
        extraMonth: extraMonth,
        extraMode: extraMode,
      );
      if (result.totalExtra > 0) {
        withoutExtra = simulateLoan(
          amount: amount,
          monthlyRate: monthlyRate,
          months: months,
          system: system,
          monthlyFee: fee,
        );
      }
    }

    AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double value) =>
        convertToMoney(allWallets, value, finalNumber: value.abs());

    return PageFramework(
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      title: "tools-loan-simulator".tr(),
      sliversBefore: false,
      listWidgets: [
        TextInput(
          labelText: "tools-loan-amount".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.payments_outlined
              : Icons.payments_rounded,
          keyboardType: decimalKeyboard,
          inputFormatters: decimalInputFormatters,
          onChanged: (value) => setState(() => amountText = value),
        ),
        const SizedBox(height: 10),
        TextInput(
          labelText: "tools-rate".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.percent_outlined
              : Icons.percent_rounded,
          suffix: "%",
          keyboardType: decimalKeyboard,
          inputFormatters: decimalInputFormatters,
          onChanged: (value) => setState(() => rateText = value),
        ),
        const SizedBox(height: 5),
        SelectChips<RateType>(
          items: const [RateType.ea, RateType.em, RateType.nmv],
          wrapped: true,
          allowMultipleSelected: false,
          getSelected: (type) => type == rateType,
          onSelected: (type) => setState(() => rateType = type),
          getLabel: rateTypeLabel,
        ),
        const SizedBox(height: 5),
        TextInput(
          labelText: "tools-term-months".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.calendar_month_outlined
              : Icons.calendar_month_rounded,
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          onChanged: (value) => setState(() => monthsText = value),
        ),
        SettingsHeader(title: "tools-amortization-system".tr()),
        SelectChips<AmortizationSystem>(
          items: AmortizationSystem.values,
          wrapped: true,
          allowMultipleSelected: false,
          getSelected: (value) => value == system,
          onSelected: (value) => setState(() => system = value),
          getLabel: (value) => value == AmortizationSystem.fixedInstallment
              ? "tools-fixed-installment".tr()
              : "tools-constant-principal".tr(),
        ),
        const SizedBox(height: 10),
        TextInput(
          labelText: "tools-monthly-fee".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.shield_outlined
              : Icons.shield_rounded,
          keyboardType: decimalKeyboard,
          inputFormatters: decimalInputFormatters,
          onChanged: (value) => setState(() => feeText = value),
        ),
        SettingsHeader(title: "tools-extra-payment".tr()),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextInput(
                labelText: "tools-extra-payment-amount".tr(),
                padding: const EdgeInsetsDirectional.only(start: 18, end: 5),
                keyboardType: decimalKeyboard,
                inputFormatters: decimalInputFormatters,
                onChanged: (value) => setState(() => extraAmountText = value),
              ),
            ),
            Expanded(
              flex: 2,
              child: TextInput(
                labelText: "tools-extra-payment-month".tr(),
                padding: const EdgeInsetsDirectional.only(start: 5, end: 18),
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly,
                onChanged: (value) => setState(() => extraMonthText = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SelectChips<ExtraPaymentMode>(
          items: ExtraPaymentMode.values,
          wrapped: true,
          allowMultipleSelected: false,
          getSelected: (value) => value == extraMode,
          onSelected: (value) => setState(() => extraMode = value),
          getLabel: (value) => value == ExtraPaymentMode.reduceTerm
              ? "tools-reduce-term".tr()
              : "tools-reduce-installment".tr(),
        ),
        SettingsHeader(title: "tools-results".tr()),
        if (result == null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 18, vertical: 10),
            child: TextFont(
              text: rateText.trim() != "" && validRate == false
                  ? "tools-invalid-rate".tr()
                  : "tools-loan-enter-data".tr(),
              fontSize: 15,
              maxLines: 3,
              textColor: getColor(context, "textLight"),
            ),
          )
        else
          ..._buildSummary(context, result, withoutExtra, monthlyRate, money),
      ],
      slivers: [
        if (result != null) ..._buildTable(context, result, money),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  List<Widget> _buildSummary(
    BuildContext context,
    LoanResult result,
    LoanResult? withoutExtra,
    double monthlyRate,
    String Function(double) money,
  ) {
    String installment = money(result.firstInstallment);
    String? installmentNote;
    if (system == AmortizationSystem.constantPrincipal) {
      installmentNote = "tools-installment-range".tr(namedArgs: {
        "first": money(result.firstInstallment),
        "last": money(result.lastInstallment),
      });
    } else if (result.totalExtra > 0 &&
        extraMode == ExtraPaymentMode.reduceInstallment) {
      int extraIndex = result.rows.indexWhere((row) => row.extra > 0);
      if (extraIndex + 1 < result.rows.length) {
        AmortizationRow after = result.rows[extraIndex + 1];
        installmentNote = "tools-new-installment".tr(namedArgs: {
          "month": after.month.toString(),
          "amount": money(after.installment),
        });
      }
    }

    return [
      _SummaryRow(
        label: "tools-monthly-installment".tr(),
        value: installment,
        note: installmentNote,
        big: true,
      ),
      _SummaryRow(
        label: "tools-total-paid".tr(),
        value: money(result.totalPaid),
      ),
      _SummaryRow(
        label: "tools-total-interest".tr(),
        value: money(result.totalInterest),
      ),
      if (result.totalFees > 0)
        _SummaryRow(
          label: "tools-total-fees".tr(),
          value: money(result.totalFees),
        ),
      _SummaryRow(
        label: "tools-real-cost".tr(),
        value: money(result.totalPaid - result.amount),
        note: "tools-real-cost-description".tr(namedArgs: {
          "percent": formatRatePercent(result.costOverAmount, decimals: 1),
        }),
      ),
      _SummaryRow(
        label: "tools-loan-ends".tr(),
        value: "tools-month-number"
            .tr(namedArgs: {"month": result.months.toString()}),
      ),
      if (withoutExtra != null)
        _SummaryRow(
          label: "tools-extra-savings".tr(),
          value: money(withoutExtra.totalInterest - result.totalInterest),
          note: "tools-extra-savings-description".tr(namedArgs: {
            "months": (withoutExtra.months - result.months).toString(),
          }),
        ),
      const SizedBox(height: 5),
      UsuryWarning(ea: monthlyEffectiveToRate(monthlyRate, RateType.ea)),
    ];
  }

  List<Widget> _buildTable(
    BuildContext context,
    LoanResult result,
    String Function(double) money,
  ) {
    Widget header = _TableRow(
      cells: [
        "tools-month-short".tr(),
        "tools-installment".tr(),
        "tools-interest".tr(),
        "tools-principal".tr(),
        "tools-balance".tr(),
      ],
      bold: true,
    );
    return [
      SliverToBoxAdapter(
        child: SettingsHeader(title: "tools-amortization-table".tr()),
      ),
      if (result.totalExtra > 0)
        SliverToBoxAdapter(
          child: Padding(
            padding:
                const EdgeInsetsDirectional.only(start: 18, end: 18, bottom: 5),
            child: TextFont(
              text: "tools-extra-payment-row-note".tr(),
              fontSize: 13,
              maxLines: 3,
              textColor: getColor(context, "textLight"),
            ),
          ),
        ),
      SliverToBoxAdapter(child: header),
      SliverList.builder(
        itemCount: result.rows.length,
        itemBuilder: (context, index) {
          AmortizationRow row = result.rows[index];
          return _TableRow(
            highlighted: row.extra > 0,
            cells: [
              row.month.toString(),
              money(row.installment + row.extra),
              money(row.interest),
              money(row.principal + row.extra),
              money(row.balance),
            ],
          );
        },
      ),
    ];
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.note,
    this.big = false,
  });
  final String label;
  final String value;
  final String? note;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 3),
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: big
              ? Theme.of(context).colorScheme.secondaryContainer
              : getColor(context, "canvasContainer"),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFont(text: label, fontSize: 15, maxLines: 2),
                  if (note != null)
                    TextFont(
                      text: note!,
                      fontSize: 13,
                      maxLines: 3,
                      textColor: getColor(context, "textLight"),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextFont(
              text: value,
              fontSize: big ? 20 : 16,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.cells,
    this.bold = false,
    this.highlighted = false,
  });
  final List<String> cells;
  final bool bold;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 12),
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        border: Border(
          bottom: BorderSide(color: getColor(context, "dividerColor")),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++)
            Expanded(
              flex: i == 0 ? 2 : 5,
              child: TextFont(
                text: cells[i],
                fontSize: 12,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                maxLines: 1,
                autoSizeText: true,
                minFontSize: 8,
              ),
            ),
        ],
      ),
    );
  }
}
