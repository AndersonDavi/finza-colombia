import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/fab.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntries.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Month grid with the net total of every day, the transactions of the selected
// day are listed under it
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => CalendarPageState();
}

class CalendarPageState extends State<CalendarPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();
  String pageId = "Calendar";
  DateTime selectedMonth = DateTime.now().firstDayOfMonth();
  DateTime selectedDay = DateTime.now().justDay();

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  void changeMonth(int offset) {
    setState(() {
      selectedMonth =
          DateTime(selectedMonth.year, selectedMonth.month + offset, 1);
      DateTime now = DateTime.now();
      selectedDay = selectedMonth.year == now.year &&
              selectedMonth.month == now.month
          ? now.justDay()
          : selectedMonth;
    });
  }

  @override
  Widget build(BuildContext context) {
    DateTime dayEnd = DateTime(
        selectedDay.year, selectedDay.month, selectedDay.day, 23, 59, 59);
    return PageFramework(
      key: pageState,
      title: "calendar".tr(),
      backButton: false,
      dragDownToDismiss: true,
      listID: pageId,
      floatingActionButton: AnimateFABDelayed(
        fab: AddFAB(
          tooltip: "add-transaction".tr(),
          openPage: AddTransactionPage(
            routesToPopAfterDelete: RoutesToPopAfterDelete.None,
            selectedDate: selectedDay,
          ),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 640,
            horizontalPadding: 13,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => changeMonth(-1),
                      icon: Icon(appStateSettings["outlinedIcons"]
                          ? Icons.chevron_left_outlined
                          : Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: TextFont(
                        text: DateFormat.yMMMM(context.locale.toString())
                            .format(selectedMonth)
                            .capitalizeFirst,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: () => changeMonth(1),
                      icon: Icon(appStateSettings["outlinedIcons"]
                          ? Icons.chevron_right_outlined
                          : Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                CalendarMonthGrid(
                  month: selectedMonth,
                  selectedDay: selectedDay,
                  onSelectDay: (day) => setState(() => selectedDay = day),
                ),
                SizedBox(height: 15),
              ],
            ),
          ),
        ),
        TransactionEntries(
          selectedDay,
          dayEnd,
          renderType: TransactionEntriesRenderType.sliversNotSticky,
          listID: pageId,
          noResultsMessage: "no-transactions-for".tr() +
              " " +
              getWordedDateShort(selectedDay) +
              ".",
        ),
        SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    required this.month,
    required this.selectedDay,
    required this.onSelectDay,
    super.key,
  });
  final DateTime month;
  final DateTime selectedDay;
  final Function(DateTime day) onSelectDay;

  int firstWeekdayIndex(BuildContext context) {
    int setting = appStateSettings["firstDayOfWeek"] ?? -1;
    if (setting == -1)
      return MaterialLocalizations.of(context).firstDayOfWeekIndex;
    return setting;
  }

  @override
  Widget build(BuildContext context) {
    DateTime monthEnd = DateTime(month.year, month.month + 1, 0);
    int startIndex = firstWeekdayIndex(context); // 0 is Sunday
    // DateTime.weekday is 1 (Monday) to 7 (Sunday)
    int leadingEmptyDays = (month.weekday % 7 - startIndex) % 7;
    List<String> weekdayNames =
        MaterialLocalizations.of(context).narrowWeekdays;
    return StreamBuilder<List<Transaction>>(
      stream: database.getTransactionsInTimeRangeFromCategories(
        month,
        monthEnd,
        null,
        null,
        true,
        null,
        null,
        null,
      ),
      builder: (context, snapshot) {
        AllWallets allWallets = Provider.of<AllWallets>(context);
        Map<int, double> totalsPerDay = {};
        for (Transaction transaction in snapshot.data ?? []) {
          // Only income and expenses: balance corrections and transfers move
          // money between accounts
          if (transaction.categoryFk == "0") continue;
          int day = transaction.dateCreated.day;
          totalsPerDay[day] = (totalsPerDay[day] ?? 0) +
              transaction.amount *
                  amountRatioToPrimaryCurrencyGivenPk(
                      allWallets, transaction.walletFk);
        }
        List<Widget> cells = [
          for (int i = 0; i < 7; i++)
            Center(
              child: TextFont(
                text: weekdayNames[(startIndex + i) % 7],
                fontSize: 13,
                textColor: getColor(context, "textLight"),
              ),
            ),
          for (int i = 0; i < leadingEmptyDays; i++) SizedBox.shrink(),
          for (int day = 1; day <= monthEnd.day; day++)
            CalendarDayCell(
              day: DateTime(month.year, month.month, day),
              total: totalsPerDay[day],
              selected: selectedDay.year == month.year &&
                  selectedDay.month == month.month &&
                  selectedDay.day == day,
              onTap: () =>
                  onSelectDay(DateTime(month.year, month.month, day)),
            ),
        ];
        return GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          childAspectRatio: 0.95,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        );
      },
    );
  }
}

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    required this.day,
    required this.total,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final DateTime day;
  final double? total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    bool isToday = day.justDay() == DateTime.now().justDay();
    double amount = total ?? 0;
    return Tappable(
      onTap: onTap,
      borderRadius: 12,
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      child: Container(
        decoration: isToday && !selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              )
            : null,
        padding: EdgeInsetsDirectional.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextFont(
              text: day.day.toString(),
              fontSize: 15,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            ),
            SizedBox(height: 2),
            if (total != null && amount != 0)
              TextFont(
                text: convertToMoney(
                  Provider.of<AllWallets>(context),
                  amount.abs(),
                  forceCompactNumberFormatter: true,
                ),
                fontSize: 10.5,
                maxLines: 1,
                autoSizeText: true,
                minFontSize: 7,
                maxFontSize: 10.5,
                textAlign: TextAlign.center,
                textColor: amount > 0
                    ? getColor(context, "incomeAmount")
                    : getColor(context, "expenseAmount"),
              ),
          ],
        ),
      ),
    );
  }
}
