import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/editObjectivesPage.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/editWalletsPage.dart';
import 'package:budget/pages/objectivePage.dart';
import 'package:budget/pages/objectivesListPage.dart';
import 'package:budget/pages/tools/loanWidgets.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Loans the person is paying, read from Cashew's loan objectives: borrowed
// loans ("Me prestaron") that are not archived. The installment is the
// pending repeating transaction linked to the loan, the same one the loan
// page creates, so loans added there count here too.

class ActiveLoan {
  const ActiveLoan({
    required this.objective,
    this.installment,
    this.monthlyInstallment = 0,
    this.remainingMonths,
  });
  final Objective objective;
  // Next pending installment, null when the loan has none
  final Transaction? installment;
  // Installment converted to a month and to the primary currency
  final double monthlyInstallment;
  final int? remainingMonths;
}

// A repeating amount spread over one month
double monthlyEquivalent(Transaction transaction) {
  double amount = transaction.amount.abs();
  int period =
      (transaction.periodLength ?? 1) <= 0 ? 1 : transaction.periodLength ?? 1;
  switch (transaction.reoccurrence) {
    case BudgetReoccurence.daily:
      return amount * 365 / 12 / period;
    case BudgetReoccurence.weekly:
      return amount * 52 / 12 / period;
    case BudgetReoccurence.yearly:
      return amount / 12 / period;
    case BudgetReoccurence.monthly:
    case BudgetReoccurence.custom:
    case null:
      return amount / period;
  }
}

Stream<List<Transaction>> _watchPendingLoanInstallments() {
  return (database.select(database.transactions)
        ..where((t) =>
            t.objectiveLoanFk.isNotNull() &
            t.paid.equals(false) &
            t.skipPaid.equals(false) &
            t.income.equals(false) &
            t.type.isInValues([
              TransactionSpecialType.repetitive,
              TransactionSpecialType.subscription,
            ]))
        ..orderBy([(t) => OrderingTerm.asc(t.dateCreated)]))
      .watch();
}

class ActiveLoansBuilder extends StatefulWidget {
  const ActiveLoansBuilder({required this.builder, super.key});
  final Widget Function(BuildContext context, List<ActiveLoan> loans) builder;

  @override
  State<ActiveLoansBuilder> createState() => _ActiveLoansBuilderState();
}

class _ActiveLoansBuilderState extends State<ActiveLoansBuilder> {
  // Kept so rebuilds of the page do not subscribe again
  late final Stream<List<Objective>> objectives = database.watchAllObjectives(
    objectiveType: ObjectiveType.loan,
    isIncome: false,
    hideArchived: true,
  );
  late final Stream<List<Transaction>> installments =
      _watchPendingLoanInstallments();

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return StreamBuilder<List<Objective>>(
      stream: objectives,
      builder: (context, objectivesSnapshot) {
        return StreamBuilder<List<Transaction>>(
          stream: installments,
          builder: (context, installmentsSnapshot) {
            Map<String, Transaction> next = {};
            for (Transaction transaction in installmentsSnapshot.data ?? []) {
              next.putIfAbsent(transaction.objectiveLoanFk!, () => transaction);
            }
            List<ActiveLoan> loans = [];
            for (Objective objective in objectivesSnapshot.data ?? []) {
              Transaction? installment = next[objective.objectivePk];
              int? remaining;
              double monthly = 0;
              if (installment != null) {
                monthly = monthlyEquivalent(installment) *
                    amountRatioToPrimaryCurrency(allWallets,
                        allWallets.indexedByPk[installment.walletFk]?.currency);
                if (installment.endDate != null &&
                    installment.reoccurrence == BudgetReoccurence.monthly &&
                    (installment.periodLength ?? 1) == 1) {
                  remaining = remainingMonthlyInstallments(
                      installment.dateCreated, installment.endDate!);
                }
              }
              loans.add(ActiveLoan(
                objective: objective,
                installment: installment,
                monthlyInstallment: monthly,
                remainingMonths: remaining,
              ));
            }
            return widget.builder(context, loans);
          },
        );
      },
    );
  }
}

double totalMonthlyInstallments(List<ActiveLoan> loans) =>
    loans.fold(0, (sum, loan) => sum + loan.monthlyInstallment);

