import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/editWalletsPage.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/saveBottomButton.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// One page for both kinds of loan: "Presté" (the money leaves an account and
// they owe it to you) and "Me prestaron" (it comes in and you owe it).
// It is saved as a long term loan: the first record moves the money, and the
// installments, if any, are a repetitive transaction linked to the loan, so
// every payment brings the loan closer to zero.
// Loan records use the balance correction category, so lending is never
// counted as spending or income.

enum LoanFrequency { daily, weekly, biweekly, monthly }

class NewLoanPage extends StatefulWidget {
  const NewLoanPage({required this.lent, super.key});
  final bool lent;

  @override
  State<NewLoanPage> createState() => _NewLoanPageState();
}

class _NewLoanPageState extends State<NewLoanPage> {
  late bool lent = widget.lent;
  String name = "";
  double amount = 0;
  String? walletPk = appStateSettings["selectedWalletPk"];
  DateTime date = DateTime.now();
  bool installments = false;
  int installmentCount = 4;
  double? customInstallment;
  LoanFrequency frequency = LoanFrequency.monthly;
  late DateTime firstInstallment = DateTime(date.year, date.month + 1, date.day);

  double get installmentAmount =>
      customInstallment ??
      (installmentCount <= 0 ? 0 : (amount / installmentCount).roundToDouble());

  DateTime installmentDate(int index) {
    switch (frequency) {
      case LoanFrequency.daily:
        return firstInstallment.add(Duration(days: index));
      case LoanFrequency.weekly:
        return firstInstallment.add(Duration(days: 7 * index));
      case LoanFrequency.biweekly:
        return firstInstallment.add(Duration(days: 14 * index));
      case LoanFrequency.monthly:
        return DateTime(firstInstallment.year, firstInstallment.month + index,
            firstInstallment.day);
    }
  }

  String frequencyLabel(LoanFrequency f) => {
        LoanFrequency.daily: "every-day",
        LoanFrequency.weekly: "every-week",
        LoanFrequency.biweekly: "every-two-weeks",
        LoanFrequency.monthly: "every-month",
      }[f]!
          .tr();

