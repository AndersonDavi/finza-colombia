import 'dart:ui' as ui;

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/spendingPatterns.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/saveFile.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

// One month on a single card that can be saved as an image to share: income,
// spending and net against the month before, what the money went to (with
// subcategories), by group, by tag and the biggest expenses.
// Transfers and balance corrections are left out.

class SummaryEntry {
  SummaryEntry(this.name, this.color);
  final String name;
  final Color? color;
  double amount = 0;
}

class MonthlySummary {
  MonthlySummary(List<Transaction> transactions, AllWallets allWallets,
      Map<String, WalletGroup> groups) {
    for (Transaction t in transactions) {
      double amount = t.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
      if (t.income) {
        income += amount;
        continue;
      }
      expenses += amount;
      count++;
      // Accounts without a group count on their own
      TransactionWallet? wallet = allWallets.indexedByPk[t.walletFk];
      WalletGroup? group = groups[wallet?.walletGroupFk];
      String groupKey = group?.walletGroupPk ?? "wallet:" + t.walletFk;
      byGroup
          .putIfAbsent(
              groupKey,
              () => SummaryEntry(
                    group?.name ??
                        (wallet == null
                            ? ""
                            : getWalletStringName(allWallets, wallet)),
                    group != null
                        ? HexColor(group.colour)
                        : wallet != null
                            ? HexColor(wallet.colour)
                            : null,
                  ))
          .amount += amount;
      byCategory[t.categoryFk] = (byCategory[t.categoryFk] ?? 0) + amount;
      if (t.subCategoryFk != null) {
        Map<String, double> subs = bySubcategory.putIfAbsent(t.categoryFk, () => {});
        subs[t.subCategoryFk!] = (subs[t.subCategoryFk!] ?? 0) + amount;
      }
      for (String tagPk in tagPksByTransaction.value[t.transactionPk] ?? []) {
        Tag? tag = tagsCache[tagPk];
        if (tag == null) continue;
        byTag
            .putIfAbsent(tagPk, () => SummaryEntry(tag.name, HexColor(tag.colour)))
            .amount += amount;
      }
      biggest.add(MapEntry(t, amount));
    }
    biggest.sort((a, b) => b.value.compareTo(a.value));
    if (biggest.length > 5) biggest = biggest.sublist(0, 5);
  }
  double income = 0;
  double expenses = 0;
  int count = 0;
  Map<String, SummaryEntry> byGroup = {};
  Map<String, SummaryEntry> byTag = {};
  Map<String, double> byCategory = {};
  Map<String, Map<String, double>> bySubcategory = {};
  List<MapEntry<Transaction, double>> biggest = [];
}

Future<List<Transaction>> getTransactionsOfMonth(DateTime month) {
  return (database.select(database.transactions)
        ..where((t) =>
            t.paid.equals(true) &
            t.categoryFk.equals("0").not() &
            t.pairedTransactionFk.isNull() &
            t.dateCreated.isBiggerOrEqualValue(month) &
            t.dateCreated
                .isSmallerThanValue(DateTime(month.year, month.month + 1))))
      .get();
}

class MonthlySummaryExportPage extends StatefulWidget {
  const MonthlySummaryExportPage({super.key});

  @override
  State<MonthlySummaryExportPage> createState() =>
      _MonthlySummaryExportPageState();
}

