import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/activeLoans.dart';
import 'package:budget/pages/tools/incomeProfile.dart';
import 'package:budget/pages/tools/loanWidgets.dart';
import 'package:budget/pages/tools/rateCalculatorPage.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Loan simulator in three tabs: Simular (the loan, extra payments and the
// "¿Me alcanza?" check), Mis ingresos (income profile and payday reminders)
// and Mis préstamos (loans being paid). Every figure is a projection.

String loanRateKindLabel(LoanRateKind kind) {
  switch (kind) {
    case LoanRateKind.ea:
      return "tools-rate-ea".tr();
    case LoanRateKind.monthlyArrears:
      return "loan-rate-mv".tr();
    case LoanRateKind.monthlyAnticipated:
      return "loan-rate-ma".tr();
    case LoanRateKind.nmv:
      return "tools-rate-nmv".tr();
    case LoanRateKind.nama:
      return "tools-rate-nama".tr();
  }
}

String loanRateKindShort(LoanRateKind kind) {
  switch (kind) {
    case LoanRateKind.ea:
      return "EA";
    case LoanRateKind.monthlyArrears:
      return "MV";
    case LoanRateKind.monthlyAnticipated:
      return "MA";
    case LoanRateKind.nmv:
      return "NMV";
    case LoanRateKind.nama:
      return "NAMA";
  }
}

class _ExtraPaymentInput {
  final TextEditingController amount = TextEditingController();
  final TextEditingController month = TextEditingController();

  void dispose() {
    amount.dispose();
    month.dispose();
  }
}

class LoanSimulatorPage extends StatefulWidget {
  const LoanSimulatorPage({this.initialTab = 0, super.key});
  final int initialTab;

  @override
  State<LoanSimulatorPage> createState() => _LoanSimulatorPageState();
}

class _LoanSimulatorPageState extends State<LoanSimulatorPage> {
  static const List<int> termPresets = [12, 24, 36, 48, 60];

  late int tab = widget.initialTab.clamp(0, 2);
  final TextEditingController amountController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  final TextEditingController monthsController = TextEditingController();
  final TextEditingController feeController = TextEditingController();
  final List<_ExtraPaymentInput> extras = [];
  LoanRateKind rateKind = LoanRateKind.ea;
  AmortizationSystem system = AmortizationSystem.fixedInstallment;
  ExtraPaymentMode extraMode = ExtraPaymentMode.reduceTerm;
  DateTime firstInstallment = addMonthsClamped(DateTime.now(), 1);
  IncomeProfile profile = IncomeProfile.load();

  @override
  void dispose() {
    amountController.dispose();
    rateController.dispose();
    monthsController.dispose();
    feeController.dispose();
    for (_ExtraPaymentInput extra in extras) extra.dispose();
    super.dispose();
  }

  void refresh(_) => setState(() {});

  void loadExample() {
    amountController.text = "8.000.000";
    rateController.text = "26";
    monthsController.text = "36";
    feeController.text = "";
    for (_ExtraPaymentInput extra in extras) extra.dispose();
    extras.clear();
    setState(() {
      rateKind = LoanRateKind.ea;
      system = AmortizationSystem.fixedInstallment;
      extraMode = ExtraPaymentMode.reduceTerm;
    });
  }

  void addExtra() {
    setState(() => extras.add(_ExtraPaymentInput()));
  }

