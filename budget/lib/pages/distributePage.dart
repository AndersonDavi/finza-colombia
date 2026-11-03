import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/editWalletsPage.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/syncClient.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/saveBottomButton.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Splits an amount from one account into several pockets (of any group or
// account) at once. Each line is a fixed amount, a percent or the rest.
// The splits can be saved as templates, kept in the settings under
// "distributionTemplates".

enum DistributionMode { amount, percent, rest }

class DistributionLine {
  DistributionLine(this.walletPk,
      {this.mode = DistributionMode.amount, this.value = 0});
  String walletPk;
  DistributionMode mode;
  double value;

  Map<String, dynamic> toJson() =>
      {"wallet": walletPk, "mode": mode.name, "value": value};

  static DistributionLine fromJson(Map<String, dynamic> json) =>
      DistributionLine(
        json["wallet"],
        mode: DistributionMode.values.firstWhere(
            (m) => m.name == json["mode"],
            orElse: () => DistributionMode.amount),
        value: (json["value"] ?? 0).toDouble(),
      );
}

List<Map<String, dynamic>> getDistributionTemplates() =>
    List<Map<String, dynamic>>.from(
        (appStateSettings["distributionTemplates"] ?? [])
            .map((t) => Map<String, dynamic>.from(t)));

// A new income in the source account of a template (the quincena landing in
// the Libre, say) offers to split it with that template from a snackbar.
// Only from the template's "suggestFrom" amount up, so small incomes stay
// quiet. Transfers between accounts never count as income here.
void suggestDistributionAfterIncome(Transaction transaction) {
  if (transaction.income != true ||
      transaction.amount <= 0 ||
      transaction.type != null ||
      transaction.pairedTransactionFk != null ||
      transaction.categoryFk == "0") return;
  double suggestFrom(Map<String, dynamic> t) =>
      (t["suggestFrom"] as num?)?.toDouble() ?? 0;
  // The template with the highest minimum the income reaches
  List<Map<String, dynamic>> matching = getDistributionTemplates()
      .where((t) =>
          t["source"] == transaction.walletFk &&
          suggestFrom(t) > 0 &&
          transaction.amount >= suggestFrom(t))
      .toList()
    ..sort((a, b) => suggestFrom(b).compareTo(suggestFrom(a)));
  Map<String, dynamic>? template = matching.firstOrNull;
  if (template == null) return;
  openSnackbar(SnackbarMessage(
    title: "distribute-income".tr(),
    description: "tap-to-use-template".tr(namedArgs: {"name": template["name"] ?? ""}),
    icon: appStateSettings["outlinedIcons"]
        ? Icons.call_split_outlined
        : Icons.call_split_rounded,
    timeout: Duration(seconds: 8),
    onTap: () => pushRoute(
      null,
      DistributePage(
        sourceWalletPk: transaction.walletFk,
        initialTotal: transaction.amount,
        initialTemplateId: template["id"],
      ),
    ),
  ));
}

class DistributePage extends StatefulWidget {
  const DistributePage(
      {this.sourceWalletPk,
      this.initialTotal,
      this.initialTemplateId,
      super.key});
  final String? sourceWalletPk;
  final double? initialTotal;
  final String? initialTemplateId;

  @override
  State<DistributePage> createState() => _DistributePageState();
}

class _DistributePageState extends State<DistributePage> {
  late String? sourceWalletPk =
      widget.sourceWalletPk ?? appStateSettings["selectedWalletPk"];
  late double total = widget.initialTotal ?? 0;
  List<DistributionLine> lines = [];
  String? templateId;
  String? templateName;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic>? template = getDistributionTemplates()
        .where((t) => t["id"] == widget.initialTemplateId)
        .firstOrNull;
    if (template != null) applyTemplate(template);
  }

  double lineAmount(DistributionLine line) {
    if (line.mode == DistributionMode.amount) return line.value;
    if (line.mode == DistributionMode.percent) return total * line.value / 100;
    double others = lines
        .where((l) => l != line && l.mode != DistributionMode.rest)
        .fold(0.0, (sum, l) => sum + lineAmount(l));
    return (total - others) < 0 ? 0 : total - others;
  }

  double get assigned => lines.fold(0.0, (sum, l) => sum + lineAmount(l));
  double get remaining => total - assigned;

  void loadTemplate(Map<String, dynamic> template) {
    setState(() => applyTemplate(template));
  }

  void applyTemplate(Map<String, dynamic> template) {
    templateId = template["id"];
    templateName = template["name"];
    if (template["source"] != null) sourceWalletPk = template["source"];
    lines = [
      for (var line in (template["lines"] ?? []))
        DistributionLine.fromJson(Map<String, dynamic>.from(line))
    ];
  }

  void newTemplate() {
    setState(() {
      templateId = null;
      templateName = null;
      lines = [];
    });
  }

  Future<void> saveTemplate() async {
    String? name = templateName;
    bool submitted = false;
    await openBottomSheet(
      context,
      popupWithKeyboard: true,
      PopupFramework(
        title: "template-name".tr(),
        child: SelectText(
          buttonLabel: "save".tr(),
          setSelectedText: (text) => name = text,
          nextWithInput: (text) {
            name = text;
            submitted = true;
          },
          selectedText: templateName ?? "",
          placeholder: "template-name-placeholder".tr(),
        ),
      ),
    );
    if (!submitted || name == null || name!.trim() == "") return;
    List<Map<String, dynamic>> templates = getDistributionTemplates();
    Map<String, dynamic>? existing =
        templates.where((t) => t["id"] == templateId).firstOrNull;
    Map<String, dynamic> template = {
      "id": templateId ?? uuid.v4(),
      "name": name!.trim(),
      "source": sourceWalletPk,
      "lines": [for (var line in lines) line.toJson()],
      // New templates suggest themselves from half of the amount split now
      "suggestFrom": existing == null
          ? (total > 0 ? (total / 2).roundToDouble() : null)
          : existing["suggestFrom"],
    };
    int index = templates.indexWhere((t) => t["id"] == template["id"]);
    if (index >= 0)
      templates[index] = template;
    else
      templates.add(template);
    await updateSettings("distributionTemplates", templates,
        updateGlobalState: false);
    await markSyncedSettingChanged("distributionTemplates");
    setState(() {
      templateId = template["id"];
      templateName = template["name"];
    });
  }

  Future<void> deleteTemplate(Map<String, dynamic> template) async {
    dynamic confirmed = await openPopup(
      context,
      title: asQuestion("delete-template".tr()),
      description: template["name"],
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outlined
          : Icons.delete_rounded,
      onSubmit: () => popRoute(context, true),
      onSubmitLabel: "delete".tr(),
      onCancel: () => popRoute(context, false),
      onCancelLabel: "cancel".tr(),
    );
    if (confirmed != true) return;
    List<Map<String, dynamic>> templates = getDistributionTemplates()
      ..removeWhere((t) => t["id"] == template["id"]);
    await updateSettings("distributionTemplates", templates,
        updateGlobalState: false);
    await markSyncedSettingChanged("distributionTemplates");
    if (templateId == template["id"]) newTemplate();
    setState(() {});
  }

  Future<void> setSuggestFrom(Map<String, dynamic> template) async {
    double? amount = await enterNumber(
      title: "suggest-from-title".tr(),
      initial: (template["suggestFrom"] as num?)?.toDouble(),
      currency: Provider.of<AllWallets>(context, listen: false)
          .indexedByPk[template["source"]]
          ?.currency,
    );
    if (amount == null) return;
    List<Map<String, dynamic>> templates = getDistributionTemplates();
    int index = templates.indexWhere((t) => t["id"] == template["id"]);
    if (index < 0) return;
    templates[index]["suggestFrom"] = amount <= 0 ? null : amount;
    await updateSettings("distributionTemplates", templates,
        updateGlobalState: false);
    await markSyncedSettingChanged("distributionTemplates");
    setState(() {});
  }

  Future<double?> enterNumber(
      {required String title, double? initial, String? currency}) async {
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
            setSelectedAmount: (amount, calculation) => result = amount.abs(),
            next: () => popRoute(context),
            nextLabel: "set-amount".tr(),
          ),
        ),
      ),
    );
    return result;
  }

  Future<void> addLine() async {
    TransactionWallet? wallet = await selectWalletPopup(
      context,
      allowEditWallet: false,
      title: "add-pocket".tr(),
      removeWalletPks: [
        if (sourceWalletPk != null) sourceWalletPk!,
        for (var line in lines) line.walletPk,
      ],
    );
    if (wallet == null) return;
    setState(() => lines.add(DistributionLine(wallet.walletPk)));
  }

  Future<void> distribute(AllWallets allWallets) async {
    TransactionWallet? source = allWallets.indexedByPk[sourceWalletPk];
    if (source == null) return;
    int count = 0;
    for (DistributionLine line in lines) {
      double amount = lineAmount(line);
      TransactionWallet? destination = allWallets.indexedByPk[line.walletPk];
      if (amount <= 0 || destination == null) continue;
      bool done = await createBalanceTransfer(
        allWallets,
        // createBalanceTransfer takes the amount in the primary currency
        amount: amount *
            amountRatioToPrimaryCurrencyGivenPk(allWallets, source.walletPk),
        walletFrom: source,
        walletTo: destination,
        title: templateName ?? "",
        showSnackbar: false,
      );
      if (done) count++;
    }
    openSnackbar(
      SnackbarMessage(
        title: "distributed".tr(),
        description: count.toString() +
            " " +
            (count == 1 ? "pocket".tr() : "pockets".tr()).toLowerCase(),
        icon: appStateSettings["outlinedIcons"]
            ? Icons.call_split_outlined
            : Icons.call_split_rounded,
      ),
    );
    savingHapticFeedback();
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    TransactionWallet? source = allWallets.indexedByPk[sourceWalletPk];
    String money(double amount, {String? currency}) => convertToMoney(
        allWallets, amount,
        currencyKey: currency ?? source?.currency, forceAbsoluteZero: false);
    return StreamBuilder<List<WalletWithDetails>>(
      stream: database.watchAllWalletsWithDetails(),
      builder: (context, snapshot) {
        Map<String, double> balances = {
          for (var w in snapshot.data ?? [])
            w.wallet.walletPk: w.totalSpent ?? 0
        };
        double sourceBalance = balances[sourceWalletPk] ?? 0;
        List<Map<String, dynamic>> templates = getDistributionTemplates();
        bool canDistribute = source != null &&
            total > 0 &&
            remaining >= -0.005 &&
            lines.any((l) => lineAmount(l) > 0);
        return PageFramework(
          title: "distribute".tr(),
          dragDownToDismiss: true,
          staticOverlay: Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: SaveBottomButton(
              label: remaining < -0.005
                  ? "over-assigned".tr()
                  : "distribute".tr() +
                      (assigned > 0 ? " " + money(assigned) : ""),
              disabled: !canDistribute,
              onTap: () => distribute(allWallets),
            ),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: CenteredPageContent(
                maxWidth: 620,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Templates
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var template in templates)
                          DistributeChip(
                            label: template["name"],
                            selected: template["id"] == templateId,
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.bookmark_outlined
                                : Icons.bookmark_rounded,
                            onTap: () => loadTemplate(template),
                            onLongPress: () => deleteTemplate(template),
                          ),
                        DistributeChip(
                          label: "new".tr(),
                          selected: templateId == null,
                          icon: appStateSettings["outlinedIcons"]
                              ? Icons.add_outlined
                              : Icons.add_rounded,
                          onTap: newTemplate,
                        ),
                      ],
                    ),
                    // When the selected template pops up after an income
                    for (var template
                        in templates.where((t) => t["id"] == templateId))
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: DistributeChip(
                            label: (template["suggestFrom"] as num?) == null
                                ? "never-suggest".tr()
                                : "suggest-from".tr() +
                                    " " +
                                    money(
                                        (template["suggestFrom"] as num)
                                            .toDouble(),
                                        currency: allWallets
                                            .indexedByPk[template["source"]]
                                            ?.currency),
                            selected: false,
                            icon: appStateSettings["outlinedIcons"]
                                ? Icons.notifications_outlined
                                : Icons.notifications_rounded,
                            onTap: () => setSuggestFrom(template),
                          ),
                        ),
                      ),
                    SizedBox(height: 16),
                    // From
                    DistributeCard(
                      onTap: () async {
                        TransactionWallet? picked = await selectWalletPopup(
                          context,
                          allowEditWallet: false,
                          selectedWallet: source,
                          title: "from-account".tr(),
                        );
                        if (picked != null)
                          setState(() {
                            sourceWalletPk = picked.walletPk;
                            lines.removeWhere(
                                (l) => l.walletPk == picked.walletPk);
                          });
                      },
                      color: HexColor(source?.colour,
                          defaultColor: Theme.of(context).colorScheme.primary),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFont(
                                  text: "from-account".tr(),
                                  fontSize: 12,
                                  textColor: getColor(context, "textLight"),
                                ),
                                TextFont(
                                  text: source == null
                                      ? "select-account".tr()
                                      : getWalletStringName(allWallets, source),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              TextFont(
                                text: money(sourceBalance),
                                fontSize: 13,
                                textColor: getColor(context, "textLight"),
                              ),
                              if (assigned > 0)
                                TextFont(
                                  text: "→ " + money(sourceBalance - assigned),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10),
                    // Total
                    DistributeCard(
                      onTap: () async {
                        double? amount = await enterNumber(
                            title: "amount-to-distribute".tr(),
                            initial: total,
                            currency: source?.currency);
                        if (amount != null) setState(() => total = amount);
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFont(
                                  text: "amount-to-distribute".tr(),
                                  fontSize: 12,
                                  textColor: getColor(context, "textLight"),
                                ),
                                TextFont(
                                  text: money(total),
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ],
                            ),
                          ),
                          if (sourceBalance > 0)
                            DistributeChip(
                              label: "whole-balance".tr(),
                              selected: total == sourceBalance,
                              onTap: () =>
                                  setState(() => total = sourceBalance),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14),
                    DistributionBar(
                      total: total,
                      segments: [
                        for (var line in lines)
                          (
                            HexColor(allWallets.indexedByPk[line.walletPk]?.colour,
                                defaultColor:
                                    Theme.of(context).colorScheme.primary),
                            lineAmount(line)
                          )
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        TextFont(
                          text: "assigned".tr() + " " + money(assigned),
                          fontSize: 13,
                          textColor: getColor(context, "textLight"),
                        ),
                        Spacer(),
                        TextFont(
                          text: "unassigned".tr() + " " + money(remaining),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          textColor: remaining < -0.005
                              ? getColor(context, "expenseAmount")
                              : getColor(context, "textLight"),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    // Lines
                    for (int i = 0; i < lines.length; i++)
                      DistributionLineCard(
                        key: ValueKey(lines[i].walletPk),
                        line: lines[i],
                        wallet: allWallets.indexedByPk[lines[i].walletPk],
                        amount: lineAmount(lines[i]),
                        balance: balances[lines[i].walletPk] ?? 0,
                        ratio: source == null
                            ? 1
                            : (amountRatioFromToCurrency(
                                    source.currency ?? "",
                                    allWallets.indexedByPk[lines[i].walletPk]
                                            ?.currency ??
                                        "") ??
                                1),
                        restTaken: lines.any((l) =>
                            l != lines[i] && l.mode == DistributionMode.rest),
                        onModeChanged: (mode) =>
                            setState(() => lines[i].mode = mode),
                        onEditValue: () async {
                          double? value = await enterNumber(
                            title: lines[i].mode == DistributionMode.percent
                                ? "percent".tr()
                                : "amount".tr(),
                            initial: lines[i].value,
                            currency: lines[i].mode == DistributionMode.percent
                                ? null
                                : source?.currency,
                          );
                          if (value != null)
                            setState(() => lines[i].value = value);
                        },
                        onRemove: () => setState(() => lines.removeAt(i)),
                      ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: DistributeCard(
                            onTap: addLine,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(appStateSettings["outlinedIcons"]
                                    ? Icons.add_outlined
                                    : Icons.add_rounded),
                                SizedBox(width: 8),
                                TextFont(text: "add-pocket".tr(), fontSize: 15),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        DistributeCard(
                          onTap: lines.isEmpty ? null : saveTemplate,
                          child: Row(
                            children: [
                              Icon(appStateSettings["outlinedIcons"]
                                  ? Icons.bookmark_add_outlined
                                  : Icons.bookmark_add_rounded),
                              SizedBox(width: 8),
                              TextFont(
                                  text: "save-template".tr(), fontSize: 15),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 110),
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

class DistributeCard extends StatelessWidget {
  const DistributeCard(
      {required this.child, this.onTap, this.color, super.key});
  final Widget child;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      borderRadius: 16,
      color: getColor(context, "lightDarkAccentHeavyLight"),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: color == null
              ? null
              : Border.all(color: color!.withOpacity(0.6), width: 2),
        ),
        child: child,
      ),
    );
  }
}

class DistributeChip extends StatelessWidget {
  const DistributeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      borderRadius: 12,
      color: selected
          ? Theme.of(context).colorScheme.secondaryContainer
          : getColor(context, "lightDarkAccentHeavyLight"),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16), SizedBox(width: 6)],
            TextFont(text: label, fontSize: 14),
          ],
        ),
      ),
    );
  }
}

