import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Savings goal of a pocket: an amount and an optional date to reach it

class PocketGoal {
  PocketGoal(this.amount, this.date);
  final double? amount;
  final DateTime? date;
}

// Progress towards the goal, what is missing and how much to set aside per
// month to make it by the date
class PocketGoalProgress {
  PocketGoalProgress(double balance, double goal, DateTime? date)
      : percent = goal <= 0 ? 0 : (balance / goal).clamp(0, 1).toDouble(),
        missing = (goal - balance) < 0 ? 0 : goal - balance,
        perMonth = date == null
            ? null
            : (goal - balance) <= 0
                ? 0
                : (goal - balance) / monthsUntil(date);
  final double percent;
  final double missing;
  final double? perMonth;

  static double monthsUntil(DateTime date) {
    double months = date.difference(DateTime.now()).inDays / 30.44;
    return months < 1 ? 1 : months;
  }
}

class PocketGoalSetting extends StatelessWidget {
  const PocketGoalSetting({
    required this.goalAmount,
    required this.goalDate,
    required this.currency,
    required this.onChanged,
    super.key,
  });
  final double? goalAmount;
  final DateTime? goalDate;
  final String? currency;
  final Function(double? amount, DateTime? date) onChanged;

  @override
  Widget build(BuildContext context) {
    String label = goalAmount == null
        ? "no-goal".tr()
        : convertToMoney(Provider.of<AllWallets>(context), goalAmount!,
                currencyKey: currency) +
            (goalDate == null ? "" : " · " + getWordedDateShort(goalDate!));
    return SettingsContainer(
      isOutlined: true,
      isWideOutlined: true,
      title: "goal".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.flag_outlined
          : Icons.flag_rounded,
      afterWidget: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: TextFont(text: label, fontSize: 14),
      ),
      onTap: () async {
        dynamic result = await openBottomSheet(
          context,
          PocketGoalPopup(
              goalAmount: goalAmount, goalDate: goalDate, currency: currency),
        );
        if (result is PocketGoal) onChanged(result.amount, result.date);
      },
    );
  }
}

class PocketGoalPopup extends StatefulWidget {
  const PocketGoalPopup(
      {this.goalAmount, this.goalDate, this.currency, super.key});
  final double? goalAmount;
  final DateTime? goalDate;
  final String? currency;

  @override
  State<PocketGoalPopup> createState() => _PocketGoalPopupState();
}

class _PocketGoalPopupState extends State<PocketGoalPopup> {
  late double amount = widget.goalAmount ?? 0;
  late DateTime? date = widget.goalDate;

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "goal".tr(),
      subtitle: "goal-description".tr(),
      child: Column(
        children: [
          SelectAmount(
            amountPassed: amount == 0 ? "" : amount.toString(),
            currencyKey: widget.currency,
            setSelectedAmount: (value, calculation) {
              setState(() => amount = value.abs());
            },
            hideNextButton: true,
          ),
          SizedBox(height: 10),
          Tappable(
            borderRadius: 12,
            color: getColor(context, "lightDarkAccentHeavyLight"),
            onTap: () async {
              DateTime? picked = await showCustomDatePicker(
                  context, date ?? DateTime.now().add(Duration(days: 180)));
              if (picked != null) setState(() => date = picked);
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(appStateSettings["outlinedIcons"]
                      ? Icons.event_outlined
                      : Icons.event_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFont(
                      text: date == null
                          ? "goal-date-optional".tr()
                          : getWordedDateShortMore(date!, includeYear: true),
                      fontSize: 16,
                    ),
                  ),
                  if (date != null)
                    IconButton(
                      onPressed: () => setState(() => date = null),
                      icon: Icon(
                        appStateSettings["outlinedIcons"]
                            ? Icons.close_outlined
                            : Icons.close_rounded,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          Button(
            label: "set-goal".tr(),
            disabled: amount <= 0,
            onTap: () => popRoute(context, PocketGoal(amount, date)),
          ),
          if (widget.goalAmount != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 8),
              child: Button(
                label: "remove-goal".tr(),
                color: Theme.of(context).colorScheme.secondaryContainer,
                textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                onTap: () => popRoute(context, PocketGoal(null, null)),
              ),
            ),
        ],
      ),
    );
  }
}

// Thin bar with the percent under a pocket card
class PocketGoalBar extends StatelessWidget {
  const PocketGoalBar({required this.wallet, required this.balance, super.key});
  final TransactionWallet wallet;
  final double balance;