  Future<double?> enterNumber(String title, double? initial,
      {String? currency, bool wholeNumber = false}) async {
    double? result;
    await openBottomSheet(
      context,
      fullSnap: true,
      PopupFramework(
        title: title,
        hasPadding: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: SelectAmount(
            amountPassed:
                initial == null || initial == 0 ? "" : initial.toString(),
            currencyKey: currency,
            convertToMoney: !wholeNumber,
            allowZero: false,
            setSelectedAmount: (value, calculation) => result = value.abs(),
            next: () => popRoute(context),
            nextLabel: "set-amount".tr(),
          ),
        ),
      ),
    );
    return result;
  }

  Future<void> save() async {
    TransactionWallet? wallet = Provider.of<AllWallets>(context, listen: false)
        .indexedByPk[walletPk];
    if (wallet == null || amount <= 0) return;
    int order = (await database.getTotalCountOfObjectives(
            objectiveType: ObjectiveType.loan))[0] ??
        0;
    String title = name.trim() == ""
        ? (lent ? "lent-money" : "borrowed-money").tr()
        : name.trim();
    DateTime? lastInstallment =
        installments ? installmentDate(installmentCount - 1) : null;
    int rowId = await database.createOrUpdateObjective(
      insert: true,
      Objective(
        objectivePk: "-1",
        name: title,
        colour: null,
        dateCreated: date,
        endDate: lastInstallment,
        dateTimeModified: null,
        order: order,
        emojiIconName: null,
        iconName: null,
        // Long term loans keep zero here, their records carry the amount
        amount: 0,
        income: lent,
        pinned: true,
        walletFk: wallet.walletPk,
        archived: false,
        type: ObjectiveType.loan,
      ),
    );
    Objective loan = await database.getObjectiveFromRowId(rowId);
    await database.createOrUpdateTransaction(
      insert: true,
      Transaction(
        transactionPk: "-1",
        name: title,
        note: "",
        amount: amount * (lent ? -1 : 1),
        categoryFk: "0",
        walletFk: wallet.walletPk,
        dateCreated: date,
        income: !lent,
        paid: true,
        skipPaid: false,
        type: null,
        objectiveLoanFk: loan.objectivePk,
      ),
    );
    if (installments && installmentAmount > 0) {
      await database.createOrUpdateTransaction(
        insert: true,
        Transaction(
          transactionPk: "-1",
          name: "loan-installment".tr() + " · " + title,
          note: "",
          amount: installmentAmount * (lent ? 1 : -1),
          categoryFk: "0",
          walletFk: wallet.walletPk,
          dateCreated: firstInstallment,
          endDate: lastInstallment,
          income: lent,
          paid: false,
          skipPaid: false,
          type: TransactionSpecialType.repetitive,
          reoccurrence: frequency == LoanFrequency.daily
              ? BudgetReoccurence.daily
              : frequency == LoanFrequency.monthly
                  ? BudgetReoccurence.monthly
                  : BudgetReoccurence.weekly,
          periodLength: frequency == LoanFrequency.biweekly ? 2 : 1,
          createdAnotherFutureTransaction: false,
          objectiveLoanFk: loan.objectivePk,
        ),
      );
    }
    savingHapticFeedback();
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    TransactionWallet? wallet = allWallets.indexedByPk[walletPk];
    String money(double value) =>
        convertToMoney(allWallets, value, currencyKey: wallet?.currency);
    Color lentColor = getColor(context, "unPaidUpcoming");
    Color borrowedColor = getColor(context, "unPaidOverdue");
    Color color = lent ? lentColor : borrowedColor;

    Widget kind(bool isLent, String label, String description, IconData icon) {
      bool selected = lent == isLent;
      Color kindColor = isLent ? lentColor : borrowedColor;
      return Expanded(
        child: Tappable(
          borderRadius: 16,
          color: selected
              ? kindColor.withOpacity(0.18)
              : getColor(context, "lightDarkAccentHeavyLight"),
          onTap: () => setState(() => lent = isLent),
          child: Container(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? kindColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: kindColor),
                SizedBox(height: 6),
                TextFont(text: label, fontSize: 17, fontWeight: FontWeight.bold),
                SizedBox(height: 2),
                TextFont(
                  text: description,
                  fontSize: 13,
                  maxLines: 3,
                  textColor: getColor(context, "textLight"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget field(IconData icon, String label, String value, VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Tappable(
            borderRadius: 14,
            color: getColor(context, "lightDarkAccentHeavyLight"),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: getColor(context, "textLight")),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFont(
                      text: label,
                      fontSize: 15,
                      textColor: getColor(context, "textLight"),
                    ),
                  ),
                  Flexible(
                    child: TextFont(
                      text: value,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return PageFramework(
      title: "new-loan".tr(),
      dragDownToDismiss: true,
      staticOverlay: Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: SaveBottomButton(
          label: "save-loan".tr(),
          disabled: amount <= 0 || wallet == null,
          onTap: save,
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 620,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      kind(
                        true,
                        "lent-money".tr(),
                        "lent-money-description".tr(),
                        Icons.north_east_rounded,
                      ),
                      SizedBox(width: 10),
                      kind(
                        false,
                        "borrowed-money".tr(),
                        "borrowed-money-description".tr(),
                        Icons.south_west_rounded,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  TextInput(
                    labelText:
                        (lent ? "loan-who-lent" : "loan-who-borrowed").tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.person_outlined
                        : Icons.person_rounded,
                    onChanged: (value) => setState(() => name = value),
                    padding: EdgeInsetsDirectional.zero,
                  ),
                  SizedBox(height: 10),
                  field(
                    Icons.payments_rounded,
                    "amount".tr(),
                    amount <= 0 ? "—" : money(amount),
                    () async {
                      double? value = await enterNumber("amount".tr(), amount,
                          currency: wallet?.currency);
                      if (value != null) setState(() => amount = value);
                    },
                  ),
                  field(
                    Icons.account_balance_wallet_rounded,
                    (lent ? "loan-account-lent" : "loan-account-borrowed").tr(),
                    wallet == null ? "—" : getWalletStringName(allWallets, wallet),
                    () async {
                      TransactionWallet? picked = await selectWalletPopup(
                        context,
                        allowEditWallet: false,
                        selectedWallet: wallet,
                      );
                      if (picked != null)
                        setState(() => walletPk = picked.walletPk);
                    },
                  ),
                  field(
                    Icons.event_rounded,
                    "date".tr(),
                    getWordedDateShort(date),
                    () async {
                      DateTime? picked =
                          await showCustomDatePicker(context, date);
                      if (picked != null) setState(() => date = picked);
                    },
                  ),
                  SizedBox(height: 8),
                  SettingsContainerSwitch(
                    enableBorderRadius: true,
                    title: (lent ? "installments-lent" : "installments-borrowed")
                        .tr(),
                    description: "installments-description".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.calendar_view_week_outlined
                        : Icons.calendar_view_week_rounded,
                    initialValue: installments,
                    onSwitched: (value) =>
                        setState(() => installments = value),
                  ),
                  if (installments) ...[
                    SizedBox(height: 8),
                    field(
                      Icons.numbers_rounded,
                      "number-of-installments".tr(),
                      installmentCount.toString(),
                      () async {
                        double? value = await enterNumber(
                            "number-of-installments".tr(),
                            installmentCount.toDouble(),
                            wholeNumber: true);
                        if (value != null && value >= 1)
                          setState(() {
                            installmentCount = value.round();
                            customInstallment = null;
                          });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (LoanFrequency f in LoanFrequency.values)
                            ChoiceChip(
                              label: Text(frequencyLabel(f)),
                              selected: frequency == f,
                              onSelected: (_) => setState(() => frequency = f),
                            ),
                        ],
                      ),
                    ),
                    field(
                      Icons.price_change_rounded,
                      "installment-amount".tr(),
                      money(installmentAmount),
                      () async {
                        double? value = await enterNumber(
                            "installment-amount".tr(), installmentAmount,
                            currency: wallet?.currency);
                        if (value != null)
                          setState(() => customInstallment = value);
                      },
                    ),
                    field(
                      Icons.event_repeat_rounded,
                      "first-installment".tr(),
                      getWordedDateShort(firstInstallment),
                      () async {
                        DateTime? picked =
                            await showCustomDatePicker(context, firstInstallment);
                        if (picked != null)
                          setState(() => firstInstallment = picked);
                      },
                    ),
                  ],
                  if (amount > 0)
                    Container(
                      margin: const EdgeInsetsDirectional.only(top: 8),
                      padding: const EdgeInsetsDirectional.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: color.withOpacity(0.12),
                      ),
                      child: TextFont(
                        text: (lent ? "loan-summary-lent" : "loan-summary-borrowed")
                                .tr(namedArgs: {
                              "amount": money(amount),
                              "account": wallet == null
                                  ? ""
                                  : getWalletStringName(allWallets, wallet),
                            }) +
                            (installments
                                ? " " +
                                    "installments-summary".tr(namedArgs: {
                                      "count": installmentCount.toString(),
                                      "amount": money(installmentAmount),
                                      "every": frequencyLabel(frequency)
                                          .toLowerCase(),
                                      "first": getWordedDateShort(
                                          firstInstallment),
                                      "last": getWordedDateShort(
                                          installmentDate(installmentCount - 1),
                                          includeYear: true),
                                    })
                                : ""),
                        fontSize: 14,
                        maxLines: 6,
                      ),
                    ),
                  SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// What they owe you and what you owe, one time and long term loans together.
// [compact] is the single line under the net worth on the home page.
class LoansBalanceSummary extends StatelessWidget {
  const LoansBalanceSummary({this.compact = false, super.key});
  final bool compact;

  Stream<TotalWithCount?> main(AllWallets allWallets, bool isCredit) =>
      database.watchTotalWithCountOfCreditDebt(
          allWallets: allWallets,
          isCredit: isCredit,
          cycleSettingsExtension: null,
          selectedTab: null);

  Stream<TotalWithCount?> offset(AllWallets allWallets, bool isCredit) =>
      database.watchTotalWithCountOfCreditDebtLongTermLoansOffset(
          allWallets: allWallets,
          isCredit: isCredit,
          cycleSettingsExtension: null,
          selectedTab: null);

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Widget total(bool isCredit, Widget Function(double) builder) =>
        StreamBuilder<TotalWithCount?>(
          stream: main(allWallets, isCredit),
          builder: (context, first) => StreamBuilder<TotalWithCount?>(
            stream: offset(allWallets, isCredit),
            builder: (context, second) => builder(
                (first.data?.total ?? 0) + (second.data?.total ?? 0)),
          ),
        );
    return total(
      true,
      (creditTotal) => total(false, (debtTotal) {
        // Lent money is negative while it is out, borrowed is positive
        double receivable = creditTotal < 0 ? -creditTotal : 0;
        double payable = debtTotal > 0 ? debtTotal : 0;
        if (compact) {
          if (receivable == 0 && payable == 0) return SizedBox.shrink();
          return Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Wrap(
              spacing: 12,
              children: [
                if (receivable > 0)
                  TextFont(
                    text: "receivable".tr() +
                        " " +
                        convertToMoney(allWallets, receivable),
                    fontSize: 13,
                    textColor: getColor(context, "unPaidUpcoming"),
                  ),
                if (payable > 0)
                  TextFont(
                    text: "payable".tr() +
                        " " +
                        convertToMoney(allWallets, payable),
                    fontSize: 13,
                    textColor: getColor(context, "unPaidOverdue"),
                  ),
              ],
            ),
          );
        }
        Widget tile(String label, double value, Color color) => Expanded(
              child: Container(
                padding: const EdgeInsetsDirectional.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: color.withOpacity(0.12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(
                      text: label,
                      fontSize: 14,
                      textColor: getColor(context, "textLight"),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: TextFont(
                        text: convertToMoney(allWallets, value),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        textColor: color,
                      ),
                    ),
                  ],
                ),
              ),
            );
        return Row(
          children: [
            tile("receivable".tr(), receivable,
                getColor(context, "unPaidUpcoming")),
            SizedBox(width: 10),
            tile("payable".tr(), payable, getColor(context, "unPaidOverdue")),
          ],
        );
      }),
    );
  }
}