// Creates a borrowed loan objective and its monthly installment reminder.
// The installment is a repeating transaction that starts unpaid: it shows
// as pending and is only marked paid when the person confirms it.
// [disbursed] records the money coming into the wallet; the rest of
// [totalToPay] (interest, fees, or everything when nothing is recorded) is
// kept as the loan's amount offset, so the loan page shows the full debt.
// Loan records use the balance correction category, as in NewLoanPage, so
// they never count as income or spending
Future<String> createTrackedLoan({
  required String name,
  required String walletPk,
  required double installment,
  required int months,
  required DateTime firstInstallment,
  required double totalToPay,
  double disbursed = 0,
  String note = "",
}) async {
  // Loan records use the balance correction category, which a fresh
  // install may not have yet
  await initializeBalanceCorrectionCategory();
  DateTime lastInstallment = addMonthsClamped(firstInstallment, months - 1);
  int order = (await database.getTotalCountOfObjectives(
          objectiveType: ObjectiveType.loan))[0] ??
      0;
  double offset = totalToPay - disbursed;
  // -1 means a difference only loan, never store it by chance
  if (offset == -1) offset = -1.01;
  int rowId = await database.createOrUpdateObjective(
    insert: true,
    Objective(
      objectivePk: "-1",
      name: name,
      colour: null,
      dateCreated: DateTime.now(),
      endDate: lastInstallment,
      dateTimeModified: null,
      order: order,
      emojiIconName: null,
      iconName: null,
      amount: 0,
      income: false,
      pinned: true,
      walletFk: walletPk,
      archived: false,
      type: ObjectiveType.loan,
    ),
  );
  Objective loan = await database.getObjectiveFromRowId(rowId);
  // New loans are always inserted with a zero offset, set it afterwards
  if (offset != 0) {
    loan = loan.copyWith(amount: offset);
    await database.createOrUpdateObjective(loan);
  }
  if (disbursed > 0) {
    await database.createOrUpdateTransaction(
      insert: true,
      Transaction(
        transactionPk: "-1",
        name: name,
        note: note,
        amount: disbursed.abs(),
        categoryFk: "0",
        walletFk: walletPk,
        dateCreated: DateTime.now(),
        income: true,
        paid: true,
        skipPaid: false,
        type: null,
        objectiveLoanFk: loan.objectivePk,
      ),
    );
  }
  await database.createOrUpdateTransaction(
    insert: true,
    Transaction(
      transactionPk: "-1",
      name: "loan-installment".tr() + " · " + name,
      note: note,
      amount: -installment.abs(),
      categoryFk: "0",
      walletFk: walletPk,
      dateCreated: firstInstallment,
      // A few days of margin: the next date of a repeating transaction can
      // move forward when it starts on the 29th to 31st
      endDate: lastInstallment.add(const Duration(days: 4)),
      income: false,
      paid: false,
      skipPaid: false,
      type: TransactionSpecialType.repetitive,
      reoccurrence: BudgetReoccurence.monthly,
      periodLength: 1,
      upcomingTransactionNotification: true,
      createdAnotherFutureTransaction: false,
      objectiveLoanFk: loan.objectivePk,
    ),
  );
  return loan.objectivePk;
}

String _loanName(String name, String entity) {
  String title = name.trim() == "" ? "loan-default-name".tr() : name.trim();
  return entity.trim() == "" ? title : title + " · " + entity.trim();
}

void _openSavedLoan(String objectivePk) {
  savingHapticFeedback();
  openSnackbar(SnackbarMessage(
    title: "loan-saved".tr(),
    description: "loan-saved-description".tr(),
    icon: appStateSettings["outlinedIcons"]
        ? Icons.check_circle_outline
        : Icons.check_circle_rounded,
    onTap: () => pushRoute(null, ObjectivePage(objectivePk: objectivePk)),
  ));
}

// "Mis préstamos" tab
class ActiveLoansSection extends StatelessWidget {
  const ActiveLoansSection({required this.otherDebts, super.key});
  // Installments typed in "Mis ingresos" that are not registered loans
  final double otherDebts;

