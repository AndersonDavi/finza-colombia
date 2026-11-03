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

  Future<void> restoreTransactions(List<Transaction> deleted) async {
    await batch((batch) {
      for (Transaction transaction in deleted) {
        batch.insert(
          transactions,
          transaction.copyWith(dateTimeModified: Value(DateTime.now())),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
    await (delete(deleteLogs)
          ..where((log) =>
              log.entryPk.isIn(deleted.map((t) => t.transactionPk)) &
              log.type.equalsValue(DeleteLogType.Transaction)))
        .go();
  }
}