  void removeExtra(int index) {
    _ExtraPaymentInput removed = extras.removeAt(index);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  @override
  Widget build(BuildContext context) {
    bool outlined = appStateSettings["outlinedIcons"] == true;
    double amount = parseToolNumber(amountController.text)?.abs() ?? 0;
    double? ratePercent = parseColombianNumber(rateController.text);
    int months = parseToolNumber(monthsController.text)?.round() ?? 0;
    double fee = parseToolNumber(feeController.text)?.abs() ?? 0;
    List<ExtraPayment> extraPayments = [
      for (_ExtraPaymentInput extra in extras)
        if ((parseToolNumber(extra.amount.text) ?? 0) > 0 &&
            (parseToolNumber(extra.month.text)?.round() ?? 0) > 0)
          ExtraPayment(
            month: parseToolNumber(extra.month.text)!.round(),
            amount: parseToolNumber(extra.amount.text)!.abs(),
          ),
    ];

    bool validRate =
        ratePercent != null && isValidLoanRate(ratePercent / 100, rateKind);
    double monthlyRate =
        validRate ? loanRateToMonthlyEffective(ratePercent / 100, rateKind) : 0;
    bool canSimulate = amount > 0 && months > 0 && months <= 600 && validRate;

    LoanResult? result;
    LoanResult? base;
    if (canSimulate) {
      base = simulateLoan(
        amount: amount,
        monthlyRate: monthlyRate,
        months: months,
        system: system,
        monthlyFee: fee,
      );
      result = extraPayments.isEmpty
          ? base
          : simulateLoan(
              amount: amount,
              monthlyRate: monthlyRate,
              months: months,
              system: system,
              monthlyFee: fee,
              extraPayments: extraPayments,
              extraMode: extraMode,
            );
    }

    Widget content;
    if (tab == 1) {
      content = IncomeProfileSection(
        profile: profile,
        onChanged: () => setState(() {}),
      );
    } else if (tab == 2) {
      content = ActiveLoansSection(otherDebts: profile.otherDebts);
    } else {
      content = _buildSimulate(
        context,
        amount: amount,
        months: months,
        ratePercent: ratePercent,
        validRate: validRate,
        monthlyRate: monthlyRate,
        result: result,
        base: base,
      );
    }

    return PageFramework(
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      title: "tools-loan-simulator".tr(),
      sliversBefore: false,
      listWidgets: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 18, end: 18, top: 5, bottom: 14),
          child: LoanTabs(
            labels: [
              "loan-tab-simulate".tr(),
              "loan-tab-income".tr(),
              "loan-tab-loans".tr(),
            ],
            icons: [
              outlined ? Icons.calculate_outlined : Icons.calculate_rounded,
              outlined ? Icons.payments_outlined : Icons.payments_rounded,
              outlined
                  ? Icons.account_balance_outlined
                  : Icons.account_balance_rounded,
            ],
            selected: tab,
            onChanged: (value) {
              minimizeKeyboard(context);
              setState(() => tab = value);
            },
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: KeyedSubtree(
            key: ValueKey(tab),
            child: tab == 0
                ? content
                : Padding(
                    padding:
                        const EdgeInsetsDirectional.symmetric(horizontal: 18),
                    child: content,
                  ),
          ),
        ),
      ],
      slivers: [
        if (tab == 0 && result != null) ..._buildTable(context, result),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ],
    );
  }

  Widget _buildSimulate(
    BuildContext context, {
    required double amount,
    required int months,
    required double? ratePercent,
    required bool validRate,
    required double monthlyRate,
    required LoanResult? result,
    required LoanResult? base,
  }) {
    bool outlined = appStateSettings["outlinedIcons"] == true;
    String money(double value) => formatToolMoney(context, value);

    List<Widget> inputs = [
      const LoanDisclaimer(),
      LoanActionButton(
        label: "loan-try-example".tr(),
        icon: outlined ? Icons.two_wheeler_outlined : Icons.two_wheeler_rounded,
        secondary: true,
        onTap: loadExample,
      ),
      ToolNote(text: "loan-try-example-description".tr()),
      ToolInputField(
        label: "tools-loan-amount".tr(),
        hint: "8.000.000",
        prefix: "\$ ",
        controller: amountController,
        onChanged: refresh,
      ),
      LoanGuide(text: "loan-guide-amount".tr()),
      ToolInputField(
        label: "tools-rate".tr(),
        hint: "26",
        suffix: "% " + loanRateKindShort(rateKind),
        controller: rateController,
        onChanged: refresh,
      ),
      SelectChips<LoanRateKind>(
        items: LoanRateKind.values,
        wrapped: true,
        allowMultipleSelected: false,
        padding: EdgeInsetsDirectional.zero,
        getSelected: (kind) => kind == rateKind,
        onSelected: (kind) => setState(() => rateKind = kind),
        getLabel: loanRateKindLabel,
      ),
      const SizedBox(height: 8),
      if (validRate)
        ToolNote(
          text: "loan-rate-equivalent".tr(namedArgs: {
            "ea": formatToolPercent(
                monthlyEffectiveToLoanRate(monthlyRate, LoanRateKind.ea)),
            "mv": formatToolPercent(monthlyRate, decimals: 3),
          }),
        )
      else if (rateController.text.trim() != "")
        ToolNote(
          text: "tools-invalid-rate".tr(),
          color: getColor(context, "expenseAmount"),
        ),
      LoanGuide(
        title: "loan-guide-rate-title".tr(),
        text: "loan-guide-rate".tr(),
      ),
      LoanGuide(
        title: "loan-guide-mv-ma-title".tr(),
        text: "loan-guide-mv-ma".tr(),
      ),
      ToolInputField(
        label: "tools-term-months".tr(),
        hint: "36",
        controller: monthsController,
        onChanged: refresh,
      ),
      SelectChips<int>(
        items: termPresets,
        wrapped: true,
        allowMultipleSelected: false,
        padding: EdgeInsetsDirectional.zero,
        getSelected: (value) => value == months,
        onSelected: (value) {
          monthsController.text = value.toString();
          setState(() {});
        },
        getLabel: (value) =>
            "loan-months-count".tr(namedArgs: {"months": value.toString()}),
      ),
      const SizedBox(height: 8),
      LoanGuide(text: "loan-guide-term".tr()),
      LoanPickerRow(
        icon: outlined ? Icons.event_outlined : Icons.event_rounded,
        label: "loan-first-installment".tr(),
        value: getWordedDateShort(firstInstallment, includeYear: true),
        onTap: () async {
          DateTime? picked =
              await showCustomDatePicker(context, firstInstallment);
          if (picked != null) {
            setState(() => firstInstallment =
                DateTime(picked.year, picked.month, picked.day));
          }
        },
      ),
      ToolSectionTitle(text: "tools-amortization-system".tr()),
      SelectChips<AmortizationSystem>(
        items: AmortizationSystem.values,
        wrapped: true,
        allowMultipleSelected: false,
        padding: EdgeInsetsDirectional.zero,
        getSelected: (value) => value == system,
        onSelected: (value) => setState(() => system = value),
        getLabel: (value) => value == AmortizationSystem.fixedInstallment
            ? "tools-fixed-installment".tr()
            : "tools-constant-principal".tr(),
      ),
      const SizedBox(height: 8),
      LoanGuide(
        title: "loan-guide-system-title".tr(),
        text: "loan-guide-system".tr(),
      ),
      ToolInputField(
        label: "tools-monthly-fee".tr(),
        hint: "15.000",
        prefix: "\$ ",
        controller: feeController,
        onChanged: refresh,
      ),
      LoanGuide(
        title: "loan-guide-fee-title".tr(),
        text: "loan-guide-fee".tr(),
      ),
      ToolSectionTitle(text: "loan-extra-payments".tr()),
      LoanGuide(
        title: "loan-guide-extra-title".tr(),
        text: "loan-guide-extra".tr(),
      ),
      for (int i = 0; i < extras.length; i++) _buildExtraRow(i, months),
      LoanActionButton(
        label: "loan-add-extra".tr(),
        icon: outlined ? Icons.add_circle_outline : Icons.add_circle_rounded,
        secondary: true,
        onTap: addExtra,
      ),
      if (extras.isNotEmpty) ...[
        SelectChips<ExtraPaymentMode>(
          items: ExtraPaymentMode.values,
          wrapped: true,
          allowMultipleSelected: false,
          padding: EdgeInsetsDirectional.zero,
          getSelected: (value) => value == extraMode,
          onSelected: (value) => setState(() => extraMode = value),
          getLabel: (value) => value == ExtraPaymentMode.reduceTerm
              ? "tools-reduce-term".tr()
              : "tools-reduce-installment".tr(),
        ),
        const SizedBox(height: 10),
      ],
      ToolSectionTitle(text: "tools-results".tr()),
    ];

    if (result == null || base == null) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...inputs,
            ToolNote(text: "tools-loan-enter-data".tr()),
          ],
        ),
      );
    }

    DateTime lastDate = addMonthsClamped(firstInstallment, result.months - 1);
    String? installmentNote;
    if (system == AmortizationSystem.constantPrincipal) {
      installmentNote = "tools-installment-range".tr(namedArgs: {
        "first": money(result.firstInstallment),
        "last": money(result.lastInstallment),
      });
    } else if (result.totalExtra > 0 &&
        extraMode == ExtraPaymentMode.reduceInstallment) {
      int extraIndex = result.rows.lastIndexWhere((row) => row.extra > 0);
      if (extraIndex + 1 < result.rows.length) {
        AmortizationRow after = result.rows[extraIndex + 1];
        installmentNote = "tools-new-installment".tr(namedArgs: {
          "month": after.month.toString(),
          "amount": money(after.installment),
        });
      }
    }
    ExtraPaymentSavings? savings =
        result.totalExtra > 0 ? ExtraPaymentSavings(base, result) : null;

    List<Widget> results = [
      ToolResultRow(
        label: "tools-monthly-installment".tr(),
        value: money(result.firstInstallment),
        description: installmentNote,
        highlight: true,
      ),
      ToolResultRow(
        label: "tools-total-paid".tr(),
        value: money(result.totalPaid),
        description: "loan-total-paid-description".tr(namedArgs: {
          "amount": money(result.amount),
        }),
      ),
      ToolResultRow(
        label: "tools-total-interest".tr(),
        value: money(result.totalInterest),
      ),
      if (result.totalFees > 0)
        ToolResultRow(
          label: "tools-total-fees".tr(),
          value: money(result.totalFees),
        ),
      ToolResultRow(
        label: "tools-real-cost".tr(),
        value: money(result.totalPaid - result.amount),
        description: "tools-real-cost-description".tr(namedArgs: {
          "percent": formatToolPercent(result.costOverAmount, decimals: 1),
        }),
      ),
      ToolResultRow(
        label: "tools-loan-ends".tr(),
        value: getWordedDateShort(lastDate, includeYear: true),
        description: "loan-term-description".tr(namedArgs: {
          "months": result.months.toString(),
          "years": removeTrailingZeroes((result.months / 12).toStringAsFixed(1))
              .replaceAll(".", getDecimalSeparator()),
        }),
      ),
      if (savings != null) ...[
        ToolResultRow(
          label: "tools-extra-savings".tr(),
          value: money(max(0, savings.total)),
          description: savings.months > 0
              ? "tools-extra-savings-description"
                  .tr(namedArgs: {"months": savings.months.toString()})
              : "loan-savings-same-term".tr(),
          highlight: true,
        ),
        ToolResultRow(
          label: "loan-without-extra".tr(),
          value: money(base.totalPaid),
          description: "loan-without-extra-description".tr(namedArgs: {
            "count": base.months.toString(),
            "installment": money(base.firstInstallment),
          }),
        ),
        for (ExtraPayment payment in _outOfTerm(base, result))
          ToolNote(
            text: "loan-extra-out-of-term"
                .tr(namedArgs: {"month": payment.month.toString()}),
            color: getColor(context, "warningOrange"),
          ),
      ],
    ];

    List<Widget> afterUsury = [
      const SizedBox(height: 6),
      _AffordabilityCard(
        profile: profile,
        newInstallment: result.firstInstallment,
        onGoToIncome: () => setState(() => tab = 1),
      ),
      ToolSectionTitle(text: "loan-save-title".tr()),
      ToolNote(text: "loan-save-description".tr()),
      LoanActionButton(
        label: "loan-save-simulation".tr(),
        icon: outlined ? Icons.save_outlined : Icons.save_rounded,
        onTap: () => openSaveSimulatedLoan(
          context,
          plan: base,
          firstInstallment: firstInstallment,
          rateNote: "loan-rate-note-kind".tr(namedArgs: {
            "rate": formatToolPercent((ratePercent ?? 0) / 100),
            "kind": loanRateKindShort(rateKind),
          }),
          variableInstallment: system == AmortizationSystem.constantPrincipal,
          hadExtraPayments: result.totalExtra > 0,
          onSaved: () => setState(() => tab = 2),
        ),
      ),
      const LoanDisclaimer(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...inputs, ...results],
          ),
        ),
        UsuryWarning(
            ea: monthlyEffectiveToLoanRate(monthlyRate, LoanRateKind.ea)),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: afterUsury,
          ),
        ),
      ],
    );
  }

  // Extra payments set after the loan is already paid off
  List<ExtraPayment> _outOfTerm(LoanResult base, LoanResult result) {
    List<ExtraPayment> out = [];
    for (_ExtraPaymentInput extra in extras) {
      int month = parseToolNumber(extra.month.text)?.round() ?? 0;
      double value = parseToolNumber(extra.amount.text) ?? 0;
      if (value > 0 && month > result.months) {
        out.add(ExtraPayment(month: month, amount: value));
      }
    }
    return out;
  }

  Widget _buildExtraRow(int index, int months) {
    _ExtraPaymentInput extra = extras[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 3,
          child: ToolInputField(
            label: "loan-extra-amount"
                .tr(namedArgs: {"number": (index + 1).toString()}),
            hint: "1.000.000",
            prefix: "\$ ",
            controller: extra.amount,
            onChanged: refresh,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ToolInputField(
            label: "tools-extra-payment-month".tr(),
            hint: months > 1 ? (months ~/ 2).toString() : "6",
            controller: extra.month,
            onChanged: refresh,
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 16),
          child: IconButton(
            tooltip: "loan-remove-extra".tr(),
            icon: Icon(
              Icons.close_rounded,
              color: getColor(context, "textLight"),
            ),
            onPressed: () => removeExtra(index),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTable(BuildContext context, LoanResult result) {
    String money(double value) => formatToolMoney(context, value);
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
      SliverToBoxAdapter(
        child: _TableRow(
          cells: [
            "tools-month-short".tr(),
            "tools-installment".tr(),
            "tools-interest".tr(),
            "tools-principal".tr(),
            "tools-balance".tr(),
          ],
          bold: true,
        ),
      ),
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

// "¿Me alcanza?": all installments against the monthly income
class _AffordabilityCard extends StatelessWidget {
  const _AffordabilityCard({
    required this.profile,
    required this.newInstallment,
    required this.onGoToIncome,
  });
  final IncomeProfile profile;
  final double newInstallment;
  final VoidCallback onGoToIncome;

  @override
  Widget build(BuildContext context) {
    String money(double value) => formatToolMoney(context, value);
    bool outlined = appStateSettings["outlinedIcons"] == true;
    List<Widget> header = [
      ToolSectionTitle(text: "loan-afford-title".tr()),
    ];
    if (profile.isSet == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          ToolNote(text: "loan-afford-no-income".tr()),
          LoanActionButton(
            label: "loan-afford-add-income".tr(),
            icon: outlined ? Icons.payments_outlined : Icons.payments_rounded,
            secondary: true,
            onTap: onGoToIncome,
          ),
        ],
      );
    }
    return ActiveLoansBuilder(builder: (context, loans) {
      double income = profile.monthlyIncome;
      double loansTotal = totalMonthlyInstallments(loans);
      double current = loansTotal + profile.otherDebts;
      double total = current + newInstallment;
      double ratio = debtToIncomeRatio(total, income) ?? 0;
      DebtLevel level = debtLevel(ratio);
      Color color = {
        DebtLevel.healthy: getColor(context, "incomeAmount"),
        DebtLevel.caution: getColor(context, "warningOrange"),
        DebtLevel.risky: getColor(context, "expenseAmount"),
      }[level]!;
      String percent = formatToolPercent(ratio, decimals: 1);
      double left = income - profile.expenses - total;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          ToolResultRow(
            label: "loan-income-monthly".tr(),
            value: money(income),
          ),
          ToolResultRow(
            label: "loan-afford-current".tr(),
            value: money(current),
            description: profile.otherDebts > 0
                ? "loan-active-total-with-other".tr(namedArgs: {
                    "loans": money(loansTotal),
                    "other": money(profile.otherDebts),
                  })
                : "loan-active-count"
                    .tr(namedArgs: {"count": loans.length.toString()}),
          ),
          ToolResultRow(
            label: "loan-afford-new".tr(),
            value: money(newInstallment),
          ),
          _RatioBar(ratio: ratio, color: color),
          LoanNotice(
            color: color,
            icon: level == DebtLevel.healthy
                ? Icons.check_circle_outline_rounded
                : level == DebtLevel.caution
                    ? Icons.info_outline_rounded
                    : Icons.warning_rounded,
            title: {
              DebtLevel.healthy: "loan-afford-healthy-title",
              DebtLevel.caution: "loan-afford-caution-title",
              DebtLevel.risky: "loan-afford-risky-title",
            }[level]!
                .tr(),
            text: {
              DebtLevel.healthy: "loan-afford-healthy",
              DebtLevel.caution: "loan-afford-caution",
              DebtLevel.risky: "loan-afford-risky",
            }[level]!
                .tr(namedArgs: {"percent": percent}),
          ),
          ToolResultRow(
            label: "loan-afford-max".tr(),
            value: money(maxAffordableInstallment(income, current)),
            description: "loan-afford-max-description".tr(),
          ),
          if (profile.expenses > 0) ...[
            ToolResultRow(
              label: "loan-afford-left".tr(),
              value: (left < 0 ? "-" : "") + money(left.abs()),
              description: "loan-afford-left-description".tr(namedArgs: {
                "expenses": money(profile.expenses),
              }),
            ),
            if (left < 0)
              LoanNotice(
                color: getColor(context, "expenseAmount"),
                icon: Icons.warning_rounded,
                text: "loan-afford-not-enough"
                    .tr(namedArgs: {"amount": money(left.abs())}),
              ),
          ] else
            ToolNote(text: "loan-afford-add-expenses".tr()),
          ToolNote(text: "loan-afford-guide".tr()),
        ],
      );
    });
  }
}

class _RatioBar extends StatelessWidget {
  const _RatioBar({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFont(
            text: "loan-afford-ratio".tr(namedArgs: {
              "percent": formatToolPercent(ratio, decimals: 1),
            }),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            maxLines: 2,
          ),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, constraints) {
            double width = constraints.maxWidth;
            Widget marker(double at) => PositionedDirectional(
                  start: width * at - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: getColor(context, "textLight").withOpacity(0.6),
                  ),
                );
            return SizedBox(
              height: 14,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: getColor(context, "lightDarkAccentHeavyLight"),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio.clamp(0, 1).toDouble()),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Container(
                      width: width * value,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  marker(debtHealthyLimit),
                  marker(debtCautionLimit),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          LayoutBuilder(builder: (context, constraints) {
            double width = constraints.maxWidth;
            return SizedBox(
              height: 16,
              child: Stack(
                children: [
                  for (double at in [debtHealthyLimit, debtCautionLimit])
                    PositionedDirectional(
                      start: width * at - 14,
                      child: TextFont(
                        text: formatToolPercent(at, decimals: 0),
                        fontSize: 11,
                        textColor: getColor(context, "textLight"),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
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