class _MonthlySummaryExportPageState extends State<MonthlySummaryExportPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  final GlobalKey cardKey = GlobalKey();
  Future<_MonthData>? data;

  Future<_MonthData> load(AllWallets allWallets) async {
    Map<String, WalletGroup> groups = {
      for (WalletGroup g in await database.getAllWalletGroups())
        g.walletGroupPk: g
    };
    List<TransactionCategory> categories =
        await database.select(database.categories).get();
    // While the month is running it is compared with the same days of the
    // month before
    DateTime now = DateTime.now();
    bool running = month.year == now.year && month.month == now.month;
    List<Transaction> before =
        await getTransactionsOfMonth(DateTime(month.year, month.month - 1));
    if (running) before = before.where((t) => t.dateCreated.day <= now.day).toList();
    SpendingStats? stats = running
        ? SpendingStats(await expensesForPatternsQuery().get(), allWallets)
        : null;
    return _MonthData(
      MonthlySummary(await getTransactionsOfMonth(month), allWallets, groups),
      MonthlySummary(before, allWallets, groups),
      stats?.projection,
      {for (TransactionCategory c in categories) c.categoryPk: c},
    );
  }

  void changeMonth(int difference) {
    setState(() {
      month = DateTime(month.year, month.month + difference);
      data = null;
    });
  }

  Future<void> saveImage(BuildContext boxContext) async {
    RenderRepaintBoundary? boundary =
        cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    ui.Image image = await boundary.toImage(pixelRatio: 3);
    var bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    await saveFile(
      boxContext: boxContext,
      dataStore: bytes.buffer.asUint8List(),
      dataString: null,
      fileName: "resumen-" + DateFormat("yyyy-MM").format(month) + ".png",
      successMessage: "image-saved".tr(),
      errorMessage: "error-saving".tr(),
    );
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    data ??= load(allWallets);
    return PageFramework(
      title: "monthly-summary".tr(),
      dragDownToDismiss: true,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(
                horizontal: getHorizontalPaddingConstrained(context) + 13),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => changeMonth(-1),
                      icon: Icon(Icons.chevron_left_rounded),
                    ),
                    SizedBox(
                      width: 180,
                      child: TextFont(
                        text: getMonth(month, includeYear: true)
                            .capitalizeFirst,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      onPressed: month.isBefore(DateTime(
                              DateTime.now().year, DateTime.now().month))
                          ? () => changeMonth(1)
                          : null,
                      icon: Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                FutureBuilder<_MonthData>(
                  future: data,
                  builder: (context, snapshot) {
                    if (snapshot.data == null)
                      return Padding(
                        padding: const EdgeInsetsDirectional.all(40),
                        child: CircularProgressIndicator(),
                      );
                    return RepaintBoundary(
                      key: cardKey,
                      child: MonthlySummaryCard(
                        month: month,
                        summary: snapshot.data!.summary,
                        previous: snapshot.data!.previous,
                        projection: snapshot.data!.projection,
                        categories: snapshot.data!.categories,
                      ),
                    );
                  },
                ),
                SizedBox(height: 15),
                Builder(
                  builder: (boxContext) => Button(
                    label: "save-image".tr(),
                    icon: appStateSettings["outlinedIcons"]
                        ? Icons.download_outlined
                        : Icons.download_rounded,
                    onTap: () => saveImage(boxContext),
                  ),
                ),
                SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MonthData {
  _MonthData(this.summary, this.previous, this.projection, this.categories);
  final MonthlySummary summary;
  final MonthlySummary previous;
  final double? projection;
  final Map<String, TransactionCategory> categories;
}

class MonthlySummaryCard extends StatelessWidget {
  const MonthlySummaryCard({
    required this.month,
    required this.summary,
    required this.previous,
    required this.categories,
    this.projection,
    super.key,
  });
  final DateTime month;
  final MonthlySummary summary;
  final MonthlySummary previous;
  // Only while the month is running
  final double? projection;
  final Map<String, TransactionCategory> categories;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    // Rounded, cents add noise to totals
    String money(double value) =>
        convertToMoney(allWallets, value.roundToDouble());
    Color textLight = getColor(context, "textLight");
    Color primary = Theme.of(context).colorScheme.primary;
    DateTime now = DateTime.now();
    bool running = month.year == now.year && month.month == now.month;
    String previousMonthName = (running ? "1–" + now.day.toString() + " " : "") +
        DateFormat.MMM(context.locale.toString())
            .format(DateTime(month.year, month.month - 1))
            .replaceAll(".", "");
    String percentOf(double value, double total) =>
        (total <= 0 ? 0 : value / total * 100).round().toString() + "%";

    Widget bar(double value, Color color) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 6,
            color: color,
            backgroundColor: color.withOpacity(0.15),
          ),
        );

    // Income, spending or net with how it moved against the month before
    Widget total(String label, double value, double before, Color? color,
        {bool lessIsBetter = false}) {
      double? change =
          before == 0 ? null : (value - before) / before.abs() * 100;
      bool better = change != null && (lessIsBetter ? change < 0 : change > 0);
      return Expanded(
        child: Container(
          padding: const EdgeInsetsDirectional.all(10),
          margin: const EdgeInsetsDirectional.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: (color ?? primary).withOpacity(0.12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFont(text: label, fontSize: 13, textColor: textLight),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: TextFont(
                  text: money(value),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  textColor: color,
                ),
              ),
              if (change != null && change.abs() >= 1)
                TextFont(
                  text: (change > 0 ? "▲ " : "▼ ") +
                      change.abs().round().toString() +
                      "% vs " +
                      previousMonthName,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  textColor: better
                      ? getColor(context, "incomeAmount")
                      : getColor(context, "expenseAmount"),
                ),
            ],
          ),
        ),
      );
    }

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsetsDirectional.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFont(text: title, fontSize: 16, fontWeight: FontWeight.bold),
              SizedBox(height: 8),
              ...children,
            ],
          ),
        );

    // Name, share, amount and a bar; the leading widget is an icon or a dot
    Widget row(Widget leading, String name, double amount, double max,
        Color color,
        {String? detail}) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 34, child: Center(child: leading)),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFont(
                          text: name,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          maxLines: 1,
                        ),
                      ),
                      TextFont(
                        text: percentOf(amount, summary.expenses),
                        fontSize: 13,
                        textColor: textLight,
                      ),
                      SizedBox(width: 10),
                      TextFont(
                        text: money(amount),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  bar(max <= 0 ? 0 : amount / max, color),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 4),
                      child: TextFont(
                        text: detail,
                        fontSize: 12,
                        maxLines: 2,
                        textColor: textLight,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget dot(Color? color) => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? primary,
          ),
        );

    List<MapEntry<String, double>> categoryRanking =
        summary.byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    List<SummaryEntry> groupRanking = summary.byGroup.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    List<SummaryEntry> tagRanking = summary.byTag.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

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
            text: getMonth(month, includeYear: true).capitalizeFirst,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          TextFont(
            text: "monthly-summary".tr() +
                " · " +
                summary.count.toString() +
                " " +
                "expenses".tr().toLowerCase(),
            fontSize: 13,
            textColor: textLight,
          ),
          SizedBox(height: 14),
          Row(
            children: [
              total("income".tr(), summary.income, previous.income,
                  getColor(context, "incomeAmount")),
              total("expenses".tr(), summary.expenses, previous.expenses,
                  getColor(context, "expenseAmount"),
                  lessIsBetter: true),
              total("net".tr(), summary.income - summary.expenses,
                  previous.income - previous.expenses, null),
            ],
          ),
          if (projection != null)
            Container(
              margin: const EdgeInsetsDirectional.only(top: 10, start: 3, end: 3),
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: getColor(context, "expenseAmount").withOpacity(0.08),
              ),
              child: Row(
                children: [
                  Icon(Icons.insights_rounded,
                      size: 18, color: getColor(context, "expenseAmount")),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextFont(
                      text: "month-projection".tr(),
                      fontSize: 14,
                    ),
                  ),
                  TextFont(
                    text: money(projection!),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ],
              ),
            ),
          if (categoryRanking.isNotEmpty)
            section("where-it-goes".tr(), [
              for (MapEntry<String, double> entry in categoryRanking.take(8))
                Builder(builder: (context) {
                  TransactionCategory? category = categories[entry.key];
                  List<MapEntry<String, double>> subs =
                      (summary.bySubcategory[entry.key] ?? {}).entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                  return row(
                    CategoryIcon(
                      margin: EdgeInsetsDirectional.zero,
                      categoryPk: entry.key,
                      category: category,
                      size: 20,
                      sizePadding: 10,
                      borderRadius: 100,
                      canEditByLongPress: false,
                    ),
                    category?.name ?? "",
                    entry.value,
                    categoryRanking.first.value,
                    HexColor(category?.colour, defaultColor: primary),
                    detail: subs.isEmpty
                        ? null
                        : [
                            for (var sub in subs.take(3))
                              (categories[sub.key]?.name ?? "") +
                                  " " +
                                  money(sub.value)
                          ].join("  ·  "),
                  );
                }),
            ]),
          if (groupRanking.isNotEmpty)
            section("by-group".tr(), [
              for (SummaryEntry entry in groupRanking.take(6))
                row(dot(entry.color), entry.name, entry.amount,
                    groupRanking.first.amount, entry.color ?? primary),
            ]),
          if (tagRanking.isNotEmpty)
            section("by-tag".tr(), [
              for (SummaryEntry entry in tagRanking.take(6))
                row(
                  Icon(Icons.sell_rounded, size: 18, color: entry.color),
                  entry.name,
                  entry.amount,
                  tagRanking.first.amount,
                  entry.color ?? primary,
                ),
            ]),
          if (summary.biggest.isNotEmpty)
            section("biggest-expenses".tr(), [
              for (MapEntry<Transaction, double> entry in summary.biggest)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Center(
                          child: CategoryIcon(
                            margin: EdgeInsetsDirectional.zero,
                            categoryPk: entry.key.categoryFk,
                            category: categories[entry.key.categoryFk],
                            size: 18,
                            sizePadding: 8,
                            borderRadius: 100,
                            canEditByLongPress: false,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: TextFont(
                          text: entry.key.name.trim() != ""
                              ? entry.key.name
                              : categories[entry.key.categoryFk]?.name ?? "",
                          fontSize: 14,
                          maxLines: 1,
                        ),
                      ),
                      TextFont(
                        text: getWordedDateShort(entry.key.dateCreated),
                        fontSize: 12,
                        textColor: textLight,
                      ),
                      SizedBox(width: 10),
                      TextFont(
                        text: money(entry.value),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}
