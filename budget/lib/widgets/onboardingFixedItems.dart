import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/tools/incomeProfile.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/initializeNotifications.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/amountInputFormatter.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/onboardingWidgets.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Payments and income that come back every month, offered in the
// onboarding. Each one becomes a pending repeating transaction: a reminder
// confirmed by hand when the money actually moves, never paid on its own

class FixedItemPreset {
  const FixedItemPreset({
    required this.id,
    required this.icon,
    this.iconName,
    required this.color,
    required this.categoryPk,
    this.income = false,
    this.defaultDay = 1,
    this.allowsBiweekly = false,
    this.custom = false,
    this.hasHint = false,
    this.multiple = false,
    this.nameSuggestions = const [],
    this.varies = false,
    this.hasNote = false,
  });
  // Title key is "onb-fixed-<id>", the optional hint "onb-fixed-<id>-hint"
  final String id;
  final IconData icon;
  // The same pictures as the categories; icon is only used without one
  final String? iconName;
  final Color color;
  // Default category it goes into; falls back to the first one that fits
  final String categoryPk;
  final bool income;
  final int defaultDay;
  final bool allowsBiweekly;
  // "Other": the name and the direction are typed in the sheet
  final bool custom;
  final bool hasHint;
  // Several can be added (Netflix and Spotify, two loans), each with its own
  // name; the name hint key is "onb-fixed-<id>-name-hint"
  final bool multiple;
  // Quick picks that fill the name
  final List<String> nameSuggestions;
  // The amount changes month to month: an average is asked
  final bool varies;
  // A line under the fields, key "onb-fixed-<id>-note"
  final bool hasNote;

  bool get asksName => custom || multiple;

  String get title => "onb-fixed-$id".tr();
  String? get hint => hasHint ? "onb-fixed-$id-hint".tr() : null;
}

const List<FixedItemPreset> fixedItemPresets = [
  FixedItemPreset(
    id: "salary",
    icon: Icons.payments_rounded,
    iconName: "money.png",
    color: Color(0xFF2E7D32),
    categoryPk: "11",
    income: true,
    defaultDay: 30,
    allowsBiweekly: true,
  ),
  FixedItemPreset(
    id: "rent",
    icon: Icons.home_rounded,
    iconName: "rent.png",
    color: Color(0xFFEF6C00),
    categoryPk: "6",
  ),
  FixedItemPreset(
    id: "utilities",
    icon: Icons.lightbulb_rounded,
    iconName: "lightning-bolt.png",
    color: Color(0xFFF9A825),
    categoryPk: "6",
    defaultDay: 10,
    hasHint: true,
    multiple: true,
    varies: true,
    nameSuggestions: ["Luz", "Agua", "Gas", "Aseo"],
  ),
  FixedItemPreset(
    id: "phone",
    icon: Icons.wifi_rounded,
    iconName: "wifi.png",
    color: Color(0xFF1565C0),
    categoryPk: "6",
    defaultDay: 15,
  ),
  FixedItemPreset(
    id: "loan",
    icon: Icons.account_balance_rounded,
    iconName: "loan.png",
    color: Color(0xFF6A1B9A),
    categoryPk: "6",
    defaultDay: 5,
    multiple: true,
    hasNote: true,
  ),
  FixedItemPreset(
    id: "subscriptions",
    icon: Icons.subscriptions_rounded,
    iconName: "subscription.png",
    color: Color(0xFFC62828),
    categoryPk: "5",
    hasHint: true,
    multiple: true,
    nameSuggestions: [
      "Netflix",
      "Spotify",
      "YouTube Premium",
      "Disney+",
      "Prime Video",
      "Max",
      "iCloud",
      "Google One",
      "ChatGPT",
    ],
  ),
  FixedItemPreset(
    id: "transport",
    icon: Icons.directions_bus_rounded,
    iconName: "tram.png",
    color: Color(0xFF00838F),
    categoryPk: "4",
    multiple: true,
    varies: true,
    nameSuggestions: ["Pasajes", "Gasolina", "Parqueadero", "Peajes"],
  ),
  FixedItemPreset(
    id: "groceries",
    icon: Icons.shopping_basket_rounded,
    iconName: "groceries.png",
    color: Color(0xFF558B2F),
    categoryPk: "2",
    varies: true,
  ),
  FixedItemPreset(
    id: "other",
    icon: Icons.add_rounded,
    color: Color(0xFF607D8B),
    categoryPk: "6",
    custom: true,
    hasHint: true,
  ),
];

