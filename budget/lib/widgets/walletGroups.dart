import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/selectColor.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:budget/widgets/fab.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/walletEntry.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:budget/pages/addButton.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/distributePage.dart';
import 'package:budget/database/initializeDefaultDatabase.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// A group (bank, cash...) with the accounts that are its pockets, or a single
// account without a group (group is null)
class WalletGroupSection {
  WalletGroupSection(this.group, this.wallets);
  final WalletGroup? group;
  final List<WalletWithDetails> wallets;
}

// Keeps the account order: a group shows up where its first account is
// Hidden accounts (eye in Edit Accounts) are left out unless showHidden
List<WalletGroupSection> groupWalletsForDisplay(
    List<WalletWithDetails> wallets, List<WalletGroup> groups,
    {bool showHidden = false}) {
  if (!showHidden) {
    wallets = wallets
        .where((w) =>
            w.wallet.archived == false ||
            w.wallet.walletPk == appStateSettings["selectedWalletPk"])
        .toList();
  }
  bool hideEmpty = appStateSettings["walletsHideEmpty"] == true;
  bool sortByAmount = appStateSettings["walletsSortByAmount"] == true;
  if (hideEmpty) {
    // The selected account always stays visible
    wallets = wallets
        .where((w) =>
            (w.totalSpent ?? 0).abs() >= 0.005 ||
            w.wallet.walletPk == appStateSettings["selectedWalletPk"])
        .toList();
  }
  if (sortByAmount) {
    wallets = [...wallets]..sort((a, b) {
        int byAmount = (b.totalSpent ?? 0).compareTo(a.totalSpent ?? 0);
        return byAmount != 0
            ? byAmount
            : a.wallet.order.compareTo(b.wallet.order);
      });
  }
  Map<String, WalletGroup> groupsByPk = {
    for (WalletGroup group in groups) group.walletGroupPk: group
  };
  List<WalletGroupSection> sections = [];
  Map<String, WalletGroupSection> sectionsByGroupPk = {};
  for (WalletWithDetails wallet in wallets) {
    WalletGroup? group = groupsByPk[wallet.wallet.walletGroupFk];
    if (group == null) {
      sections.add(WalletGroupSection(null, [wallet]));
    } else if (sectionsByGroupPk[group.walletGroupPk] == null) {
      WalletGroupSection section = WalletGroupSection(group, [wallet]);
      sectionsByGroupPk[group.walletGroupPk] = section;
      sections.add(section);
    } else {
      sectionsByGroupPk[group.walletGroupPk]!.wallets.add(wallet);
    }
  }
  if (sortByAmount) {
    double sectionTotal(WalletGroupSection section) => section.wallets
        .fold(0.0, (sum, w) => sum + (w.totalSpent ?? 0));
    // Groups first by their own order, then accounts by theirs
    int customOrder(WalletGroupSection section) => section.group != null
        ? section.group!.order
        : 100000 + section.wallets.first.wallet.order;
    sections.sort((a, b) {
      int byAmount = sectionTotal(b).compareTo(sectionTotal(a));
      return byAmount != 0 ? byAmount : customOrder(a).compareTo(customOrder(b));
    });
  } else {
    sections = [
      ...sections.where((s) => s.group != null).toList()
        ..sort((a, b) => a.group!.order.compareTo(b.group!.order)),
      ...sections.where((s) => s.group == null),
    ];
  }
  return sections;
}

String walletGroupKindLabel(WalletGroupKind kind) =>
    kind == WalletGroupKind.cash ? "cash".tr() : "digital".tr();

IconData walletGroupKindIcon(WalletGroupKind kind) =>
    kind == WalletGroupKind.cash
        ? (appStateSettings["outlinedIcons"]
            ? Icons.payments_outlined
            : Icons.payments_rounded)
        : (appStateSettings["outlinedIcons"]
            ? Icons.account_balance_outlined
            : Icons.account_balance_rounded);

// Total of the pockets: in their currency when they all share one, otherwise
// converted to the primary currency (currencyKey null)
(double, String?) walletGroupTotal(
    AllWallets allWallets, List<WalletWithDetails> wallets) {
  Set<String?> currencies = {for (var w in wallets) w.wallet.currency};
  if (currencies.length == 1) {
    return (
      wallets.fold(0.0, (sum, w) => sum + (w.totalSpent ?? 0)),
      currencies.first
    );
  }
  return (
    wallets.fold(
        0.0,
        (sum, w) =>
            sum +
            (w.totalSpent ?? 0) *
                amountRatioToPrimaryCurrencyGivenPk(
                    allWallets, w.wallet.walletPk)),
    null
  );
}

