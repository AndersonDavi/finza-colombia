import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/loanWidgets.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// What the person earns, kept on the device in the app settings. It feeds
// the "¿Me alcanza?" check of the loan simulator.
// Settings keys (none of them has a default in defaultPreferences, so every
// read falls back here):
//   loanIncomeFrequency    "monthly" | "biweekly" | "variable", null = unknown
//   loanIncomeAmount       each payment, or the monthly average when variable
//   loanIncomePayday       day of the month of a monthly salary, 30 default
//   loanMonthlyExpenses    average spending a month, 0 = not given
//   loanOtherDebtPayments  installments not registered as loans, 0 default
//   loanPaydayRemindersDate  ISO date when payday reminders were created

class IncomeProfile {
  IncomeProfile({
    this.frequency,
    this.amount = 0,
    this.payday = 30,
    this.payday2 = 30,
    this.expenses = 0,
    this.otherDebts = 0,
    this.remindersDate,
  });

  PayFrequency? frequency;
  double amount;
  int payday;
  // Second payday of a biweekly salary; payday is the first one
  int payday2;
  double expenses;
  double otherDebts;
  DateTime? remindersDate;

  static double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse("$value") ?? 0;

  factory IncomeProfile.load() {
    String? frequency = appStateSettings["loanIncomeFrequency"]?.toString();
    int payday = _number(appStateSettings["loanIncomePayday"] ?? 30).round();
    int payday2 = _number(appStateSettings["loanIncomePayday2"] ?? 30).round();
    return IncomeProfile(
      frequency: PayFrequency.values
          .where((value) => value.name == frequency)
          .firstOrNull,
      amount: _number(appStateSettings["loanIncomeAmount"]),
      payday: payday < 1 || payday > 31 ? 30 : payday,
      payday2: payday2 < 1 || payday2 > 31 ? 30 : payday2,
      expenses: _number(appStateSettings["loanMonthlyExpenses"]),
      otherDebts: _number(appStateSettings["loanOtherDebtPayments"]),
      remindersDate: DateTime.tryParse(
          appStateSettings["loanPaydayRemindersDate"]?.toString() ?? ""),
    );
  }

  Future<void> save() async {
    Map<String, dynamic> values = {
      "loanIncomeFrequency": frequency?.name,
      "loanIncomeAmount": amount,
      "loanIncomePayday": payday,
      "loanIncomePayday2": payday2,
      "loanMonthlyExpenses": expenses,
      "loanOtherDebtPayments": otherDebts,
      "loanPaydayRemindersDate": remindersDate?.toIso8601String(),
    };
    for (MapEntry<String, dynamic> entry in values.entries) {
      if (appStateSettings[entry.key] == entry.value) continue;
      await updateSettings(entry.key, entry.value, updateGlobalState: false);
    }
  }

  double get monthlyIncome =>
      frequency == null ? 0 : monthlyIncomeFrom(frequency!, amount);

  bool get isSet => frequency != null && amount > 0;

  bool get hasFixedPay =>
      frequency == PayFrequency.monthly || frequency == PayFrequency.biweekly;

  // Days of the month the salary arrives: two when biweekly (the 15th and
  // 30th unless other days were set)
  List<int> get paydays {
    if (frequency != PayFrequency.biweekly) return [payday];
    if (payday == payday2) return [15, 30];
    return payday < payday2 ? [payday, payday2] : [payday2, payday];
  }
}

class AppMonthlyAverages {
  const AppMonthlyAverages(
      {required this.income, required this.expenses, required this.months});
  final double income;
  final double expenses;
  // Months with any movement, out of the last three
  final int months;
}

