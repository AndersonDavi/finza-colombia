import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/editAssociatedTitlesPage.dart';
import 'package:budget/pages/editBudgetPage.dart';
import 'package:budget/pages/editCategoriesPage.dart';
import 'package:budget/pages/editObjectivesPage.dart';
import 'package:budget/pages/editWalletsPage.dart';
import 'package:budget/struct/navBarIconsData.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/walletGroups.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Sidebar entries with the keys the official 6.x keeps in its settings:
// "sidebarOrder" holds the order and each key is false when hidden.
// The value is the navBarIconsData key, null for Edit Data.
const Map<String, String?> sidebarEntries = {
  "sidebarHome": "home",
  "sidebarTransactions": "transactions",
  "sidebarAccounts": "accounts",
  "sidebarBudgets": "budgets",
  "sidebarGoals": "goals",
  "sidebarLoans": "loans",
  "sidebarSubscriptions": "subscriptions",
  "sidebarScheduled": "scheduled",
  "sidebarCalendar": "calendar",
  "sidebarActivityLog": "activityLog",
  "sidebarAllSpending": "allSpending",
  "sidebarEditData": null,
};

List<String> getSidebarOrder() {
  List<String> order = List<String>.from(appStateSettings["sidebarOrder"] ?? [])
      .where((entry) => sidebarEntries.containsKey(entry))
      .toList();
  for (String entry in sidebarEntries.keys) {
    if (!order.contains(entry)) order.add(entry);
  }
  return order;
}

String sidebarEntryLabel(String entry) {
  if (sidebarEntries[entry] == null) return "edit-data".tr();
  if (entry == "sidebarAllSpending") return "summary".tr();
  return navBarIconsData[sidebarEntries[entry]]!.label.tr();
}

IconData sidebarEntryIcon(String entry) {
  if (sidebarEntries[entry] == null) return Icons.edit_document;
  return navBarIconsData[sidebarEntries[entry]]!.iconData;
}

class EditDataButton extends StatelessWidget {
  const EditDataButton({super.key, required this.selectedIndex});
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return NavigationSidebarButton(
      icon: Icons.edit_document,
      label: "edit-data".tr(),
      isSelected: [9, 10, 11, 12, 15].contains(selectedIndex),
      onTap: () {
        openBottomSheet(context, EditDataPopup());
      },
      popRoutes: false,
    );
  }
}

class EditDataPopup extends StatelessWidget {
  const EditDataPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "edit-data".tr(),
      child: EditDataGrid(closePopupFirst: true),
    );
  }
}

// Buttons to the edit pages of each kind of data, used by the sidebar popup
// and the general settings page
class EditDataGrid extends StatelessWidget {
  const EditDataGrid({this.closePopupFirst = false, super.key});
  final bool closePopupFirst;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, IconData iconData, Widget page) {
      return OutlinedButtonStacked(
        text: label.tr(),
        fontSize: 13,
        iconData: iconData,
        padding: EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 15),
        onTap: () {
          if (closePopupFirst) popRoute(context);
          pushRoute(context, page);
        },
      );
    }

    return GridView.extent(
      maxCrossAxisExtent: 130,
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: [
        option("accounts", navBarIconsData["accountDetails"]!.iconData,
            EditWalletsPage()),
        option("categories", navBarIconsData["categoriesDetails"]!.iconData,
            EditCategoriesPage()),
        option("titles", navBarIconsData["titlesDetails"]!.iconData,
            EditAssociatedTitlesPage()),
        option("budgets", navBarIconsData["budgetDetails"]!.iconData,
            EditBudgetPage()),
        option("goals", navBarIconsData["goalsDetails"]!.iconData,
            EditObjectivesPage(objectiveType: ObjectiveType.goal)),
        option("long-term-loans", navBarIconsData["loans"]!.iconData,
            EditObjectivesPage(objectiveType: ObjectiveType.loan)),
        option(
            "groups",
            appStateSettings["outlinedIcons"]
                ? Icons.workspaces_outlined
                : Icons.workspaces_rounded,
            WalletGroupsPage()),
      ],
    );
  }
}

