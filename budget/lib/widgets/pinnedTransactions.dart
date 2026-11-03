import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/tags.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Pinned transactions on top of the transactions list, whatever their date
class PinnedTransactionsSection extends StatelessWidget {
  const PinnedTransactionsSection(
      {required this.listID, this.constrained = true, super.key});
  final String listID;
  // False inside narrow places like the home page list
  final bool constrained;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: database.watchPinnedTransactions(),
      builder: (context, snapshot) {
        List<Transaction> pinned = snapshot.data ?? [];
        if (pinned.isEmpty) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: (constrained ? getHorizontalPaddingConstrained(context) : 0) + 20,
                  end: (constrained ? getHorizontalPaddingConstrained(context) : 0) + 20,
                  top: 6,
                  bottom: 4,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: getColor(context, "textLight"),
                    ),
                    SizedBox(width: 6),
                    TextFont(
                      text: "pinned".tr(),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      textColor: getColor(context, "textLight"),
                    ),
                  ],
                ),
              ),
              for (int index = 0; index < pinned.length; index++)
                TransactionEntry(
                  key: ValueKey("pinned" + pinned[index].transactionPk),
                  openPage: AddTransactionPage(
                    transaction: pinned[index],
                    routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                  ),
                  transaction: pinned[index],
                  listID: listID,
                  useHorizontalPaddingConstrained: constrained,
                  transactionBefore: nullIfIndexOutOfRange(pinned, index - 1),
                  transactionAfter: nullIfIndexOutOfRange(pinned, index + 1),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Movements the MCP added from the bank emails, until they are confirmed.
// The MCP tags them with this fixed tag pk.
const String reviewTagPk = "por-revisar";

class ReviewTransactionsSection extends StatelessWidget {
  const ReviewTransactionsSection(
      {required this.listID, this.constrained = true, super.key});
  final String listID;
  final bool constrained;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Transaction>>(
      stream: database.watchTransactionsWithTag(reviewTagPk),
      builder: (context, snapshot) {
        List<Transaction> pending = snapshot.data ?? [];
        if (pending.isEmpty) return SizedBox.shrink();
        Color color = getColor(context, "unPaidUpcoming");
        return Container(
          margin: EdgeInsetsDirectional.only(
            start: (constrained ? getHorizontalPaddingConstrained(context) : 0) + 10,
            end: (constrained ? getHorizontalPaddingConstrained(context) : 0) + 10,
            bottom: 10,
          ),
          padding: const EdgeInsetsDirectional.only(top: 8, bottom: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: color.withOpacity(0.08),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.mark_email_unread_rounded, size: 18, color: color),
                    SizedBox(width: 8),
                    Expanded(
                      child: TextFont(
                        text: "to-review".tr() +
                            " (" +
                            pending.length.toString() +
                            ")",
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => database.removeTagFromTransactions(
                          [for (Transaction t in pending) t.transactionPk],
                          reviewTagPk),
                      icon: Icon(Icons.done_all_rounded, size: 18),
                      label: Text("confirm-all".tr()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
                child: TextFont(
                  text: "to-review-description".tr(),
                  fontSize: 13,
                  maxLines: 3,
                  textColor: getColor(context, "textLight"),
                ),
              ),
              SizedBox(height: 4),
              for (int index = 0; index < pending.length; index++)
                Row(
                  children: [
                    Expanded(
                      child: TransactionEntry(
                        key: ValueKey("review" + pending[index].transactionPk),
                        openPage: AddTransactionPage(
                          transaction: pending[index],
                          routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                        ),
                        transaction: pending[index],
                        listID: listID,
                        useHorizontalPaddingConstrained: constrained,
                        transactionBefore:
                            nullIfIndexOutOfRange(pending, index - 1),
                        transactionAfter:
                            nullIfIndexOutOfRange(pending, index + 1),
                      ),
                    ),
                    IconButton(
                      tooltip: "confirm".tr(),
                      onPressed: () => database.removeTagFromTransactions(
                          [pending[index].transactionPk], reviewTagPk),
                      icon: Icon(Icons.check_circle_outline_rounded,
                          color: color),
                    ),
                    SizedBox(width: 4),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