class WalletGroupHeader extends StatelessWidget {
  const WalletGroupHeader({
    required this.group,
    required this.wallets,
    this.padding = const EdgeInsetsDirectional.symmetric(horizontal: 4),
    this.onTap,
    this.collapsed,
    super.key,
  });
  final WalletGroup group;
  final List<WalletWithDetails> wallets;
  final EdgeInsetsDirectional padding;
  // Edits the group when null
  final VoidCallback? onTap;
  // Shows a chevron when set
  final bool? collapsed;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    var (total, currencyKey) = walletGroupTotal(allWallets, wallets);
    return Tappable(
      color: Colors.transparent,
      borderRadius: 10,
      onTap: onTap ?? () => openEditWalletGroupPopup(context, group: group),
      onLongPress: () => openEditWalletGroupPopup(context, group: group),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (collapsed != null)
              AnimatedRotation(
                duration: Duration(milliseconds: 250),
                turns: collapsed! ? -0.25 : 0,
                child: Icon(
                  appStateSettings["outlinedIcons"]
                      ? Icons.expand_more_outlined
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: getColor(context, "textLight"),
                ),
              ),
            Icon(
              walletGroupKindIcon(group.kind),
              size: 18,
              color: HexColor(group.colour,
                  defaultColor: Theme.of(context).colorScheme.primary),
            ),
            SizedBox(width: 6),
            Flexible(
              child: TextFont(
                text: group.name,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                maxLines: 1,
              ),
            ),
            SizedBox(width: 6),
            TextFont(
              text: walletGroupKindLabel(group.kind),
              fontSize: 12,
              textColor: getColor(context, "textLight"),
            ),
            SizedBox(width: 10),
            TextFont(
              text: convertToMoney(allWallets, total, currencyKey: currencyKey),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              textColor: total == 0
                  ? getColor(context, "black")
                  : total > 0
                      ? getColor(context, "incomeAmount")
                      : getColor(context, "expenseAmount"),
            ),
          ],
        ),
      ),
    );
  }
}

// Home card of a group: its name, kind and total over the cards of its pockets
class WalletGroupContainer extends StatelessWidget {
  const WalletGroupContainer({
    required this.group,
    required this.wallets,
    required this.children,
    super.key,
  });
  final WalletGroup group;
  final List<WalletWithDetails> wallets;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Color groupColor = HexColor(group.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: groupColor.withOpacity(0.35), width: 1.5),
          color: groupColor.withOpacity(0.06),
        ),
        padding: const EdgeInsetsDirectional.only(top: 8, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            WalletGroupHeader(
              group: group,
              wallets: wallets,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
            ),
            SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: children),
          ],
        ),
      ),
    );
  }
}

// Account rows of a list with each group as a header over its pockets.
// Tapping a header folds the group, long press edits it.
class GroupedWalletRows extends StatefulWidget {
  const GroupedWalletRows(
      {required this.wallets,
      required this.rowBuilder,
      this.showOrganizer = false,
      this.showHidden = false,
      super.key});
  final List<WalletWithDetails> wallets;
  final Widget Function(WalletWithDetails wallet) rowBuilder;
  final bool showOrganizer;
  final bool showHidden;

  @override
  State<GroupedWalletRows> createState() => _GroupedWalletRowsState();
}

class _GroupedWalletRowsState extends State<GroupedWalletRows> {
  List<String> get collapsedGroups =>
      List<String>.from(appStateSettings["collapsedWalletGroups"] ?? []);

  Future<void> toggleGroup(String walletGroupPk) async {
    List<String> collapsed = collapsedGroups;
    if (!collapsed.remove(walletGroupPk)) collapsed.add(walletGroupPk);
    await updateSettings("collapsedWalletGroups", collapsed,
        updateGlobalState: false);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    List<WalletWithDetails> wallets = widget.wallets;
    Widget Function(WalletWithDetails wallet) rowBuilder = widget.rowBuilder;
    return StreamBuilder<List<WalletGroup>>(
      stream: database.watchAllWalletGroups(),
      builder: (context, snapshot) {
        return Column(
          children: [
            if (widget.showOrganizer) WalletsOrganizer(),
            for (WalletGroupSection section
                in groupWalletsForDisplay(wallets, snapshot.data ?? [],
                    showHidden: widget.showHidden))
              // Keys keep each row with its account when the order changes,
              // so amounts do not count from another row's value
              if (section.group == null)
                KeyedSubtree(
                  key: ValueKey(section.wallets.first.wallet.walletPk),
                  child: rowBuilder(section.wallets.first),
                )
              else
                Column(
                  key: ValueKey(section.group!.walletGroupPk),
                  children: [
                    WalletGroupHeader(
                      group: section.group!,
                      wallets: section.wallets,
                      collapsed: collapsedGroups
                          .contains(section.group!.walletGroupPk),
                      onTap: () => toggleGroup(section.group!.walletGroupPk),
                      padding: const EdgeInsetsDirectional.only(
                          start: 14, end: 18, top: 8, bottom: 2),
                    ),
                    if (!collapsedGroups.contains(section.group!.walletGroupPk))
                    for (int i = 0; i < section.wallets.length; i++)
                      IntrinsicHeight(
                        key: ValueKey(section.wallets[i].wallet.walletPk),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 30,
                              child: CustomPaint(
                                painter: WalletGroupBranchPainter(
                                  color: HexColor(section.group!.colour,
                                          defaultColor: Theme.of(context)
                                              .colorScheme
                                              .primary)
                                      .withOpacity(0.5),
                                  isLast: i == section.wallets.length - 1,
                                ),
                              ),
                            ),
                            Expanded(child: rowBuilder(section.wallets[i])),
                          ],
                        ),
                      ),
                  ],
                ),
          ],
        );
      },
    );
  }
}