// While true the sidebar shows its entries as an editable list
ValueNotifier<bool> sidebarEditMode = ValueNotifier(false);

void setSidebarEditMode(bool editing) {
  sidebarEditMode.value = editing;
  sidebarStateKey.currentState?.refreshState();
}

class SidebarBottomActions extends StatelessWidget {
  const SidebarBottomActions({super.key});

  @override
  Widget build(BuildContext context) {
    if (appStateSettings["expandedNavigationSidebar"] != true ||
        sidebarEditMode.value) {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Center(
        child: SidebarPillButton(
          label: "edit-order".tr(),
          onTap: () => setSidebarEditMode(true),
        ),
      ),
    );
  }
}

class SidebarPillButton extends StatelessWidget {
  const SidebarPillButton(
      {required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tappable(
      borderRadius: 12,
      color: getColor(context, "lightDarkAccentHeavyLight"),
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
        child: TextFont(
          text: label,
          fontSize: 13,
          textColor: getColor(context, "textLight"),
        ),
      ),
    );
  }
}

// Sidebar in edit mode: drag (long press) to reorder, tap to show or hide
class SidebarEditList extends StatefulWidget {
  const SidebarEditList({super.key});

  @override
  State<SidebarEditList> createState() => _SidebarEditListState();
}

class _SidebarEditListState extends State<SidebarEditList> {
  late List<String> order = getSidebarOrder();

  Future<void> toggle(String entry) async {
    await updateSettings(entry, appStateSettings[entry] == false,
        updateGlobalState: false);
    setState(() {});
  }

  Future<void> reset() async {
    await updateSettings("sidebarOrder", sidebarEntries.keys.toList(),
        updateGlobalState: false);
    for (String entry in sidebarEntries.keys) {
      await updateSettings(entry, true, updateGlobalState: false);
    }
    setState(() {
      order = getSidebarOrder();
    });
  }

  Widget entryTile(String entry, int index) {
    bool shown = appStateSettings[entry] != false;
    return Padding(
      key: ValueKey(entry),
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 4),
      child: ReorderableDelayedDragStartListener(
        index: index,
        // Tiles slide in one after the other when the edit mode opens
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 250 + index * 35),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(-24 * (1 - value), 0),
              child: child,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Tappable(
                borderRadius: 12,
                color: getColor(context, "lightDarkAccentHeavyLight"),
                onTap: () => toggle(entry),
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  opacity: shown ? 1 : 0.4,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(sidebarEntryIcon(entry), size: 22),
                        SizedBox(width: 14),
                        Expanded(
                          child: TextFont(
                            text: sidebarEntryLabel(entry),
                            fontSize: 15,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: -5,
                end: -5,
                child: IgnorePointer(
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: shown
                          ? getColor(context, "expenseAmount")
                          : getColor(context, "incomeAmount"),
                    ),
                    child: Icon(
                      shown ? Icons.remove_rounded : Icons.add_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
          child: Container(
            padding: const EdgeInsetsDirectional.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: getColor(context, "lightDarkAccentHeavy"), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.info_outlined
                          : Icons.info_outline_rounded,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    TextFont(
                      text: "edit-list".tr(),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ],
                ),
                SizedBox(height: 4),
                TextFont(
                  text: "edit-list-description".tr(),
                  fontSize: 12,
                  maxLines: 4,
                  textColor: getColor(context, "textLight"),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 6),
        ReorderableListView(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              order.insert(newIndex, order.removeAt(oldIndex));
            });
            updateSettings("sidebarOrder", order, updateGlobalState: false);
          },
          children: [
            for (int index = 0; index < order.length; index++)
              entryTile(order[index], index),
          ],
        ),
        SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SidebarPillButton(label: "reset".tr(), onTap: reset),
            SidebarPillButton(
              label: "done".tr(),
              onTap: () => setSidebarEditMode(false),
            ),
          ],
        ),
        SizedBox(height: 15),
      ],
    );
  }
}