// Stacked bar with the part of the total each pocket gets
class DistributionBar extends StatelessWidget {
  const DistributionBar({required this.total, required this.segments, super.key});
  final double total;
  final List<(Color, double)> segments;

  @override
  Widget build(BuildContext context) {
    double used = segments.fold(0.0, (sum, s) => sum + s.$2);
    double scale = total <= 0 ? 0 : 1 / (used > total ? used : total);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 14,
        child: LayoutBuilder(builder: (context, constraints) {
          return Stack(
            children: [
              Container(color: getColor(context, "lightDarkAccentHeavyLight")),
              Row(
                children: [
                  for (var (color, amount) in segments)
                    AnimatedContainer(
                      duration: Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * amount * scale,
                      color: color,
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}

class DistributionLineCard extends StatelessWidget {
  const DistributionLineCard({
    required this.line,
    required this.wallet,
    required this.amount,
    required this.balance,
    required this.ratio,
    required this.restTaken,
    required this.onModeChanged,
    required this.onEditValue,
    required this.onRemove,
    super.key,
  });
  final DistributionLine line;
  final TransactionWallet? wallet;
  final double amount;
  final double balance;
  // From the source currency to this pocket's
  final double ratio;
  // Another line already takes the rest
  final bool restTaken;
  final Function(DistributionMode mode) onModeChanged;
  final VoidCallback onEditValue;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Color color = HexColor(wallet?.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    String money(double value) =>
        convertToMoney(allWallets, value, currencyKey: wallet?.currency);
    Widget modeButton(DistributionMode mode, String label) {
      bool selected = line.mode == mode;
      bool disabled = mode == DistributionMode.rest && restTaken;
      return Tappable(
        borderRadius: 8,
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        onTap: disabled ? null : () => onModeChanged(mode),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 5),
          child: TextFont(
            text: label,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            textColor: disabled
                ? getColor(context, "textLight").withOpacity(0.4)
                : null,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Container(
        padding: const EdgeInsetsDirectional.only(
            start: 14, end: 6, top: 10, bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.08),
          border: BorderDirectional(
            start: BorderSide(color: color, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: getWalletStringName(allWallets, wallet),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 1,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(
                    appStateSettings["outlinedIcons"]
                        ? Icons.close_outlined
                        : Icons.close_rounded,
                    size: 18,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: getColor(context, "lightDarkAccentHeavyLight"),
                  ),
                  padding: const EdgeInsetsDirectional.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      modeButton(DistributionMode.amount, "\$"),
                      modeButton(DistributionMode.percent, "%"),
                      modeButton(DistributionMode.rest, "rest".tr()),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                if (line.mode != DistributionMode.rest)
                  Tappable(
                    borderRadius: 10,
                    color: getColor(context, "lightDarkAccentHeavyLight"),
                    onTap: onEditValue,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 12, vertical: 6),
                      child: TextFont(
                        text: line.mode == DistributionMode.percent
                            ? removeTrailingZeroes(line.value.toString()) + " %"
                            : money(line.value),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Spacer(),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: TextFont(
                    text: "+" + money(amount * ratio),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    textColor: getColor(context, "incomeAmount"),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            TextFont(
              text: money(balance) + "  →  " + money(balance + amount * ratio),
              fontSize: 13,
              textColor: getColor(context, "textLight"),
            ),
          ],
        ),
      ),
    );
  }
}
