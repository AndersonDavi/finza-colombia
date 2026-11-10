import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/tags.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// A tag with a spending limit works as a budget that crosses categories: the
// trip, the motorcycle repair, a birthday. It counts the paid transactions
// carrying the tag between its dates (any date when they are not set).

bool tagHasBudget(Tag tag) => (tag.budgetAmount ?? 0) > 0;

bool insideTagBudgetDates(Tag tag, DateTime date) {
  if (tag.budgetStart != null && date.isBefore(startOfDay(tag.budgetStart!)))
    return false;
  if (tag.budgetEnd != null &&
      !date.isBefore(startOfDay(tag.budgetEnd!).add(Duration(days: 1))))
    return false;
  return true;
}

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

// Spent minus refunds, in the primary currency
double tagBudgetSpent(
    Tag tag, List<Transaction> transactions, AllWallets allWallets) {
  double total = 0;
  for (Transaction transaction in transactions) {
    if (transaction.paid != true) continue;
    if (!insideTagBudgetDates(tag, transaction.dateCreated)) continue;
    String? currency = allWallets.indexedByPk[transaction.walletFk]?.currency;
    total +=
        transaction.amount * amountRatioToPrimaryCurrency(allWallets, currency);
  }
  return -total;
}

String tagBudgetDatesLabel(Tag tag) {
  if (tag.budgetStart == null && tag.budgetEnd == null) return "all-time".tr();
  String format(DateTime date) =>
      getWordedDateShort(date, includeYear: date.year != DateTime.now().year);
  return (tag.budgetStart == null ? "…" : format(tag.budgetStart!)) +
      " – " +
      (tag.budgetEnd == null ? "…" : format(tag.budgetEnd!));
}

class TagBudgetProgress extends StatelessWidget {
  const TagBudgetProgress({required this.tag, super.key});
  final Tag tag;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return StreamBuilder<List<Transaction>>(
      stream: database.watchTransactionsWithTag(tag.tagPk),
      builder: (context, snapshot) {
        double limit = tag.budgetAmount ?? 0;
        double spent = tagBudgetSpent(tag, snapshot.data ?? [], allWallets);
        double left = limit - spent;
        double progress = limit <= 0 ? 0 : (spent / limit).clamp(0, 1);
        Color color = tagColor(context, tag);
        String money(double amount) => convertToMoney(allWallets, amount);

        String detail;
        if (left < 0) {
          detail = "tag-budget-over".tr() + " " + money(-left);
        } else {
          detail = money(left) + " " + "tag-budget-left".tr();
          DateTime today = startOfDay(DateTime.now());
          if (tag.budgetEnd != null && !today.isAfter(tag.budgetEnd!)) {
            int days = startOfDay(tag.budgetEnd!).difference(today).inDays + 1;
            if (tag.budgetStart == null || !today.isBefore(tag.budgetStart!))
              detail += " · " +
                  money(left / days) +
                  " " +
                  "tag-budget-per-day".tr() +
                  " (" +
                  days.toString() +
                  " " +
                  (days == 1 ? "day".tr() : "days".tr()) +
                  ")";
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFont(
              text: money(spent < 0 ? 0 : spent) +
                  " " +
                  "tag-budget-of".tr() +
                  " " +
                  money(limit),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: left < 0 ? getColor(context, "expenseAmount") : color,
                backgroundColor: color.withOpacity(0.15),
              ),
            ),
            SizedBox(height: 6),
            TextFont(
              text: detail,
              fontSize: 13,
              maxLines: 2,
              textColor: left < 0
                  ? getColor(context, "expenseAmount")
                  : getColor(context, "textLight"),
            ),
          ],
        );
      },
    );
  }
}

// On top of the budgets list: every tag that has a limit
class TagBudgetsSection extends StatelessWidget {
  const TagBudgetsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tag>>(
      stream: database.watchAllTags(),
      builder: (context, snapshot) {
        List<Tag> withBudget = (snapshot.data ?? [])
            .where((tag) => tagHasBudget(tag) && !tag.archived)
            .toList();
        if (withBudget.isEmpty) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 7, top: 10, bottom: 8),
                child: TextFont(
                  text: "tag-budgets".tr(),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  textColor: getColor(context, "textLight"),
                ),
              ),
              for (Tag tag in withBudget)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 10),
                  child: Tappable(
                    borderRadius: 18,
                    color: getColor(context, "lightDarkAccentHeavyLight"),
                    onTap: () => openEditTagPopup(context, tag: tag),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(tagIcon(),
                                  size: 20, color: tagColor(context, tag)),
                              SizedBox(width: 8),
                              Expanded(
                                child: TextFont(
                                  text: tag.name,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextFont(
                                text: tagBudgetDatesLabel(tag),
                                fontSize: 13,
                                textColor: getColor(context, "textLight"),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          TagBudgetProgress(tag: tag),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
