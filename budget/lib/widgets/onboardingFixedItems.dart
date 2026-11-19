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
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/onboardingWidgets.dart';
import 'package:budget/widgets/openBottomSheet.dart';
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
    required this.color,
    required this.categoryPk,
    this.income = false,
    this.defaultDay = 1,
    this.allowsBiweekly = false,
    this.custom = false,
    this.hasHint = false,
  });
  // Title key is "onb-fixed-<id>", the optional hint "onb-fixed-<id>-hint"
  final String id;
  final IconData icon;
  final Color color;
  // Default category it goes into; falls back to the first one that fits
  final String categoryPk;
  final bool income;
  final int defaultDay;
  final bool allowsBiweekly;
  // "Other": the name and the direction are typed in the sheet
  final bool custom;
  final bool hasHint;

  String get title => "onb-fixed-$id".tr();
  String? get hint => hasHint ? "onb-fixed-$id-hint".tr() : null;
}

const List<FixedItemPreset> fixedItemPresets = [
  FixedItemPreset(
    id: "salary",
    icon: Icons.payments_rounded,
    color: Color(0xFF2E7D32),
    categoryPk: "11",
    income: true,
    defaultDay: 30,
    allowsBiweekly: true,
  ),
  FixedItemPreset(
    id: "rent",
    icon: Icons.home_rounded,
    color: Color(0xFFEF6C00),
    categoryPk: "6",
  ),
  FixedItemPreset(
    id: "utilities",
    icon: Icons.lightbulb_rounded,
    color: Color(0xFFF9A825),
    categoryPk: "6",
    defaultDay: 10,
    hasHint: true,
  ),
  FixedItemPreset(
    id: "phone",
    icon: Icons.wifi_rounded,
    color: Color(0xFF1565C0),
    categoryPk: "6",
    defaultDay: 15,
  ),
  FixedItemPreset(
    id: "loan",
    icon: Icons.account_balance_rounded,
    color: Color(0xFF6A1B9A),
    categoryPk: "6",
    defaultDay: 5,
  ),
  FixedItemPreset(
    id: "subscriptions",
    icon: Icons.subscriptions_rounded,
    color: Color(0xFFC62828),
    categoryPk: "5",
    hasHint: true,
  ),
  FixedItemPreset(
    id: "transport",
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF00838F),
    categoryPk: "4",
  ),
  FixedItemPreset(
    id: "groceries",
    icon: Icons.shopping_basket_rounded,
    color: Color(0xFF558B2F),
    categoryPk: "2",
  ),
  FixedItemPreset(
    id: "other",
    icon: Icons.add_rounded,
    color: Color(0xFF607D8B),
    categoryPk: "6",
    custom: true,
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

  double get perMonth => amount * days.length;
}

Future<TransactionCategory?> _categoryFor(String categoryPk, bool income) async {
  List<TransactionCategory> categories = await database.getAllCategories();
  bool fits(TransactionCategory c) =>
      c.archived == false && c.income == income && c.mainCategoryPk == null;
  return categories.where((c) => c.categoryPk == categoryPk && fits(c)).firstOrNull ??
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
    profile.frequency =
        days.length > 1 ? PayFrequency.biweekly : PayFrequency.monthly;
    profile.amount = amount;
    profile.payday = days.first;
    profile.remindersDate = now;
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
            OnboardingTileGrid(
              children: [
                for (FixedItemPreset preset in fixedItemPresets)
                  OnboardingTile(
                    vertical: true,
                    leading: OnboardingAvatar(
                      color: preset.color,
                      icon: preset.icon,
                    ),
                    title: preset.title,
                    subtitle: preset.hint,
                    showCheck: preset.custom == false,
                    selected: preset.custom == false &&
                        added.any((item) => item.preset.id == preset.id),
                    onTap: () => add(context, preset),
                  ),
              ],
            ),
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
                              borderRadius: BorderRadius.circular(
                                  onboardingTileRadius),
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
                                          .indexedByPk[item.walletPk]
                                          ?.currency,
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
                              "income":
                                  convertToMoney(allWallets, incomeTotal),
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
    String when = item.days.length > 1
        ? "onb-fixed-biweekly-hint".tr()
        : "onb-fixed-every-month-on"
            .tr(namedArgs: {"day": item.days.first.toString()});
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
      child: Row(
        children: [
          OnboardingAvatar(
              color: item.preset.color, icon: item.preset.icon, size: 38),
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
                    text: (item.income ? "+ " : "- ") + amount + " · " + when,
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
  final FocusNode nameFocus = FocusNode();
  final FocusNode amountFocus = FocusNode();
  final FocusNode dayFocus = FocusNode();

  late bool income = widget.preset.income;
  bool biweekly = false;
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
    nameFocus.dispose();
    amountFocus.dispose();
    dayFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    String name = widget.preset.custom
        ? nameController.text.trim()
        : widget.preset.title;
    double? amount = parseToolNumber(amountController.text);
    int? day = int.tryParse(dayController.text.trim());
    setState(() {
      nameError = widget.preset.custom && name.isEmpty
          ? "onb-fixed-name-required".tr()
          : null;
      amountError = amount == null || amount <= 0
          ? "onb-fixed-amount-required".tr()
          : null;
      dayError = biweekly == false && (day == null || day < 1 || day > 31)
          ? "onb-fixed-day-invalid".tr()
          : null;
      saveFailed = false;
    });
    if (nameError != null) return nameFocus.requestFocus();
    if (amountError != null) return amountFocus.requestFocus();
    if (dayError != null) return dayFocus.requestFocus();
    saving = true;
    OnboardingFixedItem? item = await createFixedItem(
      context,
      preset: widget.preset,
      name: name,
      amount: amount!.abs(),
      income: income,
      days: biweekly ? biweeklyPaydays : [day!],
      walletPk: walletPk,
    );
    saving = false;
    if (!mounted) return;
    if (item == null) {
      setState(() => saveFailed = true);
      return;
    }
    popRoute(context, item);
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
          if (preset.custom) ...[
            OnboardingField(
              label: "onb-fixed-name".tr(),
              hint: "onb-fixed-name-hint".tr(),
              controller: nameController,
              focusNode: nameFocus,
              required: true,
              error: nameError,
              onChanged: (_) {
                if (nameError != null) setState(() => nameError = null);
              },
            ),
            twoChoices(
              firstTitle: "onb-fixed-type-expense".tr(),
              secondTitle: "onb-fixed-type-income".tr(),
              firstSelected: income == false,
              onFirst: (expense) => setState(() => income = !expense),
            ),
          ],
          if (preset.allowsBiweekly) ...[
            sectionLabel("onb-fixed-frequency".tr()),
            twoChoices(
              firstTitle: "monthly".tr(),
              firstSubtitle: "onb-fixed-monthly-hint".tr(),
              secondTitle: "onb-fixed-biweekly".tr(),
              secondSubtitle: "onb-fixed-biweekly-hint".tr(),
              firstSelected: biweekly == false,
              onFirst: (monthly) => setState(() => biweekly = !monthly),
            ),
          ],
          OnboardingField(
            label: biweekly
                ? "onb-fixed-amount-each".tr()
                : "onb-fixed-amount".tr(),
            hint: "0",
            controller: amountController,
            focusNode: amountFocus,
            required: true,
            error: amountError,
            onChanged: (_) {
              if (amountError != null) setState(() => amountError = null);
            },
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          if (biweekly == false)
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
          if (preset.allowsBiweekly == false)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 14),
              child: TextFont(
                text: "onb-fixed-repeats-monthly".tr(),
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
                              subtitle: groupNames[wallet.walletGroupFk] ==
                                      null
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