// Row in the edit account page to choose the group of the account
class WalletGroupSelector extends StatelessWidget {
  const WalletGroupSelector({
    required this.selectedWalletGroupFk,
    required this.onSelected,
    super.key,
  });
  final String? selectedWalletGroupFk;
  final Function(String? walletGroupPk) onSelected;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WalletGroup>>(
      stream: database.watchAllWalletGroups(),
      builder: (context, snapshot) {
        WalletGroup? selected = (snapshot.data ?? [])
            .where((g) => g.walletGroupPk == selectedWalletGroupFk)
            .firstOrNull;
        return SettingsContainer(
          isOutlined: true,
          isWideOutlined: true,
          title: "group".tr(),
          icon: selected == null
              ? (appStateSettings["outlinedIcons"]
                  ? Icons.workspaces_outlined
                  : Icons.workspaces_rounded)
              : walletGroupKindIcon(selected.kind),
          afterWidget: Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected == null
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : HexColor(selected.colour,
                          defaultColor: Theme.of(context).colorScheme.primary)
                      .withOpacity(0.35),
            ),
            child: TextFont(
              text: selected?.name ?? "no-group".tr(),
              fontSize: 14,
            ),
          ),
          onTap: () async {
            dynamic result = await openBottomSheet(
              context,
              SelectWalletGroupPopup(
                  selectedWalletGroupFk: selectedWalletGroupFk),
            );
            if (result is SelectedWalletGroup) onSelected(result.walletGroupPk);
          },
        );
      },
    );
  }
}

class SelectedWalletGroup {
  SelectedWalletGroup(this.walletGroupPk);
  final String? walletGroupPk;
}

class SelectWalletGroupPopup extends StatelessWidget {
  const SelectWalletGroupPopup({this.selectedWalletGroupFk, super.key});
  final String? selectedWalletGroupFk;

  @override
  Widget build(BuildContext context) {
    Widget option({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
      Color? color,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 6),
        child: Tappable(
          borderRadius: 12,
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : getColor(context, "lightDarkAccentHeavyLight"),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: color),
                SizedBox(width: 12),
                Expanded(child: TextFont(text: label, fontSize: 16)),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      );
    }