// Day used for "the last day" of a biweekly salary, the same one the payday
// reminders of the tools use: monthly repeats keep the day number
const List<int> biweeklyPaydays = [15, 30];

// One item added in the onboarding and the transactions it created
class OnboardingFixedItem {
  OnboardingFixedItem({
    required this.preset,
    required this.name,
    required this.amount,
    required this.income,
    required this.days,
    required this.walletPk,
    required this.transactionPks,
  });
  final FixedItemPreset preset;
  final String name;
  // Each time it is paid or received
  final double amount;
  final bool income;
  // One monthly reminder per day
  final List<int> days;
  final String walletPk;
  final List<String> transactionPks;

  // Without dates (a salary that is not fixed) the amount is already monthly
  double get perMonth => days.isEmpty ? amount : amount * days.length;
}

Future<TransactionCategory?> _categoryFor(
    String categoryPk, bool income) async {
  List<TransactionCategory> categories = await database.getAllCategories();
  bool fits(TransactionCategory c) =>
      c.archived == false && c.income == income && c.mainCategoryPk == null;
  return categories
          .where((c) => c.categoryPk == categoryPk && fits(c))
          .firstOrNull ??
      categories.where(fits).firstOrNull;
}

// Expenses are created as subscriptions, like the bills of the payments
// center, so they also show in Subscriptions; income as a repeating
// transaction, like the payday reminders. Both stay unpaid until confirmed
Future<OnboardingFixedItem?> createFixedItem(
  BuildContext context, {
  required FixedItemPreset preset,
  required String name,
  required double amount,
  required bool income,
  required List<int> days,
  required String walletPk,
  PayFrequency? frequency,
}) async {
  TransactionCategory? category = await _categoryFor(preset.categoryPk, income);
  if (category == null) return null;
  DateTime now = DateTime.now();
  List<String> transactionPks = [];
  for (int day in days) {
    int? rowId = await database.createOrUpdateTransaction(
      insert: true,
      Transaction(
        transactionPk: "-1",
        name: name,
        note: "onb-fixed-note".tr(),
        amount: income ? amount.abs() : -amount.abs(),
        categoryFk: category.categoryPk,
        walletFk: walletPk,
        dateCreated: nextDayOfMonth(now, day),
        income: income,
        paid: false,
        skipPaid: false,
        type: income
            ? TransactionSpecialType.repetitive
            : TransactionSpecialType.subscription,
        reoccurrence: BudgetReoccurence.monthly,
        periodLength: 1,
        upcomingTransactionNotification: true,
        createdAnotherFutureTransaction: false,
      ),
    );
    if (rowId != null) {
      transactionPks
          .add((await database.getTransactionFromRowId(rowId)).transactionPk);
    }
  }
  // The salary also fills the income profile the tools read
  if (preset.allowsBiweekly) {
    IncomeProfile profile = IncomeProfile.load();
    profile.frequency = frequency ??
        (days.length > 1 ? PayFrequency.biweekly : PayFrequency.monthly);
    profile.amount = amount;
    if (days.isNotEmpty) profile.payday = days.first;
    profile.payday2 = days.length > 1 ? days[1] : profile.payday;
    // No payday reminders for a salary that is not fixed
    profile.remindersDate = days.isEmpty ? null : now;
    await profile.save();
  }
  if (context.mounted) await setUpcomingNotifications(context);
  return OnboardingFixedItem(
    preset: preset,
    name: name,
    amount: amount,
    income: income,
    days: days,
    walletPk: walletPk,
    transactionPks: transactionPks,
  );
}

Future<void> deleteFixedItem(
    BuildContext context, OnboardingFixedItem item) async {
  await database.deleteTransactions(item.transactionPks);
  if (item.preset.allowsBiweekly) {
    IncomeProfile profile = IncomeProfile.load();
    profile.frequency = null;
    profile.amount = 0;
    profile.remindersDate = null;
    await profile.save();
  }
  if (context.mounted) await setUpcomingNotifications(context);
}

