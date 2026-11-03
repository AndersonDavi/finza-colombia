import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';

// Undo for deleted transactions: they are put back as they were and their
// delete logs removed, so syncing does not delete them again
extension UndoDeleteTransactions on FinanceDatabase {
  Future<List<Transaction>> getTransactionsFromPks(
      List<String> transactionPks) {
    return (select(transactions)
          ..where((t) => t.transactionPk.isIn(transactionPks)))
        .get();
  }

  // tags: the tags of the transactions before they were deleted
  Future<void> restoreTransactions(List<Transaction> deleted,
      {Map<String, List<String>> tags = const {}}) async {
    await batch((batch) {
      for (Transaction transaction in deleted) {
        batch.insert(
          transactions,
          transaction.copyWith(dateTimeModified: Value(DateTime.now())),
          mode: InsertMode.insertOrReplace,
        );
        for (String tagPk in tags[transaction.transactionPk] ?? []) {
          batch.insert(
            transactionToTagLinks,
            TransactionToTagLinksCompanion.insert(
                transactionPk: Value(transaction.transactionPk),
                tagPk: Value(tagPk)),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    });
    await (delete(deleteLogs)
          ..where((log) =>
              log.entryPk.isIn(deleted.map((t) => t.transactionPk)) &
              log.type.equalsValue(DeleteLogType.Transaction)))
        .go();
  }
}