    return PopupFramework(
      title: "group".tr(),
      subtitle: "group-description".tr(),
      child: StreamBuilder<List<WalletGroup>>(
        stream: database.watchAllWalletGroups(),
        builder: (context, snapshot) {
          return Column(
            children: [
              option(
                label: "no-group".tr(),
                icon: appStateSettings["outlinedIcons"]
                    ? Icons.block_outlined
                    : Icons.block_rounded,
                selected: selectedWalletGroupFk == null,
                onTap: () => popRoute(context, SelectedWalletGroup(null)),
              ),
              for (WalletGroup group in snapshot.data ?? [])
                option(
                  label: group.name + " · " + walletGroupKindLabel(group.kind),
                  icon: walletGroupKindIcon(group.kind),
                  color: HexColor(group.colour,
                      defaultColor: Theme.of(context).colorScheme.primary),
                  selected: selectedWalletGroupFk == group.walletGroupPk,
                  onTap: () => popRoute(
                      context, SelectedWalletGroup(group.walletGroupPk)),
                  trailing: IconButton(
                    onPressed: () =>
                        openEditWalletGroupPopup(context, group: group),
                    icon: Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.edit_outlined
                          : Icons.edit_rounded,
                      size: 20,
                    ),
                  ),
                ),
              SizedBox(height: 6),
              Button(
                label: "new-group".tr(),
                onTap: () async {
                  String? walletGroupPk =
                      await openEditWalletGroupPopup(context);
                  if (walletGroupPk != null)
                    popRoute(context, SelectedWalletGroup(walletGroupPk));
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// Returns the pk of the saved group
Future<String?> openEditWalletGroupPopup(BuildContext context,
    {WalletGroup? group}) async {
  dynamic result = await openBottomSheet(
    context,
    popupWithKeyboard: true,
    EditWalletGroupPopup(group: group),
  );
  return result is String ? result : null;
}

class EditWalletGroupPopup extends StatefulWidget {
  const EditWalletGroupPopup({this.group, super.key});
  final WalletGroup? group;

  @override
  State<EditWalletGroupPopup> createState() => _EditWalletGroupPopupState();
}

class _EditWalletGroupPopupState extends State<EditWalletGroupPopup> {
  late String name = widget.group?.name ?? "";
  late Color? colour =
      widget.group?.colour == null ? null : HexColor(widget.group!.colour);
  late WalletGroupKind kind = widget.group?.kind ?? WalletGroupKind.digital;
  late String? freeWalletFk = widget.group?.freeWalletFk;

  Future<void> deleteGroup() async {
    dynamic confirmed = await openPopup(
      context,
      title: asQuestion("delete-group".tr()),
      description: "delete-group-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outlined
          : Icons.delete_rounded,
      onSubmit: () => popRoute(context, true),
      onSubmitLabel: "delete".tr(),
      onCancel: () => popRoute(context, false),
      onCancelLabel: "cancel".tr(),
    );
    if (confirmed == true) {
      await database.deleteWalletGroup(widget.group!.walletGroupPk);
      popRoute(context);
    }
  }

  Future<void> save() async {
    if (name.trim() == "") return;
    String walletGroupPk = await database.createOrUpdateWalletGroup(
      insert: widget.group == null,
      WalletGroup(
        walletGroupPk: widget.group?.walletGroupPk ?? "-1",
        name: name.trim(),
        colour: colour == null ? null : toHexString(colour!),
        kind: kind,
        order: widget.group?.order ?? 0,
        dateCreated: widget.group?.dateCreated ?? DateTime.now(),
        dateTimeModified: null,
        freeWalletFk: freeWalletFk,
      ),
    );
    if (widget.group == null) {
      AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
      await database.createFreePocket(
        walletGroupPk,
        name: "free-money".tr(),
        colour: colour == null ? null : toHexString(colour!),
        currency: allWallets
            .indexedByPk[appStateSettings["selectedWalletPk"]]?.currency,
      );
    }
    popRoute(context, walletGroupPk);
  }

  @override
  Widget build(BuildContext context) {
    Widget kindOption(WalletGroupKind option) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          child: OutlinedButtonStacked(
            filled: kind == option,
            alignStart: true,
            alignBeside: true,
            padding:
                EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
            text: walletGroupKindLabel(option),
            iconData: walletGroupKindIcon(option),
            onTap: () => setState(() => kind = option),
          ),
        ),
      );
    }

    return PopupFramework(
      title: widget.group == null ? "new-group".tr() : "edit-group".tr(),
      outsideExtraWidget: widget.group == null
          ? null
          : OutsideExtraWidgetIconButton(
              iconData: appStateSettings["outlinedIcons"]
                  ? Icons.delete_outlined
                  : Icons.delete_rounded,
              onPressed: deleteGroup,
            ),
      child: Column(
        children: [
          TextInput(
            labelText: "name-placeholder".tr(),
            initialValue: name,
            autoFocus: widget.group == null,
            onChanged: (text) => setState(() => name = text),
            padding: EdgeInsetsDirectional.zero,
          ),
          SizedBox(height: 12),
          Row(children: [
            kindOption(WalletGroupKind.digital),
            kindOption(WalletGroupKind.cash),
          ]),
          if (widget.group != null) ...[
            SizedBox(height: 12),
            FreePocketSetting(
              group: widget.group!,
              freeWalletFk: freeWalletFk,
              onChanged: (walletPk) => setState(() => freeWalletFk = walletPk),
            ),
          ],
          SizedBox(height: 12),
          SelectColor(
            popOnSelect: false,
            selectedColor: colour,
            setSelectedColor: (color) => setState(() => colour = color),
          ),
          SizedBox(height: 12),
          Button(
            label:
                widget.group == null ? "new-group".tr() : "save-changes".tr(),
            disabled: name.trim() == "",
            onTap: save,
          ),
        ],
      ),
    );
  }
}

// Tree line from the group header down to each pocket row
class WalletGroupBranchPainter extends CustomPainter {
  WalletGroupBranchPainter({required this.color, required this.isLast});
  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    double x = 22;
    double middle = size.height / 2;
    canvas.drawLine(
        Offset(x, 0), Offset(x, isLast ? middle : size.height), paint);
    canvas.drawLine(Offset(x, middle), Offset(size.width, middle), paint);
  }

  @override
  bool shouldRepaint(WalletGroupBranchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLast != isLast;
}

// Which pocket of the group holds the money free to spend. "auto" uses the
// pocket named Libre / Free.
class FreePocketSetting extends StatelessWidget {
  const FreePocketSetting({
    required this.group,
    required this.freeWalletFk,
    required this.onChanged,
    super.key,
  });
  final WalletGroup group;
  final String? freeWalletFk;
  final Function(String? walletPk) onChanged;

  @override
  Widget build(BuildContext context) {
    List<TransactionWallet> pockets = Provider.of<AllWallets>(context)
        .list
        .where((w) => w.walletGroupFk == group.walletGroupPk)
        .toList();
    if (pockets.isEmpty) return SizedBox.shrink();
    return SettingsContainerDropdown(
      enableBorderRadius: true,
      title: "free-pocket".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.savings_outlined
          : Icons.savings_rounded,
      initial: pockets.any((w) => w.walletPk == freeWalletFk)
          ? freeWalletFk!
          : "auto",
      items: ["auto", for (TransactionWallet w in pockets) w.walletPk],
      getLabel: (item) => item == "auto"
          ? "automatic".tr()
          : pockets.firstWhere((w) => w.walletPk == item).name,
      onChanged: (value) => onChanged(value == "auto" ? null : value),
    );
  }
}

// Money free to spend: the free pocket of each group, next to the total of
// every account. Shown over the net worth when some group has a free pocket.
class FreeMoneySummary extends StatelessWidget {
  const FreeMoneySummary({super.key});

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return StreamBuilder<List<WalletGroup>>(
      stream: database.watchAllWalletGroups(),
      builder: (context, groupsSnapshot) {
        return StreamBuilder<List<WalletWithDetails>>(
          stream: database.watchAllWalletsWithDetails(),
          builder: (context, walletsSnapshot) {
            List<WalletWithDetails> wallets = walletsSnapshot.data ?? [];
            double inPrimary(WalletWithDetails w) =>
                (w.totalSpent ?? 0) *
                amountRatioToPrimaryCurrencyGivenPk(
                    allWallets, w.wallet.walletPk);
            List<(WalletGroup, double)> freeByGroup = [];
            String? richestFreePk;
            double richestFree = double.negativeInfinity;
            for (WalletGroup group in groupsSnapshot.data ?? []) {
              String? freePk = freeWalletPkOfGroup(
                  group, [for (var w in wallets) w.wallet]);
              WalletWithDetails? free = wallets
                  .where((w) => w.wallet.walletPk == freePk)
                  .firstOrNull;
              if (free != null) {
                freeByGroup.add((group, inPrimary(free)));
                if (inPrimary(free) > richestFree) {
                  richestFree = inPrimary(free);
                  richestFreePk = free.wallet.walletPk;
                }
              }
            }
            if (freeByGroup.isEmpty) return SizedBox.shrink();
            double freeTotal =
                freeByGroup.fold(0.0, (sum, item) => sum + item.$2);
            double allTotal =
                wallets.fold(0.0, (sum, w) => sum + inPrimary(w));
            String money(double amount) =>
                convertToMoney(allWallets, amount, addCurrencyName: false);
            Color amountColor(double amount) => amount == 0
                ? getColor(context, "black")
                : amount > 0
                    ? getColor(context, "incomeAmount")
                    : getColor(context, "expenseAmount");
            return Padding(
              padding: const EdgeInsetsDirectional.only(
                  bottom: 13, start: 13, end: 13),
              child: Container(
                padding: const EdgeInsetsDirectional.all(15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: getColor(context, "lightDarkAccentHeavyLight"),
                  boxShadow: boxShadowCheck(boxShadowGeneral(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          appStateSettings["outlinedIcons"]
                              ? Icons.savings_outlined
                              : Icons.savings_rounded,
                          size: 20,
                        ),
                        SizedBox(width: 4),
                        Expanded(
                          child: TextFont(
                            text: "free-money".tr(),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Tappable(
                          borderRadius: 10,
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          onTap: () => pushRoute(context,
                              DistributePage(sourceWalletPk: richestFreePk)),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  appStateSettings["outlinedIcons"]
                                      ? Icons.call_split_outlined
                                      : Icons.call_split_rounded,
                                  size: 17,
                                ),
                                SizedBox(width: 6),
                                TextFont(
                                  text: "distribute".tr(),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextFont(
                            text: "total-in-accounts".tr() +
                                " " +
                                money(allTotal),
                            fontSize: 12,
                            maxLines: 2,
                            textColor: getColor(context, "textLight"),
                          ),
                        ),
                        TextFont(
                          text: money(freeTotal),
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          textColor: amountColor(freeTotal),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var (group, amount) in freeByGroup)
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: HexColor(group.colour,
                                      defaultColor:
                                          Theme.of(context).colorScheme.primary)
                                  .withOpacity(0.2),
                            ),
                            child: TextFont(
                              text: group.name + " " + money(amount),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Quick filters over the accounts list: hide empty pockets, sort by amount
class WalletsOrganizer extends StatefulWidget {
  const WalletsOrganizer({super.key});

  @override
  State<WalletsOrganizer> createState() => _WalletsOrganizerState();
}

class _WalletsOrganizerState extends State<WalletsOrganizer> {
  Widget chip(String setting, String label, IconData icon) {
    bool active = appStateSettings[setting] == true;
    return Tappable(
      borderRadius: 10,
      color: active
          ? Theme.of(context).colorScheme.secondaryContainer
          : Colors.transparent,
      onTap: () async {
        await updateSettings(setting, !active, updateGlobalState: false);
        setState(() {});
        // The home cards and lists read these settings when they rebuild
        homePageStateKey.currentState?.refreshState();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : getColor(context, "lightDarkAccentHeavy"),
              width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: active
                    ? getColor(context, "black")
                    : getColor(context, "textLight")),
            SizedBox(width: 4),
            TextFont(
              text: label,
              fontSize: 12,
              textColor: active
                  ? getColor(context, "black")
                  : getColor(context, "textLight"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          chip(
            "walletsSortByAmount",
            "sort-by-amount".tr(),
            appStateSettings["outlinedIcons"]
                ? Icons.sort_outlined
                : Icons.sort_rounded,
          ),
          chip(
            "walletGroupsCompact",
            "compact-groups".tr(),
            appStateSettings["outlinedIcons"]
                ? Icons.view_agenda_outlined
                : Icons.view_agenda_rounded,
          ),
          chip(
            "walletsHideEmpty",
            "hide-empty".tr(),
            appStateSettings["outlinedIcons"]
                ? Icons.visibility_off_outlined
                : Icons.visibility_off_rounded,
          ),
        ],
      ),
    );
  }
}

// Total, transactions and pockets of a group, as a card like an account's.
// Tapping it shows its pockets in a row under the cards, long press edits it.
class WalletGroupCard extends StatelessWidget {
  const WalletGroupCard({
    required this.group,
    required this.wallets,
    required this.expanded,
    required this.onTap,
    super.key,
  });
  final WalletGroup group;
  final List<WalletWithDetails> wallets;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    var (total, currencyKey) = walletGroupTotal(allWallets, wallets);
    int transactions =
        wallets.fold(0, (sum, w) => sum + (w.numberTransactions ?? 0));
    Color groupColor = HexColor(group.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
      child: Tappable(
        color: getColor(context, "lightDarkAccentHeavyLight"),
        borderRadius: 15,
        onTap: onTap,
        onLongPress: () => openEditWalletGroupPopup(context, group: group),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 350),
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              width: 2,
              color: expanded ? groupColor.withOpacity(0.7) : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(walletGroupKindIcon(group.kind),
                      size: 18, color: groupColor),
                  SizedBox(width: 6),
                  TextFont(text: group.name, fontWeight: FontWeight.bold),
                  SizedBox(width: 4),
                  AnimatedRotation(
                    duration: Duration(milliseconds: 250),
                    turns: expanded ? 0.5 : 0,
                    child: Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.expand_more_outlined
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: getColor(context, "textLight"),
                    ),
                  ),
                ],
              ),
              TextFont(
                text: convertToMoney(allWallets, total, currencyKey: currencyKey),
                fontSize: 17,
                fontWeight: FontWeight.bold,
                textColor: total == 0
                    ? getColor(context, "black")
                    : total > 0
                        ? getColor(context, "incomeAmount")
                        : getColor(context, "expenseAmount"),
              ),
              TextFont(
                text: transactions.toString() +
                    " " +
                    (transactions == 1
                        ? "transaction".tr().toLowerCase()
                        : "transactions".tr().toLowerCase()) +
                    " · " +
                    wallets.length.toString() +
                    " " +
                    (wallets.length == 1
                        ? "pocket".tr().toLowerCase()
                        : "pockets".tr().toLowerCase()),
                fontSize: 14,
                textColor: getColor(context, "black").withOpacity(0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Home cards: first row with each group as one card (plus the accounts
// without a group), second row with every pocket. The pockets of the open
// group are highlighted with a tinted background, the row keeps the groups'
// order and ends with a button to add a pocket. The open group is remembered in the settings.
class CompactWalletSwitcher extends StatefulWidget {
  const CompactWalletSwitcher({
    required this.sections,
    required this.walletEntry,
    super.key,
  });
  final List<WalletGroupSection> sections;
  final Widget Function(WalletWithDetails wallet) walletEntry;

  @override
  State<CompactWalletSwitcher> createState() => _CompactWalletSwitcherState();
}

class _CompactWalletSwitcherState extends State<CompactWalletSwitcher> {
  late String? expandedGroupPk = appStateSettings["expandedWalletGroupPk"];
  ScrollController pocketsScrollController = ScrollController();
  Map<String, GlobalKey> pocketsKeys = {};

  void toggle(String walletGroupPk) {
    setState(() {
      expandedGroupPk = expandedGroupPk == walletGroupPk ? null : walletGroupPk;
    });
    updateSettings("expandedWalletGroupPk", expandedGroupPk,
        updateGlobalState: false);
    // Bring the open group's pockets into view, the order never changes.
    // Only this row scrolls (ensureVisible would also scroll the page).
    if (expandedGroupPk != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        RenderObject? pockets =
            pocketsKeys[expandedGroupPk]?.currentContext?.findRenderObject();
        if (pockets is! RenderBox ||
            !pocketsScrollController.hasClients ||
            !pockets.attached) return;
        ScrollPosition position = pocketsScrollController.position;
        RenderObject? viewport = position.context.storageContext
            .findRenderObject();
        if (viewport is! RenderBox) return;
        double x = pockets.localToGlobal(Offset.zero, ancestor: viewport).dx;
        double target = (position.pixels + x - 7)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        pocketsScrollController.animateTo(target,
            duration: Duration(milliseconds: 450), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void dispose() {
    pocketsScrollController.dispose();
    super.dispose();
  }

  Widget row(List<Widget> children, {ScrollController? controller}) =>
      SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsetsDirectional.symmetric(horizontal: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      );

  Widget pocketsOfGroup(WalletGroupSection section, {required bool open}) {
    WalletGroup group = section.group!;
    Color groupColor = HexColor(group.colour,
        defaultColor: Theme.of(context).colorScheme.primary);
    return AnimatedContainer(
      key: pocketsKeys.putIfAbsent(group.walletGroupPk, () => GlobalKey()),
      duration: Duration(milliseconds: 350),
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 3),
      padding: const EdgeInsetsDirectional.symmetric(vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        color: open ? groupColor.withOpacity(0.08) : Colors.transparent,
        border: Border.all(
          color: open ? groupColor.withOpacity(0.35) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (WalletWithDetails wallet in section.wallets)
            widget.walletEntry(wallet),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<WalletGroupSection> groupSections =
        widget.sections.where((s) => s.group != null).toList();
    WalletGroupSection? open = groupSections
        .where((s) => s.group!.walletGroupPk == expandedGroupPk)
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([
          for (WalletGroupSection section in widget.sections)
            section.group == null
                ? widget.walletEntry(section.wallets.first)
                : WalletGroupCard(
                    key: ValueKey(section.group!.walletGroupPk),
                    group: section.group!,
                    wallets: section.wallets,
                    expanded: section == open,
                    onTap: () => toggle(section.group!.walletGroupPk),
                  ),
          CardSizedAddButton(
            label: "group".tr(),
            onTap: () => openEditWalletGroupPopup(context),
          ),
        ]),
        if (groupSections.isNotEmpty) ...[
          SizedBox(height: 8),
          row(
            controller: pocketsScrollController,
            [
              for (WalletGroupSection section in groupSections)
                pocketsOfGroup(section, open: section == open),
              // New pocket, inside the open group if there is one
              CardSizedAddButton(
                label: "pocket".tr(),
                onTap: () => pushRoute(
                  context,
                  AddWalletPage(
                    routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                    initialWalletGroupFk: open?.group?.walletGroupPk,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// Add button with the size of an account card
class CardSizedAddButton extends StatelessWidget {
  const CardSizedAddButton(
      {required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          width: 130,
          child: IgnorePointer(
            child: Visibility(
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Opacity(
                opacity: 0,
                child: WalletEntry(
                  selected: false,
                  walletWithDetails: WalletWithDetails(wallet: defaultWallet()),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
            child: AddButton(
              onTap: onTap,
              labelUnder: label,
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.add_outlined
                  : Icons.add_rounded,
            ),
          ),
        ),
      ],
    );
  }
}

// Edit Data > Groups: every group with its pockets, drag to set their order
class WalletGroupsPage extends StatelessWidget {
  const WalletGroupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "groups".tr(),
      dragDownToDismiss: true,
      floatingActionButton: AnimateFABDelayed(
        fab: FAB(
          tooltip: "new-group".tr(),
          openPage: SizedBox.shrink(),
          onTap: () => openEditWalletGroupPopup(context),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 600,
            child: StreamBuilder<List<WalletGroup>>(
              stream: database.watchAllWalletGroups(),
              builder: (context, snapshot) {
                List<WalletGroup> groups = snapshot.data ?? [];
                List<TransactionWallet> wallets =
                    Provider.of<AllWallets>(context).list;
                if (snapshot.hasData && groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(top: 30),
                    child: TextFont(
                      text: "no-groups".tr(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      textColor: getColor(context, "textLight"),
                    ),
                  );
                }
                return ReorderableListView(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    List<WalletGroup> ordered = [...groups];
                    ordered.insert(newIndex, ordered.removeAt(oldIndex));
                    for (int i = 0; i < ordered.length; i++) {
                      if (ordered[i].order != i) {
                        await database.createOrUpdateWalletGroup(
                            ordered[i].copyWith(order: i));
                      }
                    }
                  },
                  children: [
                    for (int index = 0; index < groups.length; index++)
                      Padding(
                        key: ValueKey(groups[index].walletGroupPk),
                        padding: const EdgeInsetsDirectional.only(bottom: 8),
                        child: Tappable(
                          borderRadius: 15,
                          color: getColor(context, "lightDarkAccentHeavyLight"),
                          onTap: () => openEditWalletGroupPopup(context,
                              group: groups[index]),
                          child: Container(
                            padding: const EdgeInsetsDirectional.only(
                                start: 16, top: 12, bottom: 12, end: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: BorderDirectional(
                                start: BorderSide(
                                  width: 5,
                                  color: HexColor(groups[index].colour,
                                      defaultColor:
                                          Theme.of(context).colorScheme.primary),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(walletGroupKindIcon(groups[index].kind)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      TextFont(
                                        text: groups[index].name,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      TextFont(
                                        text: walletGroupKindLabel(
                                                groups[index].kind) +
                                            " · " +
                                            wallets
                                                .where((w) =>
                                                    w.walletGroupFk ==
                                                    groups[index].walletGroupPk)
                                                .map((w) => w.name)
                                                .join(", "),
                                        fontSize: 13,
                                        maxLines: 2,
                                        textColor:
                                            getColor(context, "textLight"),
                                      ),
                                    ],
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.all(12),
                                    child: Icon(
                                      appStateSettings["outlinedIcons"]
                                          ? Icons.drag_handle_outlined
                                          : Icons.drag_handle_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 90)),
      ],
    );
  }
}

// Account picker as a list: each group with its header and its pockets in a
// box tinted with its colour, then the accounts without a group
class GroupedWalletPicker extends StatelessWidget {
  const GroupedWalletPicker({
    required this.wallets,
    required this.selectedWalletPk,
    required this.onSelected,
    this.onLongPress,
    super.key,
  });
  final List<WalletWithDetails> wallets;
  final String? selectedWalletPk;
  final Function(TransactionWallet wallet) onSelected;
  final Function(TransactionWallet wallet)? onLongPress;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Widget walletRow(WalletWithDetails details) {
      TransactionWallet wallet = details.wallet;
      bool selected = wallet.walletPk == selectedWalletPk;
      Color walletColor = HexColor(wallet.colour,
          defaultColor: Theme.of(context).colorScheme.primary);
      double total = details.totalSpent ?? 0;
      return Tappable(
        borderRadius: 12,
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        onTap: () => onSelected(wallet),
        onLongPress: onLongPress == null ? null : () => onLongPress!(wallet),
        child: Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? walletColor : Colors.transparent,
                  border: Border.all(color: walletColor, width: 2),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextFont(
                  text: wallet.name,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  maxLines: 1,
                ),
              ),
              TextFont(
                text: convertToMoney(allWallets, total,
                    finalNumber: total,
                    currencyKey: wallet.currency,
                    decimals: wallet.decimals,
                    addCurrencyName: true),
                fontSize: 15,
                textColor: total < -0.005
                    ? getColor(context, "expenseAmount")
                    : getColor(context, "black"),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<List<WalletGroup>>(
      stream: database.watchAllWalletGroups(),
      builder: (context, snapshot) {
        List<WalletGroup> groups = snapshot.data ?? [];
        List<WalletWithDetails> ungrouped = wallets
            .where((w) => !groups
                .any((g) => g.walletGroupPk == w.wallet.walletGroupFk))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (WalletGroup group in groups)
              if (wallets.any((w) => w.wallet.walletGroupFk == group.walletGroupPk))
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsetsDirectional.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: HexColor(group.colour,
                              defaultColor:
                                  Theme.of(context).colorScheme.primary)
                          .withOpacity(0.08),
                      border: Border.all(
                        color: HexColor(group.colour,
                                defaultColor:
                                    Theme.of(context).colorScheme.primary)
                            .withOpacity(0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                              start: 8, end: 8, top: 4, bottom: 2),
                          child: Row(
                            children: [
                              Icon(
                                walletGroupKindIcon(group.kind),
                                size: 18,
                                color: HexColor(group.colour,
                                    defaultColor:
                                        Theme.of(context).colorScheme.primary),
                              ),
                              SizedBox(width: 8),
                              TextFont(
                                text: group.name,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              SizedBox(width: 6),
                              TextFont(
                                text: walletGroupKindLabel(group.kind),
                                fontSize: 12,
                                textColor: getColor(context, "textLight"),
                              ),
                            ],
                          ),
                        ),
                        for (WalletWithDetails wallet in wallets.where((w) =>
                            w.wallet.walletGroupFk == group.walletGroupPk))
                          walletRow(wallet),
                      ],
                    ),
                  ),
                ),
            if (ungrouped.isNotEmpty)
              Container(
                padding: const EdgeInsetsDirectional.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: getColor(context, "lightDarkAccentHeavyLight"),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var wallet in ungrouped) walletRow(wallet)],
                ),
              ),
          ],
        );
      },
    );
  }
}

// Icon next to the name of a group's free pocket, "Free" on hover
class FreePocketTag extends StatelessWidget {
  const FreePocketTag({this.size = 17, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "free-money".tr(),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 5),
        child: Icon(
          appStateSettings["outlinedIcons"]
              ? Icons.savings_outlined
              : Icons.savings_rounded,
          size: size,
          color: getColor(context, "incomeAmount"),
        ),
      ),
    );
  }
}
