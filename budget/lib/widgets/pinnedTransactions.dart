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
  const PinnedTransactionsSection({required this.listID, super.key});
  final String listID;

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
                  start: getHorizontalPaddingConstrained(context) + 20,
                  end: getHorizontalPaddingConstrained(context) + 20,
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