  @override
  Widget build(BuildContext context) {
    bool outlined = appStateSettings["outlinedIcons"] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolNote(text: "loan-active-intro".tr()),
        ActiveLoansBuilder(builder: (context, loans) {
          double total = totalMonthlyInstallments(loans);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolResultRow(
                label: "loan-active-total".tr(),
                value: formatToolMoney(context, total + otherDebts),
                description: otherDebts > 0
                    ? "loan-active-total-with-other".tr(namedArgs: {
                        "loans": formatToolMoney(context, total),
                        "other": formatToolMoney(context, otherDebts),
                      })
                    : "loan-active-count"
                        .tr(namedArgs: {"count": loans.length.toString()}),
                highlight: true,
              ),
              if (loans.isEmpty)
                ToolNote(text: "loan-active-empty".tr())
              else
                for (ActiveLoan loan in loans) _ActiveLoanCard(loan: loan),
            ],
          );
        }),
        const SizedBox(height: 6),
        LoanActionButton(
          label: "loan-register-existing".tr(),
          icon: outlined ? Icons.add_card_outlined : Icons.add_card_rounded,
          onTap: () => openBottomSheet(
            context,
            fullSnap: true,
            PopupFramework(
              title: "loan-register-existing".tr(),
              child: const _RegisterLoanForm(),
            ),
          ),
        ),
        LoanActionButton(
          label: "loan-see-all-loans".tr(),
          icon: outlined ? Icons.list_alt_outlined : Icons.list_alt_rounded,
          secondary: true,
          onTap: () => pushRoute(
              context, EditObjectivesPage(objectiveType: ObjectiveType.loan)),
        ),
        LoanGuide(
          title: "loan-guide-why-register-title".tr(),
          text: "loan-guide-why-register".tr(),
        ),
      ],
    );
  }
}

class _ActiveLoanCard extends StatelessWidget {
  const _ActiveLoanCard({required this.loan});
  final ActiveLoan loan;

