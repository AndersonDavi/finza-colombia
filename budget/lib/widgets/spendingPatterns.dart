import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Spending patterns of the last 12 months, in the primary currency: where
// this month is heading, what takes the most (categories and their
// subcategories, against their usual month), the month by month bars, and
// which part of the month and which weekdays take the most.
// Transfers, balance corrections and loans are left out.

double median(List<double> values) {
  if (values.isEmpty) return 0;
  List<double> sorted = [...values]..sort();
  int middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

// The period the patterns look at, chosen on the card and kept per device:
// "12m" (default), "year", "all" or "custom" (patternsStart / patternsEnd)
DateTimeRange patternsRange() {
  DateTime now = DateTime.now();
  DateTime nextMonth = DateTime(now.year, now.month + 1);
  switch (appStateSettings["patternsPeriod"]) {
    case "year":
      return DateTimeRange(start: DateTime(now.year), end: nextMonth);
    case "all":
      return DateTimeRange(start: DateTime(1970), end: nextMonth);
    case "custom":
      DateTime? start =
          DateTime.tryParse(appStateSettings["patternsStart"] ?? "");
      DateTime? end = DateTime.tryParse(appStateSettings["patternsEnd"] ?? "");
      if (start != null && end != null)
        // The end day is included
        return DateTimeRange(
            start: start, end: DateTime(end.year, end.month, end.day + 1));
  }
  return DateTimeRange(
      start: DateTime(now.year, now.month - 11), end: nextMonth);
}

class SpendingStats {
  SpendingStats(List<Transaction> expenses, AllWallets allWallets,
      {required DateTimeRange range}) {
    DateTime now = DateTime.now();
    DateTime monthStart = DateTime(now.year, now.month);
    // Projection and "this month" only make sense while the range reaches today
    running = range.end.isAfter(monthStart) && !range.start.isAfter(now);
    DateTime? earliest;
    Map<DateTime, double> spentByMonth = {};
    Map<DateTime, double> spentByMonthUntilToday = {};
    for (Transaction t in expenses) {
      double amount = t.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
      DateTime date = t.dateCreated;
      DateTime month = DateTime(date.year, date.month);
      if (earliest == null || month.isBefore(earliest)) earliest = month;
      spentByMonth[month] = (spentByMonth[month] ?? 0) + amount;
      if (date.day <= now.day) {
        spentByMonthUntilToday[month] =
            (spentByMonthUntilToday[month] ?? 0) + amount;
        Map<String, double> untilToday =
            byMonthCategoryUntilToday.putIfAbsent(month, () => {});
        untilToday[t.categoryFk] = (untilToday[t.categoryFk] ?? 0) + amount;
      }
      Map<String, double> categories =
          byMonthCategory.putIfAbsent(month, () => {});
      categories[t.categoryFk] = (categories[t.categoryFk] ?? 0) + amount;
      if (t.subCategoryFk != null) {
        Map<String, double> subcategories = byMonthSubcategory
            .putIfAbsent(month, () => {})
            .putIfAbsent(t.categoryFk, () => {});
        subcategories[t.subCategoryFk!] =
            (subcategories[t.subCategoryFk!] ?? 0) + amount;
      }
      if (running && !month.isBefore(monthStart)) {
        thisMonth += amount;
        continue;
      }
      // The rest only looks at full past months
      int day = date.day;
      byWeekOfMonth[day <= 7
          ? 0
          : day <= 15
              ? 1
              : day <= 23
                  ? 2
                  : 3] += amount;
      byWeekday[date.weekday - 1] += amount;
    }
    // From the start of the range (or the first expense) to its last month
    DateTime first = DateTime(range.start.year, range.start.month);
    if (earliest != null && earliest.isAfter(first)) first = earliest;
    DateTime lastDay = range.end.subtract(Duration(days: 1));
    DateTime last =
        running ? monthStart : DateTime(lastDay.year, lastDay.month);
    for (DateTime month = first;
        !month.isAfter(last);
        month = DateTime(month.year, month.month + 1)) {
      months.add(month);
      byMonth.add(spentByMonth[month] ?? 0);
    }
    pastMonths = spentByMonth.keys
        .where((m) =>
            (!running || m.isBefore(monthStart)) && (spentByMonth[m] ?? 0) > 0)
        .toList();
    if (pastMonths.isNotEmpty) {
      // The median keeps one unusual month (a trip, a big purchase) from
      // moving the typical month
      typicalMonth = median([for (DateTime m in pastMonths) spentByMonth[m]!]);
    }
    if (pastMonths.isNotEmpty && running) {
      double shareByToday = median([
        for (DateTime m in pastMonths)
          (spentByMonthUntilToday[m] ?? 0) / spentByMonth[m]!
      ]);
      projection = thisMonth + typicalMonth * (1 - shareByToday);
      typicalByToday = median([
        for (DateTime m in pastMonths) spentByMonthUntilToday[m] ?? 0
      ]);
    }
  }

  bool running = false;
  double thisMonth = 0;
  double typicalMonth = 0;
  double typicalByToday = 0;
  double? projection;
  List<DateTime> pastMonths = [];
  List<double> byWeekOfMonth = [0, 0, 0, 0];
  List<double> byWeekday = [0, 0, 0, 0, 0, 0, 0];
  List<DateTime> months = [];
  List<double> byMonth = [];
  Map<DateTime, Map<String, double>> byMonthCategory = {};
  Map<DateTime, Map<String, double>> byMonthCategoryUntilToday = {};
  Map<DateTime, Map<String, Map<String, double>>> byMonthSubcategory = {};

  // The last [monthCount] months of the range (0 = all of it)
  List<DateTime> lastMonths(int monthCount) =>
      monthCount <= 0 || monthCount >= months.length
          ? months
          : months.sublist(months.length - monthCount);

  // Spending by category over the last [monthCount] months (1 = this month)
  Map<String, double> categoriesOf(int monthCount) {
    Map<String, double> total = {};
    for (DateTime month in lastMonths(monthCount)) {
      byMonthCategory[month]?.forEach(
          (category, amount) => total[category] = (total[category] ?? 0) + amount);
    }
    return total;
  }

  Map<String, double> subcategoriesOf(String categoryPk, int monthCount) {
    Map<String, double> total = {};
    for (DateTime month in lastMonths(monthCount)) {
      byMonthSubcategory[month]?[categoryPk]?.forEach(
          (sub, amount) => total[sub] = (total[sub] ?? 0) + amount);
    }
    return total;
  }

  // Usual month of a category: median over the past months, empty months
  // counting as zero
  double typicalOf(String categoryPk) => median([
        for (DateTime m in pastMonths) byMonthCategory[m]?[categoryPk] ?? 0
      ]);

  // Same, but only up to today's day of the month, to compare this month
  // fairly while it is still running
  double typicalUntilTodayOf(String categoryPk) => median([
        for (DateTime m in pastMonths)
          byMonthCategoryUntilToday[m]?[categoryPk] ?? 0
      ]);
}

SimpleSelectStatement<$TransactionsTable, Transaction>
    expensesForPatternsQuery({DateTimeRange? range}) {
  DateTimeRange period = range ?? patternsRange();
  return database.select(database.transactions)
    ..where((t) =>
        t.income.equals(false) &
        t.paid.equals(true) &
        t.categoryFk.equals("0").not() &
        t.pairedTransactionFk.isNull() &
        t.objectiveLoanFk.isNull() &
        t.dateCreated.isBiggerOrEqualValue(period.start) &
        t.dateCreated.isSmallerThanValue(period.end));
}

class SpendingPatterns extends StatefulWidget {
  const SpendingPatterns({super.key});

  @override
  State<SpendingPatterns> createState() => _SpendingPatternsState();
}

class _SpendingPatternsState extends State<SpendingPatterns> {
  late DateTimeRange range = patternsRange();
  late Stream<List<Transaction>> expenses =
      expensesForPatternsQuery(range: range).watch();

  Future<void> choosePeriod(String kind) async {
    if (kind == "custom") {
      DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime.now(),
        initialDateRange: appStateSettings["patternsPeriod"] == "custom"
            ? DateTimeRange(
                start: range.start,
                end: range.end.subtract(Duration(days: 1)))
            : null,
      );
      if (picked == null) return;
      await updateSettings("patternsStart", picked.start.toIso8601String(),
          updateGlobalState: false);
      await updateSettings("patternsEnd", picked.end.toIso8601String(),
          updateGlobalState: false);
    }
    await updateSettings("patternsPeriod", kind, updateGlobalState: false);
    setState(() {
      range = patternsRange();
      expenses = expensesForPatternsQuery(range: range).watch();
    });
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return StreamBuilder<List<Transaction>>(
      stream: expenses,
      builder: (context, snapshot) {
        if (snapshot.data == null) return SizedBox.shrink();
        SpendingStats stats =
            SpendingStats(snapshot.data!, allWallets, range: range);
        return Padding(
          // In the two column layout the column is already narrow
          padding: EdgeInsetsDirectional.symmetric(
              horizontal: enableDoubleColumn(context)
                  ? 13
                  : getHorizontalPaddingConstrained(context) + 13,
              vertical: 10),
          child: StreamBuilder<List<TransactionCategory>>(
            // Main categories and subcategories
            stream: database.select(database.categories).watch(),
            builder: (context, snapshot) => SpendingPatternsCard(
              stats: stats,
              range: range,
              onPeriod: choosePeriod,
              categories: {
                for (TransactionCategory c in snapshot.data ?? [])
                  c.categoryPk: c
              },
            ),
          ),
        );
      },
    );
  }
}