// Average income and spending a month over the last three full months, from
// the paid transactions of the app. Transfers, balance corrections and
// loans are left out, so loan installments are not counted twice
Future<AppMonthlyAverages> getAppMonthlyAverages(AllWallets allWallets) async {
  DateTime now = DateTime.now();
  DateTime end = DateTime(now.year, now.month, 1);
  DateTime start = DateTime(now.year, now.month - 3, 1);
  List<Transaction> rows = await (database.select(database.transactions)
        ..where((t) =>
            t.paid.equals(true) &
            t.categoryFk.equals("0").not() &
            t.objectiveLoanFk.isNull() &
            (t.type.isNull() |
                t.type.isNotInValues([
                  TransactionSpecialType.credit,
                  TransactionSpecialType.debt,
                ])) &
            t.dateCreated.isBiggerOrEqualValue(start) &
            t.dateCreated.isSmallerThanValue(end)))
      .get();
  double income = 0;
  double expenses = 0;
  Set<int> months = {};
  for (Transaction transaction in rows) {
    double ratio = amountRatioToPrimaryCurrency(
        allWallets, allWallets.indexedByPk[transaction.walletFk]?.currency);
    double value = transaction.amount * ratio;
    if (value > 0) {
      income += value;
    } else {
      expenses += -value;
    }
    months
        .add(transaction.dateCreated.year * 12 + transaction.dateCreated.month);
  }
  int count = months.isEmpty ? 1 : months.length;
  return AppMonthlyAverages(
    income: income / count,
    expenses: expenses / count,
    months: months.length,
  );
}

// An income category for the payday reminders: the default one if it is
// still there, otherwise the first income category
Future<TransactionCategory?> _incomeCategory() async {
  List<TransactionCategory> categories = await database.getAllCategories();
  List<TransactionCategory> income = categories
      .where((category) => category.income && category.archived == false)
      .toList();
  if (income.isEmpty) return null;
  return income.where((c) => c.categoryPk == "11").firstOrNull ?? income.first;
}

// Repeating income transactions for each payday. They start unpaid and stay
// pending until the person confirms the money arrived; nothing is marked
// paid here. Returns how many were created
Future<int> createPaydayReminders(
    BuildContext context, IncomeProfile profile) async {
  if (profile.hasFixedPay == false || profile.amount <= 0) return 0;
  TransactionCategory? category = await _incomeCategory();
  if (category == null) return 0;
  String walletPk = appStateSettings["selectedWalletPk"]?.toString() ?? "0";
  DateTime now = DateTime.now();
  int created = 0;
  for (int day in profile.paydays) {
    await database.createOrUpdateTransaction(
      insert: true,
      Transaction(
        transactionPk: "-1",
        name: "loan-payday-reminder-name".tr(),
        note: "loan-payday-reminder-note".tr(),
        amount: profile.amount.abs(),
        categoryFk: category.categoryPk,
        walletFk: walletPk,
        dateCreated: nextDayOfMonth(now, day),
        income: true,
        paid: false,
        skipPaid: false,
        type: TransactionSpecialType.repetitive,
        reoccurrence: BudgetReoccurence.monthly,
        periodLength: 1,
        upcomingTransactionNotification: true,
        createdAnotherFutureTransaction: false,
      ),
    );
    created++;
  }
  profile.remindersDate = now;
  await profile.save();
  if (context.mounted) await setUpcomingNotifications(context);
  return created;
}

// "Mis ingresos" tab
class IncomeProfileSection extends StatefulWidget {
  const IncomeProfileSection(
      {required this.profile, required this.onChanged, super.key});
  final IncomeProfile profile;
  final VoidCallback onChanged;

  @override
  State<IncomeProfileSection> createState() => _IncomeProfileSectionState();
}

class _IncomeProfileSectionState extends State<IncomeProfileSection> {
  late final TextEditingController amountController = TextEditingController(
      text: widget.profile.amount > 0
          ? toolNumberToInput(widget.profile.amount)
          : "");
  late final TextEditingController paydayController =
      TextEditingController(text: widget.profile.payday.toString());
  late final TextEditingController expensesController = TextEditingController(
      text: widget.profile.expenses > 0
          ? toolNumberToInput(widget.profile.expenses)
          : "");
  late final TextEditingController otherDebtsController = TextEditingController(
      text: widget.profile.otherDebts > 0
          ? toolNumberToInput(widget.profile.otherDebts)
          : "");
  AppMonthlyAverages? averages;
  bool creatingReminders = false;

