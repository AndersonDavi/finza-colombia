import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

// Tags of every transaction (transactionPk -> tagPks), kept current by the
// listener in main.dart so the transaction entries can show them
ValueNotifier<Map<String, List<String>>> tagPksByTransaction =
    ValueNotifier({});
Map<String, Tag> tagsCache = {};

// Queries for the tags of the transactions (tables from the official 6.x app)
extension TagQueries on FinanceDatabase {
  Stream<List<Tag>> watchAllTags() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.order)])).watch();
  }

  Future<List<Tag>> getAllTags() {
    return (select(tags)..orderBy([(t) => OrderingTerm.asc(t.order)])).get();
  }

  Future<String> createOrUpdateTag(Tag tag, {bool insert = false}) async {
    TagsCompanion companion =
        tag.copyWith(dateTimeModified: Value(DateTime.now())).toCompanion(true);
    if (insert) {
      int count = (await getAllTags()).length;
      companion =
          companion.copyWith(tagPk: Value.absent(), order: Value(count));
      await into(tags).insert(companion);
      return (await getAllTags()).last.tagPk;
    }
    await into(tags).insertOnConflictUpdate(companion);
    return tag.tagPk;
  }

  Future<void> reorderTags(List<Tag> ordered) async {
    await batch((batch) {
      for (int i = 0; i < ordered.length; i++) {
        batch.update(
          tags,
          TagsCompanion(
              order: Value(i), dateTimeModified: Value(DateTime.now())),
          where: (t) => t.tagPk.equals(ordered[i].tagPk),
        );
      }
    });
  }

  Future<void> deleteTag(String tagPk) async {
    await createDeleteLog(DeleteLogType.Tag, tagPk);
    await (delete(transactionToTagLinks)..where((l) => l.tagPk.equals(tagPk)))
        .go();
    await (delete(tags)..where((t) => t.tagPk.equals(tagPk))).go();
  }

  Stream<List<TransactionToTagLink>> watchAllTagLinks() {
    return select(transactionToTagLinks).watch();
  }

  Future<List<String>> getTagPksOfTransaction(String transactionPk) async {
    return (await (select(transactionToTagLinks)
              ..where((l) => l.transactionPk.equals(transactionPk)))
            .get())
        .map((l) => l.tagPk ?? "")
        .where((pk) => pk != "")
        .toList();
  }

  // Replaces the tags of a transaction. The transaction is touched too so the
  // other devices pick up the new tags on the next sync.
  Future<void> setTransactionTags(
      String transactionPk, List<String> tagPks) async {
    List<String> current = await getTagPksOfTransaction(transactionPk);
    if (listEquals(current..sort(), [...tagPks]..sort())) return;
    await transaction(() async {
      await (delete(transactionToTagLinks)
            ..where((l) => l.transactionPk.equals(transactionPk)))
          .go();
      for (String tagPk in tagPks) {
        await into(transactionToTagLinks).insert(
            TransactionToTagLinksCompanion.insert(
                transactionPk: Value(transactionPk), tagPk: Value(tagPk)),
            mode: InsertMode.insertOrIgnore);
      }
      await (update(transactions)
            ..where((t) => t.transactionPk.equals(transactionPk)))
          .write(
              TransactionsCompanion(dateTimeModified: Value(DateTime.now())));
    });
  }

  // Adds the tags to every transaction, keeping the ones they already have
  Future<void> addTagsToTransactions(
      List<String> transactionPks, List<String> tagPks) async {
    for (String transactionPk in transactionPks) {
      List<String> current = await getTagPksOfTransaction(transactionPk);
      await setTransactionTags(transactionPk, {...current, ...tagPks}.toList());
    }
  }

  Future<void> deleteTagLinksOfTransactions(List<String> transactionPks) async {
    await (delete(transactionToTagLinks)
          ..where((l) => l.transactionPk.isIn(transactionPks)))
        .go();
  }

  // For syncing. A database from before tags existed has no tables.
  Future<List<Tag>> getAllNewTags(DateTime lastSynced) async {
    try {
      return await (select(tags)
            ..where((t) => t.dateTimeModified.isBiggerOrEqualValue(lastSynced)))
          .get();
    } catch (e) {
      print("No tags to sync: " + e.toString());
      return [];
    }
  }

  Future<Map<String, List<TransactionToTagLink>>> getTagLinksOfTransactions(
      List<String> transactionPks) async {
    Map<String, List<TransactionToTagLink>> result = {
      for (String pk in transactionPks) pk: []
    };
    try {
      for (TransactionToTagLink link in await (select(transactionToTagLinks)
            ..where((l) => l.transactionPk.isIn(transactionPks)))
          .get()) {
        result[link.transactionPk]?.add(link);
      }
    } catch (e) {
      print("No tag links to sync: " + e.toString());
    }
    return result;
  }

  Future<void> setPinned(List<String> transactionPks, bool pinned) async {
    await (update(transactions)
          ..where((t) => t.transactionPk.isIn(transactionPks)))
        .write(TransactionsCompanion(
      pinned: Value(pinned ? true : null),
      dateTimeModified: Value(DateTime.now()),
    ));
  }

  // Transactions carrying a tag, newest first (the MCP's "Por revisar" ones)
  Stream<List<Transaction>> watchTransactionsWithTag(String tagPk) {
    return (select(transactions)
          ..where(
              (t) => t.transactionPk.isInQuery(selectOnly(transactionToTagLinks)
                ..addColumns([transactionToTagLinks.transactionPk])
                ..where(transactionToTagLinks.tagPk.equals(tagPk))))
          ..orderBy([(t) => OrderingTerm.desc(t.dateCreated)]))
        .watch();
  }

  // Review inbox: what carries one of the review tags, plus movements named
  // just "?"
  Stream<List<Transaction>> watchTransactionsToReview(List<String> tagPks) {
    return (select(transactions)
          ..where((t) =>
              t.name.trim().equals("?") |
              t.transactionPk.isInQuery(selectOnly(transactionToTagLinks)
                ..addColumns([transactionToTagLinks.transactionPk])
                ..where(transactionToTagLinks.tagPk.isIn(tagPks))))
          ..orderBy([(t) => OrderingTerm.desc(t.dateCreated)]))
        .watch();
  }

  Future<void> removeTagFromTransactions(
      List<String> transactionPks, String tagPk) async {
    for (String transactionPk in transactionPks) {
      List<String> current = await getTagPksOfTransaction(transactionPk);
      await setTransactionTags(
          transactionPk, current.where((pk) => pk != tagPk).toList());
    }
  }

  Stream<List<Transaction>> watchPinnedTransactions() {
    return (select(transactions)
          ..where((t) => t.pinned.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.dateCreated)]))
        .watch();
  }
}
