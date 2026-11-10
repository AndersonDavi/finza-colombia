import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/pinnedTransactions.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// One movement at a time: give it a title, a category and an account, save,
// and the next one shows up
class ReviewInboxPage extends StatefulWidget {
  const ReviewInboxPage({super.key});

  @override
  State<ReviewInboxPage> createState() => _ReviewInboxPageState();
}

class _ReviewInboxPageState extends State<ReviewInboxPage> {
  // Skipped ones go to the end of the line for this visit
  List<String> skipped = [];
  String? shownPk;
  TextEditingController titleController = TextEditingController();
  String? categoryPk;
  String? walletPk;
  // A category picked by hand is not replaced by the title suggestion
  bool categoryPickedByHand = false;

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  void show(Transaction transaction) {
    if (shownPk == transaction.transactionPk) return;
    shownPk = transaction.transactionPk;
    String name = transaction.name.trim();
    titleController.text = name == "?" ? "" : name;
    categoryPk = transaction.categoryFk;
    walletPk = transaction.walletFk;
    categoryPickedByHand = false;
  }

  Future<void> suggestCategory(String title) async {
    if (categoryPickedByHand || title.trim().length < 3) return;
    List<TransactionAssociatedTitleWithCategory> found = await database
        .getSimilarAssociatedTitles(title: title.trim(), limit: 1);
    if (found.isEmpty || !mounted) return;
    setState(() => categoryPk = found.first.category.categoryPk);
  }

  Future<void> save(Transaction transaction) async {
    String title = titleController.text.trim();
    Transaction updated = transaction.copyWith(
      name: title == "" ? transaction.name : title,
      categoryFk: categoryPk ?? transaction.categoryFk,
      walletFk: walletPk ?? transaction.walletFk,
    );
    await database.createOrUpdateTransaction(updated,
        originalTransaction: transaction);
    List<String> tagPks = reviewTagPks();
    for (String tagPk in tagPks) {
      await database
          .removeTagFromTransactions([transaction.transactionPk], tagPk);
    }
    // Next time this title picks the same category by itself
    if (title != "" && categoryPk != null) {
      await addAssociatedTitles(
          title, await database.getCategoryInstance(categoryPk!));
    }
    shownPk = null;
  }

