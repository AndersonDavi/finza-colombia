import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:budget/widgets/fab.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/selectColor.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tagBudgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:provider/provider.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

IconData tagIcon() => appStateSettings["outlinedIcons"]
    ? Icons.sell_outlined
    : Icons.sell_rounded;

Color tagColor(BuildContext context, Tag tag) =>
    HexColor(tag.colour, defaultColor: Theme.of(context).colorScheme.primary);

class TagChip extends StatelessWidget {
  const TagChip({
    required this.tag,
    this.selected = true,
    this.onTap,
    this.onLongPress,
    this.small = false,
    super.key,
  });
  final Tag tag;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool small;

  @override
  Widget build(BuildContext context) {
    Color color = tagColor(context, tag);
    return Tappable(
      borderRadius: small ? 6 : 10,
      color: selected
          ? color.withOpacity(small ? 0.2 : 0.3)
          : getColor(context, "lightDarkAccentHeavyLight"),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsetsDirectional.symmetric(
            horizontal: small ? 6 : 12, vertical: small ? 2 : 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(small ? 6 : 10),
          border: small
              ? null
              : Border.all(
                  color: selected ? color : Colors.transparent, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tagIcon(), size: small ? 11 : 15, color: color),
            SizedBox(width: small ? 3 : 6),
            Flexible(
              child: TextFont(
                text: tag.name,
                fontSize: small ? 11 : 14,
                fontWeight:
                    selected && !small ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Tags of a transaction picked as chips, with a chip to create a new one.
// Long press a chip to edit the tag.
class SelectTags extends StatelessWidget {
  const SelectTags({
    required this.selectedTagPks,
    required this.onChanged,
    super.key,
  });
  final List<String> selectedTagPks;
  final Function(List<String> tagPks) onChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tag>>(
      stream: database.watchAllTags(),
      builder: (context, snapshot) {
        List<Tag> tags = (snapshot.data ?? [])
            .where(
                (t) => t.archived == false || selectedTagPks.contains(t.tagPk))
            .toList();
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (Tag tag in tags)
              TagChip(
                tag: tag,
                selected: selectedTagPks.contains(tag.tagPk),
                onTap: () {
                  bool isSelected = selectedTagPks.contains(tag.tagPk);
                  onChanged(isSelected
                      ? ([...selectedTagPks]..remove(tag.tagPk))
                      : [...selectedTagPks, tag.tagPk]);
                },
                onLongPress: () => openEditTagPopup(context, tag: tag),
              ),
            Tappable(
              borderRadius: 10,
              color: getColor(context, "lightDarkAccentHeavyLight"),
              onTap: () async {
                String? tagPk = await openEditTagPopup(context);
                if (tagPk != null) onChanged([...selectedTagPks, tagPk]);
              },
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                    horizontal: 12, vertical: 9.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.add_outlined
                          : Icons.add_rounded,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    TextFont(
                      text: tags.isEmpty ? "new-tag".tr() : "tag".tr(),
                      fontSize: 14,
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

// Small chips with the tags of a transaction, for the transaction entries
class TransactionTagsLine extends StatelessWidget {
  const TransactionTagsLine({required this.transactionPk, super.key});
  final String transactionPk;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, List<String>>>(
      valueListenable: tagPksByTransaction,
      builder: (context, byTransaction, _) {
        List<Tag> tags = [
          for (String tagPk in byTransaction[transactionPk] ?? [])
            if (tagsCache[tagPk] != null) tagsCache[tagPk]!
        ];
        if (tags.isEmpty) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: 3),
          child: Wrap(
            spacing: 4,
            runSpacing: 3,
            children: [
              for (Tag tag in tags) TagChip(tag: tag, small: true),
            ],
          ),
        );
      },
    );
  }
}

// Returns the pk of the saved tag
Future<String?> openEditTagPopup(BuildContext context, {Tag? tag}) async {
  dynamic result = await openBottomSheet(
    context,
    popupWithKeyboard: true,
    EditTagPopup(tag: tag),
  );
  return result is String ? result : null;
}

class EditTagPopup extends StatefulWidget {
  const EditTagPopup({this.tag, super.key});
  final Tag? tag;

  @override
  State<EditTagPopup> createState() => _EditTagPopupState();
}

class _EditTagPopupState extends State<EditTagPopup> {
  late String name = widget.tag?.name ?? "";
  late Color? colour =
      widget.tag?.colour == null ? null : HexColor(widget.tag!.colour);
  final FocusNode nameFocus = FocusNode();
  late double? budgetAmount = widget.tag?.budgetAmount;
  late DateTime? budgetStart = widget.tag?.budgetStart;
  late DateTime? budgetEnd = widget.tag?.budgetEnd;

  Future<void> selectBudgetAmount() async {
    await openBottomSheet(
      context,
      fullSnap: true,
      PopupFramework(
        title: "tag-budget-limit".tr(),
        subtitle: "tag-budget-limit-description".tr(),
        hasPadding: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: SelectAmount(
            amountPassed:
                (budgetAmount ?? 0) == 0 ? "" : budgetAmount.toString(),
            allowZero: true,
            setSelectedAmount: (amount, _) => setState(
                () => budgetAmount = amount.abs() == 0 ? null : amount.abs()),
            next: () => popRoute(context),
            nextLabel: "set-amount".tr(),
          ),
        ),
      ),
    );
  }

  Future<void> selectBudgetDates() async {
    DateTimeRangeOrAllTime result = await showCustomDateRangePicker(
      context,
      budgetStart != null && budgetEnd != null
          ? DateTimeRangeOrAllTime(
              allTime: false,
              dateTimeRange:
                  DateTimeRange(start: budgetStart!, end: budgetEnd!))
          : DateTimeRangeOrAllTime(allTime: true),
      allTimeButton: true,
    );
    setState(() {
      budgetStart = result.allTime ? null : result.dateTimeRange?.start;
      budgetEnd = result.allTime ? null : result.dateTimeRange?.end;
    });
  }

  @override
  void initState() {
    super.initState();
    // autofocus gets lost on the web while the sheet slides in, so ask for
    // the focus once it is open
    if (widget.tag == null)
      Future.delayed(Duration(milliseconds: 300), () {
        if (mounted) nameFocus.requestFocus();
      });
  }

  @override
  void dispose() {
    nameFocus.dispose();
    super.dispose();
  }

  Future<void> deleteTag() async {
    dynamic confirmed = await openPopup(
      context,
      title: asQuestion("delete-tag".tr()),
      description: "delete-tag-description".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.delete_outlined
          : Icons.delete_rounded,
      onSubmit: () => popRoute(context, true),
      onSubmitLabel: "delete".tr(),
      onCancel: () => popRoute(context, false),
      onCancelLabel: "cancel".tr(),
    );
    if (confirmed == true) {
      await database.deleteTag(widget.tag!.tagPk);
      popRoute(context);
    }
  }

  Future<void> save() async {
    if (name.trim() == "") return;
    String tagPk = await database.createOrUpdateTag(
      insert: widget.tag == null,
      Tag(
        tagPk: widget.tag?.tagPk ?? "-1",
        name: name.trim(),
        colour: colour == null ? null : toHexString(colour!),
        order: widget.tag?.order ?? 0,
        archived: widget.tag?.archived ?? false,
        iconName: widget.tag?.iconName,
        emojiIconName: widget.tag?.emojiIconName,
        dateCreated: widget.tag?.dateCreated ?? DateTime.now(),
        dateTimeModified: null,
        budgetAmount: budgetAmount,
        budgetStart: budgetAmount == null ? null : budgetStart,
        budgetEnd: budgetAmount == null ? null : budgetEnd,
      ),
    );
    popRoute(context, tagPk);
  }

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: widget.tag == null ? "new-tag".tr() : "edit-tag".tr(),
      outsideExtraWidget: widget.tag == null
          ? null
          : OutsideExtraWidgetIconButton(
              iconData: appStateSettings["outlinedIcons"]
                  ? Icons.delete_outlined
                  : Icons.delete_rounded,
              onPressed: deleteTag,
            ),
      child: Column(
        children: [
          TextInput(
            labelText: "name-placeholder".tr(),
            initialValue: name,
            focusNode: nameFocus,
            onChanged: (text) => setState(() => name = text),
            onSubmitted: (_) => save(),
            padding: EdgeInsetsDirectional.zero,
          ),
          SizedBox(height: 12),
          SelectColor(
            popOnSelect: false,
            selectedColor: colour,
            setSelectedColor: (color) => setState(() => colour = color),
          ),
          SizedBox(height: 12),
          SettingsContainer(
            enableBorderRadius: true,
            title: "tag-budget-limit".tr(),
            description: budgetAmount == null
                ? "tag-budget-limit-description".tr()
                : convertToMoney(
                    Provider.of<AllWallets>(context), budgetAmount!),
            icon: appStateSettings["outlinedIcons"]
                ? Icons.savings_outlined
                : Icons.savings_rounded,
            onTap: selectBudgetAmount,
          ),
          if (budgetAmount != null)
            SettingsContainer(
              enableBorderRadius: true,
              title: "date-range".tr(),
              description: tagBudgetDatesLabel(Tag(
                tagPk: "",
                name: "",
                order: 0,
                archived: false,
                dateCreated: DateTime.now(),
                budgetStart: budgetStart,
                budgetEnd: budgetEnd,
              )),
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.date_range_outlined
                  : Icons.date_range_rounded,
              onTap: selectBudgetDates,
            ),
          if (widget.tag != null && budgetAmount != null)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 4, vertical: 8),
              child: TagBudgetProgress(
                tag: widget.tag!.copyWith(
                  budgetAmount: Value(budgetAmount),
                  budgetStart: Value(budgetStart),
                  budgetEnd: Value(budgetEnd),
                ),
              ),
            ),
          SizedBox(height: 12),
          Button(
            label: widget.tag == null ? "new-tag".tr() : "save-changes".tr(),
            disabled: name.trim() == "",
            onTap: save,
          ),
        ],
      ),
    );
  }
}

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "tags".tr(),
      dragDownToDismiss: true,
      floatingActionButton: AnimateFABDelayed(
        fab: FAB(
          tooltip: "new-tag".tr(),
          openPage: SizedBox.shrink(),
          onTap: () => openEditTagPopup(context),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 600,
            child: StreamBuilder<List<Tag>>(
              stream: database.watchAllTags(),
              builder: (context, snapshot) {
                List<Tag> tags = snapshot.data ?? [];
                if (snapshot.hasData && tags.isEmpty) {
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(
                        top: 30, start: 20, end: 20),
                    child: TextFont(
                      text: "no-tags".tr(),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      textColor: getColor(context, "textLight"),
                    ),
                  );
                }
                return ValueListenableBuilder<Map<String, List<String>>>(
                  valueListenable: tagPksByTransaction,
                  builder: (context, byTransaction, _) {
                    Map<String, int> counts = {};
                    for (List<String> tagPks in byTransaction.values) {
                      for (String tagPk in tagPks) {
                        counts[tagPk] = (counts[tagPk] ?? 0) + 1;
                      }
                    }
                    return ReorderableListView(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) async {
                        if (newIndex > oldIndex) newIndex--;
                        List<Tag> ordered = [...tags];
                        ordered.insert(newIndex, ordered.removeAt(oldIndex));
                        await database.reorderTags(ordered);
                      },
                      children: [
                        for (int index = 0; index < tags.length; index++)
                          Padding(
                            key: ValueKey(tags[index].tagPk),
                            padding:
                                const EdgeInsetsDirectional.only(bottom: 8),
                            child: Tappable(
                              borderRadius: 15,
                              color: getColor(
                                  context, "lightDarkAccentHeavyLight"),
                              onTap: () =>
                                  openEditTagPopup(context, tag: tags[index]),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                    start: 16, top: 6, bottom: 6, end: 4),
                                child: Row(
                                  children: [
                                    Icon(tagIcon(),
                                        color: tagColor(context, tags[index])),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          TextFont(
                                            text: tags[index].name,
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          if (tagHasBudget(tags[index]))
                                            TextFont(
                                              text: "tag-budget-limit".tr() +
                                                  " " +
                                                  convertToMoney(
                                                      Provider.of<AllWallets>(
                                                          context),
                                                      tags[index]
                                                          .budgetAmount!) +
                                                  " · " +
                                                  tagBudgetDatesLabel(
                                                      tags[index]),
                                              fontSize: 13,
                                              textColor: getColor(
                                                  context, "textLight"),
                                            ),
                                        ],
                                      ),
                                    ),
                                    TextFont(
                                      text: (counts[tags[index].tagPk] ?? 0)
                                          .toString(),
                                      fontSize: 14,
                                      textColor: getColor(context, "textLight"),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: Padding(
                                        padding:
                                            const EdgeInsetsDirectional.all(12),
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

// Picks tags to add to several transactions at once (multi select menu)
class AddTagsPopup extends StatefulWidget {
  const AddTagsPopup({super.key});

  @override
  State<AddTagsPopup> createState() => _AddTagsPopupState();
}

class _AddTagsPopupState extends State<AddTagsPopup> {
  List<String> selectedTagPks = [];

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "add-tags".tr(),
      child: Column(
        children: [
          SelectTags(
            selectedTagPks: selectedTagPks,
            onChanged: (tagPks) => setState(() => selectedTagPks = tagPks),
          ),
          SizedBox(height: 15),
          Button(
            label: "add-tags".tr(),
            disabled: selectedTagPks.isEmpty,
            onTap: () => popRoute(context, selectedTagPks),
          ),
        ],
      ),
    );
  }
}