class SpendingPatternsCard extends StatefulWidget {
  const SpendingPatternsCard({
    required this.stats,
    required this.categories,
    required this.range,
    required this.onPeriod,
    super.key,
  });
  final SpendingStats stats;
  final Map<String, TransactionCategory> categories;
  final DateTimeRange range;
  final Function(String kind) onPeriod;

  @override
  State<SpendingPatternsCard> createState() => _SpendingPatternsCardState();
}

class _SpendingPatternsCardState extends State<SpendingPatternsCard> {
  // Months the category ranking covers: this month, 3 or 12
  int monthCount = 1;
  Set<String> expanded = {};

  @override
  Widget build(BuildContext context) {
    SpendingStats stats = widget.stats;
    AllWallets allWallets = Provider.of<AllWallets>(context);
    // Rounded, cents add noise to averages and totals
    String money(double value) =>
        convertToMoney(allWallets, value.roundToDouble());
    Color barColor = getColor(context, "expenseAmount");
    Color textLight = getColor(context, "textLight");
    String locale = context.locale.toString();

    Widget section(String title, Widget child, {Widget? trailing}) => Padding(
          padding: const EdgeInsetsDirectional.only(top: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFont(
                      text: title,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
              SizedBox(height: 10),
              child,
            ],
          ),
        );

    Widget bar(double value, Color color, {double height = 8}) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: height,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        );