  IncomeProfile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      if (!mounted) return;
      AppMonthlyAverages result = await getAppMonthlyAverages(
          Provider.of<AllWallets>(context, listen: false));
      if (mounted) setState(() => averages = result);
    });
  }

  @override
  void dispose() {
    amountController.dispose();
    paydayController.dispose();
    expensesController.dispose();
    otherDebtsController.dispose();
    super.dispose();
  }

  void changed() {
    profile.save();
    widget.onChanged();
    setState(() {});
  }

  void useValue(TextEditingController controller, double value,
      void Function(double) apply) {
    double rounded = value.roundToDouble();
    controller.text = toolNumberToInput(rounded);
    apply(rounded);
    changed();
  }

  Future<void> askReminders() async {
    List<String> dates = [
      for (int day in profile.paydays)
        getWordedDateShort(nextDayOfMonth(DateTime.now(), day)),
    ];
    bool? confirmed = await openPopup<bool>(
      context,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.notifications_outlined
          : Icons.notifications_rounded,
      title: "loan-payday-reminders-create".tr(),
      description: (profile.frequency == PayFrequency.biweekly
                  ? "loan-payday-reminders-confirm-biweekly"
                  : "loan-payday-reminders-confirm-monthly")
              .tr(namedArgs: {
            "amount": formatToolMoney(context, profile.amount),
            "dates": dates.join(" · "),
          }) +
          (profile.remindersDate != null
              ? "\n\n" + "loan-payday-reminders-again".tr()
              : ""),
      onSubmitLabel: "loan-create".tr(),
      onCancelLabel: "cancel".tr(),
      onSubmit: () => popRoute(context, true),
      onCancel: () => popRoute(context, false),
    );
    if (confirmed != true || !mounted) return;
    setState(() => creatingReminders = true);
    int created = await createPaydayReminders(context, profile);
    if (!mounted) return;
    setState(() => creatingReminders = false);
    openSnackbar(SnackbarMessage(
      title: created > 0
          ? "loan-payday-reminders-created".tr()
          : "loan-payday-reminders-no-category".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.event_repeat_outlined
          : Icons.event_repeat_rounded,
    ));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    bool outlined = appStateSettings["outlinedIcons"] == true;
    String amountLabel = {
      PayFrequency.monthly: "loan-income-amount-monthly",
      PayFrequency.biweekly: "loan-income-amount-biweekly",
      PayFrequency.variable: "loan-income-amount-variable",
    }[profile.frequency ?? PayFrequency.monthly]!
        .tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolNote(text: "loan-income-intro".tr()),
        ToolSectionTitle(text: "loan-income-how-paid".tr()),
        _PayOption(
          icon: outlined ? Icons.calendar_month_outlined : Icons.calendar_month,
          title: "loan-pay-monthly".tr(),
          description: "loan-pay-monthly-description".tr(),
          selected: profile.frequency == PayFrequency.monthly,
          onTap: () {
            profile.frequency = PayFrequency.monthly;
            changed();
          },
        ),
        _PayOption(
          icon: outlined ? Icons.event_repeat_outlined : Icons.event_repeat,
          title: "loan-pay-biweekly".tr(),
          description: "loan-pay-biweekly-description".tr(),
          selected: profile.frequency == PayFrequency.biweekly,
          onTap: () {
            profile.frequency = PayFrequency.biweekly;
            changed();
          },
        ),
        _PayOption(
          icon: outlined ? Icons.show_chart_outlined : Icons.show_chart,
          title: "loan-pay-variable".tr(),
          description: "loan-pay-variable-description".tr(),
          selected: profile.frequency == PayFrequency.variable,
          onTap: () {
            profile.frequency = PayFrequency.variable;
            changed();
          },
        ),
        if (profile.frequency != null) ...[
          const SizedBox(height: 8),
          ToolInputField(
            label: amountLabel,
            hint: "2.000.000",
            prefix: "\$ ",
            controller: amountController,
            onChanged: (value) {
              profile.amount = parseToolNumber(value)?.abs() ?? 0;
              changed();
            },
          ),
          if (averages != null && averages!.income > 0)
            _Suggestion(
              text: "loan-income-app-average".tr(namedArgs: {
                "amount": formatToolMoney(context, averages!.income),
                "months": averages!.months.toString(),
              }),
              onTap: () => useValue(
                amountController,
                profile.frequency == PayFrequency.biweekly
                    ? averages!.income / 2
                    : averages!.income,
                (value) => profile.amount = value,
              ),
            ),
          if (profile.frequency == PayFrequency.monthly)
            ToolInputField(
              label: "loan-income-payday".tr(),
              hint: "30",
              controller: paydayController,
              onChanged: (value) {
                int? day = parseToolNumber(value)?.round();
                if (day != null && day >= 1 && day <= 31) {
                  profile.payday = day;
                  changed();
                }
              },
            ),
          if (profile.isSet)
            ToolResultRow(
              label: "loan-income-monthly".tr(),
              value: formatToolMoney(context, profile.monthlyIncome),
              description: profile.frequency == PayFrequency.biweekly
                  ? "loan-income-monthly-biweekly".tr()
                  : null,
              highlight: true,
            ),
          const SizedBox(height: 6),
          ToolInputField(
            label: "loan-expenses".tr(),
            hint: "1.200.000",
            prefix: "\$ ",
            controller: expensesController,
            onChanged: (value) {
              profile.expenses = parseToolNumber(value)?.abs() ?? 0;
              changed();
            },
          ),
          if (averages != null && averages!.expenses > 0)
            _Suggestion(
              text: "loan-expenses-app-average".tr(namedArgs: {
                "amount": formatToolMoney(context, averages!.expenses),
                "months": averages!.months.toString(),
              }),
              onTap: () => useValue(expensesController, averages!.expenses,
                  (value) => profile.expenses = value),
            ),
          LoanGuide(text: "loan-guide-expenses".tr()),
          ToolInputField(
            label: "loan-other-debts".tr(),
            hint: "150.000",
            prefix: "\$ ",
            controller: otherDebtsController,
            onChanged: (value) {
              profile.otherDebts = parseToolNumber(value)?.abs() ?? 0;
              changed();
            },
          ),
          LoanGuide(text: "loan-guide-other-debts".tr()),
          ToolSectionTitle(text: "loan-payday-reminders".tr()),
          if (profile.hasFixedPay) ...[
            ToolNote(text: "loan-payday-reminders-description".tr()),
            if (profile.remindersDate != null)
              ToolNote(
                text: "loan-payday-reminders-done".tr(namedArgs: {
                  "date": getWordedDateShort(profile.remindersDate!,
                      includeYear: true),
                }),
                color: getColor(context, "incomeAmount"),
              ),
            if (profile.amount > 0)
              AnimatedOpacity(
                opacity: creatingReminders ? 0.5 : 1,
                duration: const Duration(milliseconds: 200),
                child: LoanActionButton(
                  label: "loan-payday-reminders-create".tr(),
                  icon: outlined
                      ? Icons.notification_add_outlined
                      : Icons.notification_add_rounded,
                  secondary: profile.remindersDate != null,
                  onTap: creatingReminders ? () {} : askReminders,
                ),
              )
            else
              ToolNote(text: "loan-payday-reminders-need-amount".tr()),
          ] else
            ToolNote(text: "loan-payday-reminders-variable".tr()),
        ] else
          ToolNote(text: "loan-income-pick-one".tr()),
        const SizedBox(height: 4),
        ToolNote(text: "loan-income-saved-on-device".tr()),
      ],
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Tappable(
        borderRadius: loanBoxRadius(),
        color: selected
            ? colors.secondaryContainer
            : getColor(context, "lightDarkAccent"),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(loanBoxRadius()),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected
                      ? colors.primary
                      : getColor(context, "textLight")),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(
                      text: title,
                      fontSize: 16,
                      maxLines: 2,
                      fontWeight: FontWeight.bold,
                    ),
                    TextFont(
                      text: description,
                      fontSize: 13,
                      maxLines: 3,
                      textColor: getColor(context, "textLight"),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.check_circle_rounded, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// "Según tus movimientos..." with a tap to use the value
class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Tappable(
        borderRadius: loanBoxRadius(),
        color: accent.withOpacity(0.1),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: TextFont(text: text, fontSize: 13, maxLines: 4),
              ),
              const SizedBox(width: 8),
              TextFont(
                text: "loan-use-value".tr(),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                textColor: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