  @override
  Widget build(BuildContext context) {
    String note = loan.installment?.note.trim() ?? "";
    List<String> details = [
      loan.installment == null
          ? "loan-active-no-installment".tr()
          : "loan-active-installment".tr(namedArgs: {
              "amount": formatToolMoney(context, loan.monthlyInstallment),
            }),
      if (loan.remainingMonths != null)
        "loan-active-remaining"
            .tr(namedArgs: {"months": loan.remainingMonths.toString()}),
      if (note != "") note,
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Tappable(
        borderRadius: loanBoxRadius(),
        color: getColor(context, "lightDarkAccent"),
        onTap: () => pushRoute(
            context, ObjectivePage(objectivePk: loan.objective.objectivePk)),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16, vertical: 12),
          child: WatchTotalAndAmountOfObjective(
            objective: loan.objective,
            builder: (objectiveAmount, totalAmount, percentage) {
              double left = (objectiveAmount - totalAmount).clamp(0, 1e15);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFont(
                          text: loan.objective.name,
                          fontSize: 16,
                          maxLines: 2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_right_rounded,
                          color: getColor(context, "textLight")),
                    ],
                  ),
                  const SizedBox(height: 2),
                  TextFont(
                    text: details.join(" · "),
                    fontSize: 13,
                    maxLines: 3,
                    textColor: getColor(context, "textLight"),
                  ),
                  if (objectiveAmount > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: percentage.clamp(0, 1).toDouble(),
                        minHeight: 7,
                        backgroundColor:
                            getColor(context, "lightDarkAccentHeavyLight"),
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextFont(
                      text: "loan-active-left".tr(namedArgs: {
                        "amount": formatToolMoney(context, left),
                      }),
                      fontSize: 13,
                      maxLines: 2,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// Fields shared by both forms: wallet and first installment date
mixin _LoanFormFields<T extends StatefulWidget> on State<T> {
  late String walletPk =
      appStateSettings["selectedWalletPk"]?.toString() ?? "0";
  bool saving = false;

  Widget walletRow(BuildContext context, AllWallets allWallets) {
    TransactionWallet? wallet = allWallets.indexedByPk[walletPk];
    return LoanPickerRow(
      icon: appStateSettings["outlinedIcons"]
          ? Icons.account_balance_wallet_outlined
          : Icons.account_balance_wallet_rounded,
      label: "loan-wallet".tr(),
      value: wallet == null ? "—" : getWalletStringName(allWallets, wallet),
      onTap: () async {
        TransactionWallet? picked = await selectWalletPopup(
          context,
          allowEditWallet: false,
          selectedWallet: wallet,
        );
        if (picked != null) setState(() => walletPk = picked.walletPk);
      },
    );
  }

  Widget dateRow(BuildContext context, String label, DateTime date,
      ValueChanged<DateTime> onPicked) {
    return LoanPickerRow(
      icon: appStateSettings["outlinedIcons"]
          ? Icons.event_outlined
          : Icons.event_rounded,
      label: label,
      value: getWordedDateShort(date, includeYear: true),
      onTap: () async {
        DateTime? picked = await showCustomDatePicker(context, date);
        if (picked != null) {
          onPicked(DateTime(picked.year, picked.month, picked.day));
        }
      },
    );
  }

  Widget summaryBox(BuildContext context, String text) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(loanBoxRadius()),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: TextFont(text: text, fontSize: 14, maxLines: 12),
    );
  }

  Future<void> finish(BuildContext context, Future<String> Function() create,
      {VoidCallback? onSaved}) async {
    if (saving) return;
    setState(() => saving = true);
    String objectivePk;
    try {
      objectivePk = await create();
    } catch (e) {
      if (mounted) setState(() => saving = false);
      openSnackbar(SnackbarMessage(
        title: "loan-save-error".tr(),
        description: e.toString().tr(),
        icon: Icons.warning_rounded,
      ));
      return;
    }
    if (context.mounted) await setUpcomingNotifications(context);
    if (!context.mounted) return;
    popRoute(context);
    _openSavedLoan(objectivePk);
    onSaved?.call();
  }
}

class _RegisterLoanForm extends StatefulWidget {
  const _RegisterLoanForm();

  @override
  State<_RegisterLoanForm> createState() => _RegisterLoanFormState();
}

class _RegisterLoanFormState extends State<_RegisterLoanForm>
    with _LoanFormFields {
  String name = "";
  String entity = "";
  final TextEditingController installmentController = TextEditingController();
  final TextEditingController monthsController = TextEditingController();
  final TextEditingController rateController = TextEditingController();
  DateTime next = addMonthsClamped(DateTime.now(), 1);

  @override
  void dispose() {
    installmentController.dispose();
    monthsController.dispose();
    rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    double installment =
        parseToolNumber(installmentController.text)?.abs() ?? 0;
    int months = parseToolNumber(monthsController.text)?.round() ?? 0;
    double? rate = parseColombianNumber(rateController.text);
    bool valid = installment > 0 && months >= 1 && months <= 600;
    String note = rate == null || rate <= 0
        ? ""
        : "loan-rate-note".tr(namedArgs: {
            "rate": formatToolPercent(rate / 100),
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInput(
          labelText: "loan-name".tr(),
          padding: const EdgeInsetsDirectional.only(bottom: 10),
          onChanged: (value) => setState(() => name = value),
        ),
        TextInput(
          labelText: "loan-entity".tr(),
          padding: const EdgeInsetsDirectional.only(bottom: 12),
          onChanged: (value) => setState(() => entity = value),
        ),
        ToolInputField(
          label: "loan-existing-installment".tr(),
          hint: "350.000",
          prefix: "\$ ",
          controller: installmentController,
          onChanged: (_) => setState(() {}),
        ),
        ToolInputField(
          label: "loan-existing-months".tr(),
          hint: "24",
          controller: monthsController,
          onChanged: (_) => setState(() {}),
        ),
        ToolInputField(
          label: "loan-existing-rate".tr(),
          hint: "24",
          suffix: "% EA",
          controller: rateController,
          onChanged: (_) => setState(() {}),
        ),
        dateRow(context, "loan-next-installment".tr(), next,
            (date) => setState(() => next = date)),
        walletRow(context, allWallets),
        if (valid)
          summaryBox(
            context,
            "loan-register-summary".tr(namedArgs: {
              "installment": formatToolMoney(context, installment),
              "count": months.toString(),
              "first": getWordedDateShort(next, includeYear: true),
              "last": getWordedDateShort(addMonthsClamped(next, months - 1),
                  includeYear: true),
              "total": formatToolMoney(context, installment * months),
            }),
          ),
        LoanActionButton(
          label: "save-loan".tr(),
          icon: Icons.check_rounded,
          onTap: valid == false
              ? () => openSnackbar(SnackbarMessage(
                    title: "loan-register-fill".tr(),
                    icon: Icons.info_outline_rounded,
                  ))
              : () => finish(
                    context,
                    () => createTrackedLoan(
                      name: _loanName(name, entity),
                      walletPk: walletPk,
                      installment: installment,
                      months: months,
                      firstInstallment: next,
                      totalToPay: installment * months,
                      note: note,
                    ),
                  ),
        ),
      ],
    );
  }
}

// Turns a simulation into a tracked loan. [plan] is the loan without the
// simulated extra payments: those are only saved when they are made
Future<void> openSaveSimulatedLoan(
  BuildContext context, {
  required LoanResult plan,
  required DateTime firstInstallment,
  required String rateNote,
  required bool variableInstallment,
  required bool hadExtraPayments,
  VoidCallback? onSaved,
}) {
  return openBottomSheet(
    context,
    fullSnap: true,
    PopupFramework(
      title: "loan-save-simulation".tr(),
      child: _SaveSimulationForm(
        plan: plan,
        firstInstallment: firstInstallment,
        rateNote: rateNote,
        variableInstallment: variableInstallment,
        hadExtraPayments: hadExtraPayments,
        onSaved: onSaved,
      ),
    ),
  );
}

class _SaveSimulationForm extends StatefulWidget {
  const _SaveSimulationForm({
    required this.plan,
    required this.firstInstallment,
    required this.rateNote,
    required this.variableInstallment,
    required this.hadExtraPayments,
    this.onSaved,
  });
  final LoanResult plan;
  final DateTime firstInstallment;
  final String rateNote;
  final bool variableInstallment;
  final bool hadExtraPayments;
  final VoidCallback? onSaved;

  @override
  State<_SaveSimulationForm> createState() => _SaveSimulationFormState();
}

class _SaveSimulationFormState extends State<_SaveSimulationForm>
    with _LoanFormFields {
  String name = "";
  String entity = "";
  bool recordDisbursement = true;
  late DateTime first = widget.firstInstallment;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    LoanResult plan = widget.plan;
    TransactionWallet? wallet = allWallets.indexedByPk[walletPk];
    String walletName =
        wallet == null ? "" : getWalletStringName(allWallets, wallet);
    String summary = "loan-save-summary".tr(namedArgs: {
          "total": formatToolMoney(context, plan.totalPaid),
          "installment": formatToolMoney(context, plan.firstInstallment),
          "count": plan.months.toString(),
          "first": getWordedDateShort(first, includeYear: true),
          "last": getWordedDateShort(addMonthsClamped(first, plan.months - 1),
              includeYear: true),
        }) +
        (recordDisbursement
            ? "\n\n" +
                "loan-save-summary-disbursement".tr(namedArgs: {
                  "amount": formatToolMoney(context, plan.amount),
                  "wallet": walletName,
                })
            : "") +
        (widget.variableInstallment
            ? "\n\n" + "loan-save-variable-installment".tr()
            : "") +
        (widget.hadExtraPayments
            ? "\n\n" + "loan-save-extra-not-saved".tr()
            : "");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LoanDisclaimer(),
        TextInput(
          labelText: "loan-name".tr(),
          padding: const EdgeInsetsDirectional.only(bottom: 10),
          onChanged: (value) => setState(() => name = value),
        ),
        TextInput(
          labelText: "loan-entity".tr(),
          padding: const EdgeInsetsDirectional.only(bottom: 12),
          onChanged: (value) => setState(() => entity = value),
        ),
        dateRow(context, "loan-first-installment".tr(), first,
            (date) => setState(() => first = date)),
        walletRow(context, allWallets),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 10),
          child: Tappable(
            borderRadius: loanBoxRadius(),
            color: getColor(context, "lightDarkAccent"),
            onTap: () =>
                setState(() => recordDisbursement = !recordDisbursement),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                  start: 16, end: 8, top: 8, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFont(
                          text: "loan-record-disbursement".tr(),
                          fontSize: 15,
                          maxLines: 2,
                          fontWeight: FontWeight.bold,
                        ),
                        TextFont(
                          text: "loan-record-disbursement-description".tr(),
                          fontSize: 13,
                          maxLines: 4,
                          textColor: getColor(context, "textLight"),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: recordDisbursement,
                    onChanged: (value) =>
                        setState(() => recordDisbursement = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        summaryBox(context, summary),
        LoanActionButton(
          label: "save-loan".tr(),
          icon: Icons.check_rounded,
          onTap: () => finish(
            context,
            () => createTrackedLoan(
              name: _loanName(name, entity),
              walletPk: walletPk,
              installment: plan.firstInstallment,
              months: plan.months,
              firstInstallment: first,
              totalToPay: plan.totalPaid,
              disbursed: recordDisbursement ? plan.amount : 0,
              note: widget.rateNote,
            ),
            onSaved: widget.onSaved,
          ),
        ),
      ],
    );
  }
}

// Summary for the loan page of a borrowed loan with a monthly installment:
// "Cuota mensual $311.077 · Llevas 3 de 36 cuotas · terminas el ...".
// Other objectives, and loans without a monthly installment, show
// [fallback], the usual date range and daily amount.
class LoanObjectiveSummary extends StatefulWidget {
  const LoanObjectiveSummary(
      {required this.objective, required this.fallback, super.key});
  final Objective objective;
  final Widget fallback;

  @override
  State<LoanObjectiveSummary> createState() => _LoanObjectiveSummaryState();
}

class _LoanObjectiveSummaryState extends State<LoanObjectiveSummary> {
  late final Stream<List<Transaction>> records = (database
          .select(database.transactions)
        ..where((t) => t.objectiveLoanFk.equals(widget.objective.objectivePk))
        ..orderBy([(t) => OrderingTerm.asc(t.dateCreated)]))
      .watch();

  @override
  Widget build(BuildContext context) {
    if (widget.objective.type != ObjectiveType.loan ||
        widget.objective.income) {
      return widget.fallback;
    }
    return StreamBuilder<List<Transaction>>(
      stream: records,
      builder: (context, snapshot) {
        List<Transaction> all = snapshot.data ?? [];
        Transaction? next = all
            .where((t) =>
                t.paid == false &&
                t.skipPaid == false &&
                t.income == false &&
                t.reoccurrence == BudgetReoccurence.monthly &&
                (t.periodLength ?? 1) == 1 &&
                (t.type == TransactionSpecialType.repetitive ||
                    t.type == TransactionSpecialType.subscription))
            .firstOrNull;
        if (next == null) return widget.fallback;
        int paid = all
            .where((t) => t.paid && t.income == false && t.amount < 0)
            .length;
        double disbursed = all
            .where((t) => t.paid && t.income && t.amount > 0)
            .fold(0.0, (sum, t) => sum + t.amount);
        DateTime? last = widget.objective.endDate ??
            next.endDate?.subtract(const Duration(days: 4));
        int? left = last == null
            ? null
            : remainingMonthlyInstallments(next.dateCreated, last);
        String lastText =
            last == null ? "" : getWordedDateShort(last, includeYear: true);
        String progress;
        if (left == null) {
          progress = "loan-page-next"
              .tr(namedArgs: {"date": getWordedDateShort(next.dateCreated)});
        } else if (paid > 0) {
          progress = "loan-page-installments-progress".tr(namedArgs: {
            "paid": paid.toString(),
            "total": (paid + left).toString(),
            "date": lastText,
          });
        } else {
          progress = "loan-page-installments-left".tr(namedArgs: {
            "count": left.toString(),
            "date": lastText,
          });
        }
        return Column(
          children: [
            TextFont(
              text: "loan-page-installment".tr(namedArgs: {
                "amount": convertToMoney(
                    Provider.of<AllWallets>(context), next.amount.abs()),
              }),
              maxLines: 3,
              textAlign: TextAlign.center,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
            const SizedBox(height: 8),
            TextFont(
              text: progress,
              maxLines: 3,
              textAlign: TextAlign.center,
              fontSize: 16,
            ),
            if (left != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 4),
                child: TextFont(
                  text: "loan-page-next".tr(namedArgs: {
                    "date":
                        getWordedDateShort(next.dateCreated, includeYear: true),
                  }),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  fontSize: 15,
                  textColor: getColor(context, "textLight"),
                ),
              ),
            const SizedBox(height: 10),
            TextFont(
              text: (disbursed > 0
                      ? "loan-page-disbursement-note".tr(namedArgs: {
                            "amount": convertToMoney(
                                Provider.of<AllWallets>(context), disbursed),
                          }) +
                          " "
                      : "") +
                  "loan-page-confirm-note".tr(),
              maxLines: 6,
              textAlign: TextAlign.center,
              fontSize: 14,
              textColor: getColor(context, "textLight"),
            ),
          ],
        );
      },
    );
  }
}