    // Horizontal bars with a label and the share of the total
    Widget shareBars(List<String> labels, List<double> values) {
      double total = values.fold(0.0, (s, v) => s + v);
      double max = values.fold(0.0, (m, v) => v > m ? v : m);
      return Column(
        children: [
          for (int i = 0; i < values.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: TextFont(text: labels[i], fontSize: 14),
                  ),
                  Expanded(
                    child: bar(
                      max <= 0 ? 0 : values[i] / max,
                      values[i] == max ? barColor : barColor.withOpacity(0.5),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: TextFont(
                      text: total <= 0
                          ? "0%"
                          : (values[i] / total * 100).round().toString() + "%",
                      fontSize: 14,
                      textAlign: TextAlign.end,
                      textColor: textLight,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    double maxMonth = stats.byMonth.fold(0.0, (m, v) => v > m ? v : m);
    // Long ranges scroll sideways with fixed width bars; January carries
    // its year when the range covers more than one
    bool scrolls = stats.months.length > 18;
    bool manyYears = stats.months.isNotEmpty &&
        stats.months.first.year != stats.months.last.year;
    Widget monthBar(int i) {
      DateTime month = stats.months[i];
      Widget bar = Tooltip(
        message: getMonth(month, includeYear: true) +
            ": " +
            money(stats.byMonth[i]),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              margin: const EdgeInsetsDirectional.symmetric(horizontal: 2.5),
              height: maxMonth <= 0
                  ? 0
                  : (stats.byMonth[i] / maxMonth * 80).clamp(2, 80).toDouble(),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                // This month is still running, it shows lighter
                color: stats.running && i == stats.months.length - 1
                    ? barColor.withOpacity(0.25)
                    : stats.byMonth[i] == maxMonth
                        ? barColor
                        : barColor.withOpacity(0.55),
              ),
            ),
            SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: TextFont(
                text: DateFormat.MMM(locale).format(month).replaceAll(".", "") +
                    (manyYears && month.month == 1
                        ? " " + (month.year % 100).toString().padLeft(2, "0")
                        : ""),
                fontSize: 11,
                textColor: textLight,
              ),
            ),
          ],
        ),
      );
      return scrolls ? SizedBox(width: 34, child: bar) : Expanded(child: bar);
    }

    Widget bars = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [for (int i = 0; i < stats.months.length; i++) monthBar(i)],
    );
    Widget monthBars = SizedBox(
      height: 110,
      child: scrolls
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: bars,
            )
          : bars,
    );

    // What takes the most in the chosen months, with its subcategories
    Map<String, double> byCategory = stats.categoriesOf(monthCount);
    double categoriesTotal = byCategory.values.fold(0.0, (s, v) => s + v);
    List<MapEntry<String, double>> ranking = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    double topAmount = ranking.isEmpty ? 0 : ranking.first.value;

    Widget periodChip(int months, String label) {
      bool selected = monthCount == months;
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: Tappable(
          borderRadius: 10,
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          onTap: () => setState(() => monthCount = months),
          child: Padding(
            padding:
                const EdgeInsetsDirectional.symmetric(horizontal: 9, vertical: 4),
            child: TextFont(
              text: label,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              textColor: selected
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : textLight,
            ),
          ),
        ),
      );
    }

    Widget categoryRow(MapEntry<String, double> entry) {
      TransactionCategory? category = widget.categories[entry.key];
      Color color = HexColor(category?.colour,
          defaultColor: Theme.of(context).colorScheme.primary);
      Map<String, double> subcategories =
          stats.subcategoriesOf(entry.key, monthCount);
      List<MapEntry<String, double>> subRanking = subcategories.entries
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      bool isExpanded = expanded.contains(entry.key);
      // Against what it usually has by this day, only when looking at this
      // month
      double typical = stats.typicalOf(entry.key);
      // A finished range compares whole months
      double typicalByToday =
          stats.running ? stats.typicalUntilTodayOf(entry.key) : typical;
      String? versus;
      bool above = false;
      if (monthCount == 1 && typicalByToday > 0) {
        double change = (entry.value - typicalByToday) / typicalByToday * 100;
        above = change > 0;
        // Big jumps read better as times than as thousands of percent
        if (change >= 200)
          versus = "×" + (entry.value / typicalByToday).round().toString();
        else if (change.abs() >= 5)
          versus = (above ? "+" : "") + change.round().toString() + "%";
      }
      return Tappable(
        borderRadius: 14,
        color: Colors.transparent,
        onTap: subRanking.isEmpty
            ? null
            : () => setState(() => isExpanded
                ? expanded.remove(entry.key)
                : expanded.add(entry.key)),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryIcon(
                    margin: EdgeInsetsDirectional.zero,
                    categoryPk: entry.key,
                    category: category,
                    size: 22,
                    sizePadding: 12,
                    borderRadius: 100,
                    canEditByLongPress: false,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFont(
                                text: category?.name ?? "",
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                maxLines: 1,
                              ),
                            ),
                            TextFont(
                              text: money(entry.value),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ],
                        ),
                        SizedBox(height: 2),
                        Row(
                          children: [
                            TextFont(
                              text: (categoriesTotal <= 0
                                          ? 0
                                          : entry.value / categoriesTotal * 100)
                                      .round()
                                      .toString() +
                                  "% " +
                                  "of-spending".tr(),
                              fontSize: 12,
                              textColor: textLight,
                            ),
                            if (subRanking.isNotEmpty)
                              Icon(
                                isExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 16,
                                color: textLight,
                              ),
                            Spacer(),
                            if (versus != null)
                              Tooltip(
                                message: "typical-by-today".tr() +
                                    ": " +
                                    money(typicalByToday) +
                                    "\n" +
                                    "typical-month".tr() +
                                    ": " +
                                    money(typical),
                                child: TextFont(
                                  text: versus,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  textColor: above
                                      ? getColor(context, "expenseAmount")
                                      : getColor(context, "incomeAmount"),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 5),
                        bar(topAmount <= 0 ? 0 : entry.value / topAmount,
                            color,
                            height: 6),
                      ],
                    ),
                  ),
                ],
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 44, top: 6),
                  child: Column(
                    children: [
                      for (MapEntry<String, double> sub in subRanking.take(6))
                        Padding(
                          padding: const EdgeInsetsDirectional.only(bottom: 6),
                          child: Row(
                            children: [
                              CategoryIcon(
                                margin: EdgeInsetsDirectional.zero,
                                categoryPk: sub.key,
                                category: widget.categories[sub.key],
                                size: 16,
                                sizePadding: 8,
                                borderRadius: 100,
                                canEditByLongPress: false,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: TextFont(
                                  text: widget.categories[sub.key]?.name ?? "",
                                  fontSize: 14,
                                  maxLines: 1,
                                ),
                              ),
                              TextFont(
                                text: money(sub.value),
                                fontSize: 14,
                                textColor: textLight,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    DateTime monday = DateTime(2024, 1, 1);
    List<String> weekdays = [
      for (int i = 0; i < 7; i++)
        DateFormat.E(locale).format(monday.add(Duration(days: i)))
    ];

    // The numbers said in words, only the ones worth saying
    List<MapEntry<IconData, String>> insights = [];
    String pct(double value) => value.abs().round().toString();
    if (stats.typicalByToday > 0) {
      double pace =
          (stats.thisMonth - stats.typicalByToday) / stats.typicalByToday * 100;
      if (pace.abs() >= 10)
        insights.add(MapEntry(
            pace > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            (pace > 0 ? "insight-pace-above" : "insight-pace-below")
                .tr(namedArgs: {"pct": pct(pace)})));
    }
    MapEntry<String, double>? risingCategory;
    double risingChange = 0;
    for (MapEntry<String, double> entry in stats.categoriesOf(1).entries) {
      double usual = stats.running
          ? stats.typicalUntilTodayOf(entry.key)
          : stats.typicalOf(entry.key);
      if (usual <= 0 || entry.value < stats.thisMonth * 0.05) continue;
      double change = (entry.value - usual) / usual * 100;
      if (change > risingChange) {
        risingChange = change;
        risingCategory = entry;
      }
    }
    if (risingCategory != null && risingChange >= 25)
      insights.add(MapEntry(
          Icons.local_fire_department_rounded,
          "insight-category-above".tr(namedArgs: {
            "name": widget.categories[risingCategory.key]?.name ?? "",
            "amount": money(risingCategory.value),
            "usual": money(stats.typicalUntilTodayOf(risingCategory.key)),
          })));
    Map<String, double> lastThree = stats.categoriesOf(3);
    double lastThreeTotal = lastThree.values.fold(0.0, (s, v) => s + v);
    MapEntry<String, double>? topCategory = (lastThree.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .firstOrNull;
    if (topCategory != null && lastThreeTotal > 0)
      insights.add(MapEntry(
          Icons.pie_chart_rounded,
          "insight-top-category".tr(namedArgs: {
            "name": widget.categories[topCategory.key]?.name ?? "",
            "pct": pct(topCategory.value / lastThreeTotal * 100),
            "amount": money(topCategory.value),
          })));
    double weekdayTotal = stats.byWeekday.fold(0.0, (s, v) => s + v);
    int topWeekday = stats.byWeekday
        .indexOf(stats.byWeekday.fold(0.0, (m, v) => v > m ? v : m));
    if (weekdayTotal > 0 && stats.byWeekday[topWeekday] / weekdayTotal >= 0.17) {
      String day = DateFormat.EEEE(locale)
          .format(monday.add(Duration(days: topWeekday)));
      if (!day.endsWith("s")) day += "s";
      insights.add(MapEntry(
          Icons.today_rounded,
          "insight-weekday".tr(namedArgs: {
            "day": day,
            "pct": pct(stats.byWeekday[topWeekday] / weekdayTotal * 100),
          })));
    }
    double partTotal = stats.byWeekOfMonth.fold(0.0, (s, v) => s + v);
    int topPart = stats.byWeekOfMonth
        .indexOf(stats.byWeekOfMonth.fold(0.0, (m, v) => v > m ? v : m));
    if (partTotal > 0 && stats.byWeekOfMonth[topPart] / partTotal >= 0.28)
      insights.add(MapEntry(
          Icons.date_range_rounded,
          "insight-part-of-month".tr(namedArgs: {
            "from": ["1", "8", "16", "24"][topPart],
            "to": ["7", "15", "23", "31"][topPart],
            "pct": pct(stats.byWeekOfMonth[topPart] / partTotal * 100),
          })));
    // The most expensive full month, when it stands out from the typical one
    int topMonth = -1;
    for (int i = 0;
        i < stats.months.length - (stats.running ? 1 : 0);
        i++)
      if (topMonth == -1 || stats.byMonth[i] > stats.byMonth[topMonth])
        topMonth = i;
    if (topMonth >= 0 && stats.byMonth[topMonth] > stats.typicalMonth * 1.3)
      insights.add(MapEntry(
          Icons.event_busy_rounded,
          "insight-top-month".tr(namedArgs: {
            "month": getMonth(stats.months[topMonth]).capitalizeFirst,
            "amount": money(stats.byMonth[topMonth]),
            "pct": pct((stats.byMonth[topMonth] - stats.typicalMonth) /
                stats.typicalMonth *
                100),
          })));

    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: getColor(context, "lightDarkAccentHeavyLight"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFont(
            text: "spending-patterns".tr(),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          // Its own period, apart from the selectors of the page
          SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (MapEntry<String, String> option in {
                "12m": "last-12-months".tr(),
                "year": "this-year".tr(),
                "all": "all-history".tr(),
                "custom": appStateSettings["patternsPeriod"] == "custom"
                    ? getWordedDateShort(widget.range.start,
                            includeYear: true) +
                        " – " +
                        getWordedDateShort(
                            widget.range.end.subtract(Duration(days: 1)),
                            includeYear: true)
                    : "date-range".tr() + "…",
              }.entries)
                ChoiceChip(
                  label: Text(option.value),
                  selected: (appStateSettings["patternsPeriod"] ?? "12m") ==
                      option.key,
                  onSelected: (_) => widget.onPeriod(option.key),
                ),
            ],
          ),
          if (stats.pastMonths.isEmpty && stats.thisMonth == 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 16),
              child: TextFont(
                text: "no-spending-in-period".tr(),
                fontSize: 14,
                textColor: textLight,
              ),
            ),
          // Projection of the month, the first thing to see
          if (stats.projection != null)
            Container(
              margin: const EdgeInsetsDirectional.only(top: 14),
              padding: const EdgeInsetsDirectional.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: barColor.withOpacity(0.12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.insights_rounded, size: 18, color: barColor),
                      SizedBox(width: 6),
                      TextFont(
                        text: "month-projection".tr(),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        textColor: barColor,
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  TextFont(
                    text: money(stats.projection!),
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                  SizedBox(height: 8),
                  bar(
                    stats.projection! <= 0
                        ? 0
                        : stats.thisMonth / stats.projection!,
                    barColor,
                    height: 8,
                  ),
                  SizedBox(height: 8),
                  TextFont(
                    text: "projection-explained".tr(namedArgs: {
                      "spent": money(stats.thisMonth),
                      "typical": money(stats.typicalMonth),
                    }),
                    fontSize: 13,
                    maxLines: 3,
                    textColor: textLight,
                  ),
                ],
              ),
            ),
          if (insights.isNotEmpty)
            section(
              "what-your-numbers-say".tr(),
              Column(
                children: [
                  for (MapEntry<IconData, String> insight in insights)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: barColor.withOpacity(0.15),
                            ),
                            child: Icon(insight.key, size: 17, color: barColor),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(top: 5),
                              child: TextFont(
                                text: insight.value,
                                fontSize: 14,
                                maxLines: 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (ranking.isNotEmpty)
            section(
              "where-it-goes".tr(),
              Column(children: [for (var e in ranking.take(8)) categoryRow(e)]),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  periodChip(1, "this-month-short".tr()),
                  periodChip(3, "3m"),
                  periodChip(0, "whole-period".tr()),
                ],
              ),
            ),
          section("by-month".tr(), monthBars),
          section(
            "by-part-of-month".tr(),
            shareBars(["1–7", "8–15", "16–23", "24–31"], stats.byWeekOfMonth),
          ),
          section("by-weekday".tr(), shareBars(weekdays, stats.byWeekday)),
        ],
      ),
    );
  }
}