  void skip(Transaction transaction) {
    setState(() {
      skipped.add(transaction.transactionPk);
      shownPk = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      title: "to-review".tr(),
      backButton: true,
      dragDownToDismiss: true,
      listWidgets: [
        StreamBuilder<List<Transaction>>(
          stream: database.watchTransactionsToReview(reviewTagPks()),
          builder: (context, snapshot) {
            List<Transaction> pending = snapshot.data ?? [];
            if (snapshot.hasData == false) return SizedBox.shrink();
            if (pending.isEmpty) return reviewDone();
            // Skipped ones last, keeping their order
            List<Transaction> queue = [
              ...pending.where((t) => !skipped.contains(t.transactionPk)),
              ...pending.where((t) => skipped.contains(t.transactionPk)),
            ];
            Transaction transaction = queue.firstWhere(
                (t) => t.transactionPk == shownPk,
                orElse: () => queue.first);
            show(transaction);
            int position = queue.indexOf(transaction) + 1;
            return reviewCard(transaction, position, queue.length);
          },
        ),
      ],
    );
  }

  Widget reviewDone() {
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        children: [
          Icon(Icons.task_alt_rounded,
              size: 56, color: getColor(context, "incomeAmount")),
          SizedBox(height: 12),
          TextFont(
            text: "review-done".tr(),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6),
          TextFont(
            text: "review-done-description".tr(),
            fontSize: 15,
            textAlign: TextAlign.center,
            textColor: getColor(context, "textLight"),
          ),
        ],
      ),
    );
  }

  Widget sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 18, bottom: 8),
      child: TextFont(
        text: text.capitalizeFirst,
        fontSize: 15,
        fontWeight: FontWeight.bold,
        textColor: getColor(context, "textLight"),
      ),
    );
  }

  Widget choiceChip({
    required bool selected,
    required Color color,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return Tappable(
      onTap: onTap,
      borderRadius: 12,
      color: selected
          ? color.withOpacity(0.25)
          : getColor(context, "lightDarkAccentHeavyLight"),
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget reviewCard(Transaction transaction, int position, int total) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    TransactionWallet? wallet = allWallets.indexedByPk[transaction.walletFk];
    bool isIncome = transaction.amount > 0;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFont(
            text: position.toString() +
                " " +
                "review-progress".tr() +
                " " +
                total.toString(),
            fontSize: 14,
            textColor: getColor(context, "textLight"),
          ),
          SizedBox(height: 8),
          Container(
            padding: const EdgeInsetsDirectional.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: getColor(context, "lightDarkAccentHeavyLight"),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                  text: convertToMoney(allWallets, transaction.amount,
                      currencyKey: wallet?.currency,
                      decimals: wallet?.decimals),
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  textColor: getColor(
                      context, isIncome ? "incomeAmount" : "expenseAmount"),
                ),
                SizedBox(height: 4),
                TextFont(
                  text: getWordedDateShortMore(transaction.dateCreated,
                          includeTime: true, includeYear: true) +
                      (wallet == null
                          ? ""
                          : " · " + getWalletStringName(allWallets, wallet)),
                  fontSize: 15,
                  textColor: getColor(context, "textLight"),
                  maxLines: 2,
                ),
                if ((transaction.note).trim() != "")
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 10),
                    child: TextFont(
                      text: transaction.note.trim(),
                      fontSize: 13,
                      maxLines: 6,
                      textColor: getColor(context, "textLight"),
                    ),
                  ),
              ],
            ),
          ),
          sectionLabel("title".tr()),
          TextInput(
            labelText: "title".tr(),
            controller: titleController,
            padding: EdgeInsetsDirectional.zero,
            onChanged: suggestCategory,
          ),
          sectionLabel("category".tr()),
          StreamBuilder<List<TransactionCategory>>(
            stream: database.watchAllCategories(selectedIncome: isIncome),
            builder: (context, snapshot) {
              List<TransactionCategory> categories = snapshot.data ?? [];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (TransactionCategory category in categories)
                    choiceChip(
                      selected: category.categoryPk == categoryPk,
                      color: HexColor(category.colour,
                          defaultColor: Theme.of(context).colorScheme.primary),
                      onTap: () => setState(() {
                        categoryPk = category.categoryPk;
                        categoryPickedByHand = true;
                      }),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryIcon(
                            categoryPk: category.categoryPk,
                            category: category,
                            size: 18,
                            sizePadding: 6,
                            borderRadius: 100,
                            canEditByLongPress: false,
                          ),
                          SizedBox(width: 6),
                          TextFont(text: category.name, fontSize: 14),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          sectionLabel("account".tr()),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (TransactionWallet option in allWallets.list)
                if (option.currency == wallet?.currency)
                  choiceChip(
                    selected: option.walletPk == walletPk,
                    color: pickedColor(context, option.colour),
                    onTap: () => setState(() => walletPk = option.walletPk),
                    child: TextFont(
                      text: getWalletStringName(allWallets, option),
                      fontSize: 14,
                    ),
                  ),
            ],
          ),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Button(
                  label: "skip".tr(),
                  expandedLayout: true,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  onTap: () => skip(transaction),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Button(
                  label: "save-and-next".tr(),
                  expandedLayout: true,
                  onTap: () => save(transaction),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => pushRoute(
                context,
                AddTransactionPage(
                  transaction: transaction,
                  routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                ),
              ),
              child: Text("open-full".tr()),
            ),
          ),
          SizedBox(height: 40),
        ],
      ),
    );
  }
}
