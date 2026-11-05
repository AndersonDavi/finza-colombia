import 'package:budget/database/tables.dart';
import 'package:budget/struct/country.dart';
import 'package:drift/drift.dart';

// Queries for the groups of accounts (where the money is kept: a bank, cash)
extension WalletGroupQueries on FinanceDatabase {
  Stream<List<WalletGroup>> watchAllWalletGroups() {
    return (select(walletGroups)..orderBy([(g) => OrderingTerm.asc(g.order)]))
        .watch();
  }

  Future<List<WalletGroup>> getAllWalletGroups() {
    return (select(walletGroups)..orderBy([(g) => OrderingTerm.asc(g.order)]))
        .get();
  }

  Future<String> createOrUpdateWalletGroup(WalletGroup group,
      {bool insert = false}) async {
    WalletGroupsCompanion companion = group
        .copyWith(dateTimeModified: Value(DateTime.now()))
        .toCompanion(true);
    if (insert) {
      int count = (await getAllWalletGroups()).length;
      companion = companion.copyWith(
          walletGroupPk: Value.absent(), order: Value(count));
      await into(walletGroups).insert(companion);
      return (await getAllWalletGroups()).last.walletGroupPk;
    }
    await into(walletGroups).insertOnConflictUpdate(companion);
    return group.walletGroupPk;
  }

  // For syncing: groups changed since the last sync. A database from before
  // groups existed has no table, then there is nothing to sync.
  Future<List<WalletGroup>> getAllNewWalletGroups(DateTime lastSynced) async {
    try {
      return await (select(walletGroups)
            ..where((g) => g.dateTimeModified.isBiggerOrEqualValue(lastSynced)))
          .get();
    } catch (e) {
      print("No wallet groups to sync: " + e.toString());
      return [];
    }
  }

  // The accounts of the group stay, they just stop belonging to one
  Future<void> deleteWalletGroup(String walletGroupPk) async {
    await createDeleteLog(DeleteLogType.WalletGroup, walletGroupPk);
    await (update(wallets)..where((w) => w.walletGroupFk.equals(walletGroupPk)))
        .write(WalletsCompanion(
      walletGroupFk: Value(null),
      dateTimeModified: Value(DateTime.now()),
    ));
    await (delete(walletGroups)
          ..where((g) => g.walletGroupPk.equals(walletGroupPk)))
        .go();
  }

  // Creates the free pocket of a new group and marks it as such
  Future<void> createFreePocket(String walletGroupPk,
      {required String name, String? colour, String? currency}) async {
    int numberOfWallets = (await getTotalCountOfWallets())[0] ?? 0;
    await createOrUpdateWallet(
      insert: true,
      TransactionWallet(
        walletPk: "-1",
        name: name,
        colour: colour,
        dateCreated: DateTime.now(),
        order: numberOfWallets,
        currency: currency,
        decimals: defaultPocketDecimals(),
        archived: false,
        walletGroupFk: walletGroupPk,
      ),
    );
    TransactionWallet? pocket = (await getAllWallets())
        .where((w) => w.walletGroupFk == walletGroupPk)
        .firstOrNull;
    WalletGroup? group = (await getAllWalletGroups())
        .where((g) => g.walletGroupPk == walletGroupPk)
        .firstOrNull;
    if (pocket != null && group != null) {
      await createOrUpdateWalletGroup(
          group.copyWith(freeWalletFk: Value(pocket.walletPk)));
    }
  }

  // Groups made before free pockets were marked: the pocket named Libre/Free
  // becomes the marked one, so renaming it later keeps it as the free pocket
  Future<void> markDetectedFreePockets(List<WalletGroup> groups) async {
    List<TransactionWallet> wallets = await getAllWallets();
    for (WalletGroup group in groups) {
      if (group.freeWalletFk != null) continue;
      String? detected = freeWalletPkOfGroup(group, wallets);
      if (detected != null) {
        await createOrUpdateWalletGroup(
            group.copyWith(freeWalletFk: Value(detected)));
      }
    }
  }

  Future<void> setWalletGroup(String walletPk, String? walletGroupPk) async {
    await (update(wallets)..where((w) => w.walletPk.equals(walletPk)))
        .write(WalletsCompanion(
      walletGroupFk: Value(walletGroupPk),
      dateTimeModified: Value(DateTime.now()),
    ));
  }
}

// The pocket of the group with the money that is free to spend: the one chosen
// in the group, or else one named "Libre" / "Free"
String? freeWalletPkOfGroup(WalletGroup group, List<TransactionWallet> wallets) {
  List<TransactionWallet> pockets =
      wallets.where((w) => w.walletGroupFk == group.walletGroupPk).toList();
  if (group.freeWalletFk != null &&
      pockets.any((w) => w.walletPk == group.freeWalletFk)) {
    return group.freeWalletFk;
  }
  for (TransactionWallet wallet in pockets) {
    String name = wallet.name.trim().toLowerCase();
    if (name == "libre" || name == "free") return wallet.walletPk;
  }
  return null;
}