class OnboardingFixedItemsStep extends StatefulWidget {
  const OnboardingFixedItemsStep({required this.items, super.key});
  final ValueNotifier<List<OnboardingFixedItem>> items;

  @override
  State<OnboardingFixedItemsStep> createState() =>
      _OnboardingFixedItemsStepState();
}

class _OnboardingFixedItemsStepState extends State<OnboardingFixedItemsStep> {
  ValueNotifier<List<OnboardingFixedItem>> get items => widget.items;
  // The summary sits under the tiles; it is scrolled into view after each
  // new item so the list and the totals are seen right away
  final GlobalKey summaryKey = GlobalKey();

  Future<void> add(BuildContext context, FixedItemPreset preset) async {
    dynamic created = await openBottomSheet(
      context,
      FixedItemSheet(preset: preset),
    );
    if (created is OnboardingFixedItem) {
      items.value = [...items.value, created];
      await Future.delayed(Duration(milliseconds: 300));
      BuildContext? summary = summaryKey.currentContext;
      if (summary != null && summary.mounted) {
        Scrollable.ensureVisible(
          summary,
          alignment: 1,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  Future<void> remove(BuildContext context, OnboardingFixedItem item) async {
    items.value = items.value.where((i) => i != item).toList();
    await deleteFixedItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return ValueListenableBuilder<List<OnboardingFixedItem>>(
      valueListenable: items,
      builder: (context, added, _) {
        double incomeTotal = 0;
        double expenseTotal = 0;
        for (OnboardingFixedItem item in added) {
          if (item.income) {
            incomeTotal += item.perMonth;
          } else {
            expenseTotal += item.perMonth;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (MapEntry<String, List<FixedItemPreset>> section in {
              "onb-fixed-section-income":
                  fixedItemPresets.where((p) => p.income && !p.custom).toList(),
              "onb-fixed-section-expense": fixedItemPresets
                  .where((p) => !p.income && !p.custom)
                  .toList(),
              "onb-fixed-section-other":
                  fixedItemPresets.where((p) => p.custom).toList(),
            }.entries) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(
                    start: 4, top: 6, bottom: 8),
                child: Row(
                  children: [
                    if (section.key != "onb-fixed-section-other")
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: Icon(
                          section.key == "onb-fixed-section-income"
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 20,
                          color: section.key == "onb-fixed-section-income"
                              ? getColor(context, "incomeAmount")
                              : getColor(context, "expenseAmount"),
                        ),
                      ),
                    Expanded(
                      child: TextFont(
                        text: section.key.tr(),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: OnboardingTileGrid(
                  children: [
                    for (FixedItemPreset preset in section.value)
                      Builder(builder: (context) {
                        int count = added
                            .where((item) => item.preset.id == preset.id)
                            .length;
                        return OnboardingTile(
                          vertical: true,
                          leading: OnboardingAvatar(
                            color: preset.color,
                            icon: preset.icon,
                            iconName: preset.iconName,
                          ),
                          title: preset.title,
                          // The ones that take several say how many there are
                          // and that one more can be added
                          subtitle: preset.multiple && count > 0
                              ? "onb-fixed-added-count"
                                  .tr(namedArgs: {"count": count.toString()})
                              : preset.hint,
                          showCheck: preset.custom == false,
                          selected: preset.custom == false && count > 0,
                          onTap: () => add(context, preset),
                        );
                      }),
                  ],
                ),
              ),
            ],
            AnimatedSize(
              duration: Duration(milliseconds: 250),
              curve: Curves.easeInOutCubic,
              alignment: AlignmentDirectional.topCenter,
              child: added.isEmpty
                  ? SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsetsDirectional.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFont(
                            text: "onb-fixed-added".tr(),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: getColor(context, "canvasContainer"),
                              borderRadius:
                                  BorderRadius.circular(onboardingTileRadius),
                            ),
                            padding: const EdgeInsetsDirectional.symmetric(
                                vertical: 6),
                            child: Column(
                              children: [
                                for (OnboardingFixedItem item in added)
                                  _AddedItemRow(
                                    item: item,
                                    amount: convertToMoney(
                                      allWallets,
                                      item.amount,
                                      currencyKey: allWallets
                                          .indexedByPk[item.walletPk]?.currency,
                                    ),
                                    onDelete: () => remove(context, item),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          TextFont(
                            key: summaryKey,
                            text: "onb-fixed-summary".tr(namedArgs: {
                              "income": convertToMoney(allWallets, incomeTotal),
                              "expenses":
                                  convertToMoney(allWallets, expenseTotal),
                            }),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            maxLines: 4,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AddedItemRow extends StatelessWidget {
  const _AddedItemRow(
      {required this.item, required this.amount, required this.onDelete});
  final OnboardingFixedItem item;
  final String amount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    String when = item.days.isEmpty
        ? "onb-fixed-no-dates".tr()
        : item.days.length > 1
            ? "onb-fixed-twice-on".tr(namedArgs: {
                "first": item.days[0].toString(),
                "second": item.days[1].toString(),
              })
            : "onb-fixed-every-month-on"
                .tr(namedArgs: {"day": item.days.first.toString()});
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
      child: Row(
        children: [
          OnboardingAvatar(
              color: item.preset.color,
              icon: item.preset.icon,
              iconName: item.preset.iconName,
              size: 38),
          SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFont(
                    text: item.name,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 2,
                  ),
                  TextFont(
                    text: item.amount <= 0
                        ? when
                        : (item.income ? "+ " : "- ") + amount + " · " + when,
                    fontSize: 14,
                    maxLines: 2,
                    textColor: item.income
                        ? getColor(context, "incomeAmount")
                        : getColor(context, "black").withOpacity(0.65),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: "delete".tr(),
            iconSize: 26,
            padding: const EdgeInsetsDirectional.all(12),
            onPressed: onDelete,
            icon: Icon(
              appStateSettings["outlinedIcons"]
                  ? Icons.delete_outlined
                  : Icons.delete_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

// Amount, day and, for the salary, how often. Pops with the created item
class FixedItemSheet extends StatefulWidget {
  const FixedItemSheet({required this.preset, super.key});
  final FixedItemPreset preset;

  @override
  State<FixedItemSheet> createState() => _FixedItemSheetState();
}

class _FixedItemSheetState extends State<FixedItemSheet> {
  late final TextEditingController nameController = TextEditingController();
  late final TextEditingController amountController = TextEditingController();
  late final TextEditingController dayController =
      TextEditingController(text: widget.preset.defaultDay.toString());
  // The two days of a biweekly salary
  final TextEditingController firstPaydayController =
      TextEditingController(text: biweeklyPaydays[0].toString());
  final TextEditingController secondPaydayController =
      TextEditingController(text: biweeklyPaydays[1].toString());
  final FocusNode secondPaydayFocus = FocusNode();
  String? secondPaydayError;
  final FocusNode nameFocus = FocusNode();
  final FocusNode amountFocus = FocusNode();
  final FocusNode dayFocus = FocusNode();

  late bool income = widget.preset.income;
  PayFrequency frequency = PayFrequency.monthly;
  bool get biweekly => frequency == PayFrequency.biweekly;
  // A salary that is not fixed: no dates, the amount is optional
  bool get noFixedPay =>
      widget.preset.allowsBiweekly && frequency == PayFrequency.variable;
  String walletPk = appStateSettings["selectedWalletPk"]?.toString() ?? "0";
  String? nameError;
  String? amountError;
  String? dayError;
  bool saveFailed = false;
  bool saving = false;

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    dayController.dispose();
    firstPaydayController.dispose();
    secondPaydayController.dispose();
    secondPaydayFocus.dispose();
    nameFocus.dispose();
    amountFocus.dispose();
    dayFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    String typed = nameController.text.trim();
    // Without a name, one of several still gets the title of its tile
    String name = widget.preset.custom
        ? typed
        : widget.preset.multiple && typed.isNotEmpty
            ? typed
            : widget.preset.title;
    double? amount = parseToolNumber(amountController.text);
    int? day = int.tryParse(
        (biweekly ? firstPaydayController : dayController).text.trim());
    int? secondDay = int.tryParse(secondPaydayController.text.trim());
    bool validDay(int? d) => d != null && d >= 1 && d <= 31;
    setState(() {
      nameError = widget.preset.custom && name.isEmpty
          ? "onb-fixed-name-required".tr()
          : null;
      amountError = noFixedPay == false && (amount == null || amount <= 0)
          ? "onb-fixed-amount-required".tr()
          : null;
      dayError = noFixedPay == false && !validDay(day)
          ? "onb-fixed-day-invalid".tr()
          : null;
      secondPaydayError = biweekly && !validDay(secondDay)
          ? "onb-fixed-day-invalid".tr()
          : biweekly && secondDay == day
              ? "onb-fixed-days-different".tr()
              : null;
      saveFailed = false;
    });
    if (nameError != null) return nameFocus.requestFocus();
    if (amountError != null) return amountFocus.requestFocus();
    if (dayError != null) return dayFocus.requestFocus();
    if (secondPaydayError != null) return secondPaydayFocus.requestFocus();
    saving = true;
    OnboardingFixedItem? item = await createFixedItem(
      context,
      preset: widget.preset,
      name: name,
      amount: (amount ?? 0).abs(),
      income: income,
      days: noFixedPay
          ? []
          : biweekly
              ? ([day!, secondDay!]..sort())
              : [day!],
      walletPk: walletPk,
      frequency: widget.preset.allowsBiweekly ? frequency : null,
    );
    saving = false;
    if (!mounted) return;
    if (item == null) {
      setState(() => saveFailed = true);
      return;
    }
    popRoute(context, item);
  }

  // What was typed keeps meaning the same money a month: 2.000.000 monthly
  // become 1.000.000 each fortnight, and back
  void changeFrequency(PayFrequency next) {
    double? typed = parseToolNumber(amountController.text);
    if (typed != null && typed > 0 && next != frequency) {
      double monthly = frequency == PayFrequency.biweekly ? typed * 2 : typed;
      double converted = next == PayFrequency.biweekly ? monthly / 2 : monthly;
      amountController.text = groupThousands(converted.round().toString());
    }
    frequency = next;
    amountError = null;
    dayError = null;
    secondPaydayError = null;
  }

  Widget sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
      child: TextFont(text: text, fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  Widget twoChoices({
    required String firstTitle,
    String? firstSubtitle,
    required String secondTitle,
    String? secondSubtitle,
    required bool firstSelected,
    required ValueChanged<bool> onFirst,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: OnboardingTile(
                title: firstTitle,
                subtitle: firstSubtitle,
                selected: firstSelected,
                onTap: () => onFirst(true),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: OnboardingTile(
                title: secondTitle,
                subtitle: secondSubtitle,
                selected: firstSelected == false,
                onTap: () => onFirst(false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    FixedItemPreset preset = widget.preset;
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return PopupFramework(
      title: preset.custom ? "onb-fixed-other-title".tr() : preset.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preset.asksName)
            OnboardingField(
              label: preset.custom
                  ? "onb-fixed-name".tr()
                  : "onb-fixed-which".tr(),
              hint: preset.custom
                  ? "onb-fixed-name-hint".tr()
                  : "onb-fixed-${preset.id}-name-hint".tr(),
              controller: nameController,
              focusNode: nameFocus,
              required: preset.custom,
              error: nameError,
              onChanged: (_) {
                setState(() => nameError = null);
              },
            ),
          if (preset.nameSuggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 14),
              child: SelectChips<String>(
                items: preset.nameSuggestions,
                wrapped: true,
                allowMultipleSelected: false,
                padding: EdgeInsetsDirectional.zero,
                getLabel: (name) => name,
                getSelected: (name) => nameController.text.trim() == name,
                onSelected: (name) => setState(() {
                  nameController.text = name;
                  nameError = null;
                }),
              ),
            ),
          if (preset.custom) ...[
            twoChoices(
              firstTitle: "onb-fixed-type-expense".tr(),
              secondTitle: "onb-fixed-type-income".tr(),
              firstSelected: income == false,
              onFirst: (expense) => setState(() => income = !expense),
            ),
          ],
          if (preset.allowsBiweekly) ...[
            sectionLabel("onb-fixed-frequency".tr()),
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 16),
              child: OnboardingTileGrid(
                minTileWidth: 150,
                maxColumns: 2,
                children: [
                  for (MapEntry<PayFrequency, List<String>> option in {
                    PayFrequency.monthly: [
                      "monthly".tr(),
                      "onb-fixed-monthly-hint".tr()
                    ],
                    PayFrequency.biweekly: [
                      "onb-fixed-biweekly".tr(),
                      "onb-fixed-biweekly-hint".tr()
                    ],
                    PayFrequency.variable: [
                      "onb-fixed-no-fixed-pay".tr(),
                      "onb-fixed-no-fixed-pay-hint".tr()
                    ],
                  }.entries)
                    OnboardingTile(
                      title: option.value[0],
                      subtitle: option.value[1],
                      selected: frequency == option.key,
                      onTap: () => setState(() => changeFrequency(option.key)),
                    ),
                ],
              ),
            ),
          ],
          OnboardingField(
            label: noFixedPay
                ? "onb-fixed-amount-no-fixed-pay".tr()
                : biweekly
                    ? "onb-fixed-amount-each".tr()
                    : preset.varies
                        ? "onb-fixed-amount-approx".tr()
                        : "onb-fixed-amount".tr(),
            hint: "0",
            controller: amountController,
            focusNode: amountFocus,
            required: noFixedPay == false,
            error: amountError,
            onChanged: (_) {
              if (amountError != null) setState(() => amountError = null);
            },
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            prefix: "\$ ",
            amount: true,
          ),
          if (biweekly)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: OnboardingField(
                    label: "onb-fixed-first-payday".tr(),
                    hint: "15",
                    controller: firstPaydayController,
                    focusNode: dayFocus,
                    required: true,
                    error: dayError,
                    onChanged: (_) {
                      if (dayError != null) setState(() => dayError = null);
                    },
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: OnboardingField(
                    label: "onb-fixed-second-payday".tr(),
                    hint: "30",
                    controller: secondPaydayController,
                    focusNode: secondPaydayFocus,
                    required: true,
                    error: secondPaydayError,
                    onChanged: (_) {
                      if (secondPaydayError != null) {
                        setState(() => secondPaydayError = null);
                      }
                    },
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          if (biweekly == false && noFixedPay == false)
            OnboardingField(
              label: "onb-fixed-day".tr(),
              hint: "onb-fixed-day-hint".tr(),
              controller: dayController,
              focusNode: dayFocus,
              required: true,
              error: dayError,
              onChanged: (_) {
                if (dayError != null) setState(() => dayError = null);
              },
              keyboardType: TextInputType.number,
            ),
          if (preset.allowsBiweekly == false || noFixedPay)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 14),
              child: TextFont(
                text: noFixedPay
                    ? "onb-fixed-no-fixed-pay-note".tr()
                    : preset.hasNote
                        ? "onb-fixed-${preset.id}-note".tr()
                        : preset.varies
                            ? "onb-fixed-varies-note".tr()
                            : "onb-fixed-repeats-monthly".tr(),
                fontSize: 14,
                maxLines: 3,
                textColor: getColor(context, "black").withOpacity(0.6),
              ),
            ),
          if (allWallets.list.length > 1)
            StreamBuilder<List<WalletGroup>>(
              stream: database.watchAllWalletGroups(),
              builder: (context, snapshot) {
                Map<String, String> groupNames = {
                  for (WalletGroup g in snapshot.data ?? [])
                    g.walletGroupPk: g.name
                };
                return Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      sectionLabel("onb-fixed-pocket".tr()),
                      OnboardingTileGrid(
                        minTileWidth: 150,
                        maxColumns: 2,
                        children: [
                          for (TransactionWallet wallet in allWallets.list)
                            OnboardingTile(
                              title: groupNames[wallet.walletGroupFk] ??
                                  wallet.name,
                              subtitle: groupNames[wallet.walletGroupFk] == null
                                  ? null
                                  : wallet.name,
                              selected: walletPk == wallet.walletPk,
                              onTap: () =>
                                  setState(() => walletPk = wallet.walletPk),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          if (saveFailed)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: OnboardingErrorText(text: "onb-fixed-save-failed".tr()),
            ),
          Button(
            label: "add".tr(),
            fontSize: 17,
            expandedLayout: true,
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 18),
            color: Theme.of(context).colorScheme.primary,
            textColor: Theme.of(context).colorScheme.onPrimary,
            onTap: submit,
          ),
        ],
      ),
    );
  }
}