  @override
  Widget build(BuildContext context) {
    if (wallet.goalAmount == null) return SizedBox.shrink();
    PocketGoalProgress progress =
        PocketGoalProgress(balance, wallet.goalAmount!, wallet.goalDate);
    Color color = HexColor(wallet.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double value) =>
        convertToMoney(allWallets, value, currencyKey: wallet.currency);
    return Tooltip(
      message: progress.missing <= 0
          ? "goal-reached".tr()
          : "missing".tr() +
              " " +
              money(progress.missing) +
              (progress.perMonth == null
                  ? ""
                  : " · " + money(progress.perMonth!) + " / " + "month".tr()),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 90,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress.percent,
                      minHeight: 5,
                      color: color,
                      backgroundColor: color.withOpacity(0.2),
                    ),
                  ),
                ),
                SizedBox(width: 6),
                TextFont(
                  text: (progress.percent * 100).round().toString() + "%",
                  fontSize: 12,
                  textColor: getColor(context, "textLight"),
                ),
              ],
            ),
            // Suggested monthly contribution to make it by the date
            if (progress.perMonth != null && progress.perMonth! > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: TextFont(
                  text: money(progress.perMonth!) + " / " + "month".tr(),
                  fontSize: 11,
                  maxLines: 1,
                  textColor: getColor(context, "textLight"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Scheduled expenses (upcoming, repetitive, subscriptions) of the next month,
// by the account they are paid from. Kept up to date from main.dart.
ValueNotifier<Map<String, double>> upcomingSpendByWallet = ValueNotifier({});

void listenToUpcomingSpend() {
  database
      .watchAllUpcomingTransactions(null,
          startDate: DateTime.now().subtract(Duration(days: 31)),
          endDate: DateTime.now().add(Duration(days: 31)),
          isIncome: false)
      .listen((transactions) {
    Map<String, double> byWallet = {};
    for (Transaction transaction in transactions) {
      byWallet[transaction.walletFk] =
          (byWallet[transaction.walletFk] ?? 0) + transaction.amount.abs();
    }
    upcomingSpendByWallet.value = byWallet;
  });
}

// On a pocket card: what is scheduled from it, in red when the balance does
// not cover it. Shows [otherwise] when nothing is scheduled.
class PocketScheduledLine extends StatelessWidget {
  const PocketScheduledLine({
    required this.wallet,
    required this.balance,
    required this.otherwise,
    super.key,
  });
  final TransactionWallet wallet;
  final double balance;
  final Widget otherwise;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: upcomingSpendByWallet,
      builder: (context, byWallet, _) {
        double scheduled = byWallet[wallet.walletPk] ?? 0;
        if (scheduled <= 0) return otherwise;
        String money(double value) => convertToMoney(
            Provider.of<AllWallets>(context), value,
            currencyKey: wallet.currency);
        bool isShort = balance < scheduled;
        return Tooltip(
          message: "scheduled-next-month".tr() + ": " + money(scheduled),
          child: TextFont(
            textAlign: TextAlign.start,
            text: isShort
                ? "missing".tr() + " " + money(scheduled - balance)
                : "scheduled".tr() + " " + money(scheduled),
            fontSize: 14,
            maxLines: 1,
            textColor: isShort
                ? getColor(context, "expenseAmount")
                : getColor(context, "black").withOpacity(0.65),
          ),
        );
      },
    );
  }
}
