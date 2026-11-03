import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Day by day bars of the last 30 days above the home transactions list:
// spending on the "all" and "expense" tabs, income on the "income" tab.
// One small query; transfers, corrections and loans left out.
class HomeSpendingChart extends StatelessWidget {
  const HomeSpendingChart({required this.income, super.key});
  final bool income;

  static const int days = 30;

  @override
  Widget build(BuildContext context) {
    DateTime today = DateTime.now().justDay();
    DateTime start = today.subtract(Duration(days: days - 1));
    final query = database.select(database.transactions)
      ..where((t) =>
          t.income.equals(income) &
          t.paid.equals(true) &
          t.categoryFk.equals("0").not() &
          t.pairedTransactionFk.isNull() &
          t.objectiveLoanFk.isNull() &
          t.dateCreated.isBiggerOrEqualValue(start) &
          t.dateCreated.isSmallerThanValue(today.add(Duration(days: 1))));
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Color color = income
        ? getColor(context, "incomeAmount")
        : getColor(context, "expenseAmount");
    return StreamBuilder<List<Transaction>>(
      stream: query.watch(),
      builder: (context, snapshot) {
        List<double> byDay = List.filled(days, 0);
        for (Transaction t in snapshot.data ?? []) {
          int index = t.dateCreated.justDay().difference(start).inDays;
          if (index < 0 || index >= days) continue;
          byDay[index] += t.amount.abs() *
              amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
        }
        double total = byDay.fold(0.0, (s, v) => s + v);
        double max = byDay.fold(0.0, (m, v) => v > m ? v : m);
        if (total == 0) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 14, end: 14, top: 4, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFont(
                      text: "last-30-days".tr(),
                      fontSize: 13,
                      textColor: getColor(context, "textLight"),
                    ),
                  ),
                  TextFont(
                    text: convertToMoney(allWallets, total.roundToDouble()),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    textColor: color,
                  ),
                ],
              ),
              SizedBox(height: 6),
              SizedBox(
                height: 46,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (int i = 0; i < days; i++)
                      Expanded(
                        child: Tooltip(
                          message: getWordedDateShort(
                                  start.add(Duration(days: i))) +
                              ": " +
                              convertToMoney(
                                  allWallets, byDay[i].roundToDouble()),
                          child: Container(
                            margin: const EdgeInsetsDirectional.symmetric(
                                horizontal: 1),
                            height: max <= 0
                                ? 2
                                : (byDay[i] / max * 46).clamp(2, 46).toDouble(),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i == days - 1
                                  ? color
                                  : color.withOpacity(byDay[i] == 0 ? 0.15 : 0.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
