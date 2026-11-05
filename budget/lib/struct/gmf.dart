import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/walletGroups.dart';
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// The 4x1000 (GMF): what a Colombian bank takes on every debit. It is added
// as its own expense in the same pocket, so the balance matches the bank's.

const String gmfCategoryPk = "gmf";

Future<TransactionCategory> initializeGmfCategory() async {
  TransactionCategory? category =
      await database.getCategoryInstanceOrNull(gmfCategoryPk);
  if (category != null) return category;
  await database.createOrUpdateCategory(
    insert: false,
    updateSharedEntry: false,
    TransactionCategory(
      archived: false,
      categoryPk: gmfCategoryPk,
      name: "gmf-category-name".tr(),
      colour: toHexString(Colors.blueGrey),
      iconName: "bank.png",
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      order: await database.getAmountOfCategories(),
      income: false,
    ),
  );
  return await database.getCategoryInstance(gmfCategoryPk);
}

// For a transaction just added by hand
Future<void> chargeGmfForTransaction(Transaction transaction) async {
  if (transaction.income || transaction.amount >= 0) return;
  if (transaction.paid == false) return;
  if (transaction.categoryFk == "0" ||
      transaction.categoryFk == gmfCategoryPk) {
    return;
  }
  TransactionWallet? wallet =
      await database.getWalletInstanceOrNull(transaction.walletFk);
  if (wallet == null) return;
  await chargeGmf(
    wallet: wallet,
    debit: transaction.amount.abs(),
    date: transaction.dateCreated,
    title: transaction.name,
  );
}

// debit is in the pocket's own currency. Moving money between pockets of the
// same account is not a debit at the bank, so toWallet in the same account
// is free.
Future<void> chargeGmf({
  required TransactionWallet wallet,
  required double debit,
  required DateTime date,
  TransactionWallet? toWallet,
  String title = "",
}) async {
  if (livesInColombia() == false || debit <= 0) return;
  if (wallet.walletGroupFk == null) return;
  if (toWallet != null && toWallet.walletGroupFk == wallet.walletGroupFk) {
    return;
  }
  WalletGroup? group = (await database.getAllWalletGroups())
      .where((g) => g.walletGroupPk == wallet.walletGroupFk)
      .firstOrNull;
  if (group == null || walletGroupKindPaysGmf(group.kind) == false) return;

  double taxable = debit;
  if (group.gmfExempt) {
    // Only what goes over the monthly exempt amount pays
    double limit = gmfExemptMonthlyUVT * colombiaYear(date.year).uvt;
    double after = await monthDebitsOfGroup(group, date);
    double before = after - debit;
    taxable = (after - limit).clamp(0, double.infinity) -
        (before - limit).clamp(0, double.infinity);
  }
  double tax = (taxable * gmfRate * 100).round() / 100;
  if (tax <= 0) return;

  await initializeGmfCategory();
  await database.createOrUpdateTransaction(
    insert: true,
    updateSharedEntry: false,
    Transaction(
      transactionPk: "-1",
      name: "gmf-transaction-name".tr(),
      amount: -tax,
      note: title,
      categoryFk: gmfCategoryPk,
      walletFk: wallet.walletPk,
      // A second later so it lists right next to what caused it
      dateCreated: date.add(Duration(seconds: 1)),
      income: false,
      paid: true,
      skipPaid: false,
    ),
  );
}

// Everything that left the account this month, the 4x1000 itself and moves
// between its own pockets left out
Future<double> monthDebitsOfGroup(WalletGroup group, DateTime date) async {
  List<TransactionWallet> wallets = await database.getAllWallets();
  Set<String> pockets = wallets
      .where((w) => w.walletGroupFk == group.walletGroupPk)
      .map((w) => w.walletPk)
      .toSet();
  if (pockets.isEmpty) return 0;
  DateTime start = DateTime(date.year, date.month);
  DateTime end = DateTime(date.year, date.month + 1);
  List<Transaction> debits = await (database.select(database.transactions)
        ..where((t) =>
            t.walletFk.isIn(pockets) &
            t.amount.isSmallerThanValue(0) &
            t.paid.equals(true) &
            t.categoryFk.equals(gmfCategoryPk).not() &
            t.dateCreated.isBiggerOrEqualValue(start) &
            t.dateCreated.isSmallerThanValue(end)))
      .get();
  double total = 0;
  for (Transaction t in debits) {
    if (t.categoryFk == "0" && await isMoveWithinGroup(t, pockets)) continue;
    total += t.amount.abs();
  }
  return total;
}

// A transfer is a pair of balance corrections that point at each other
Future<bool> isMoveWithinGroup(Transaction t, Set<String> pockets) async {
  Transaction? other;
  if (t.pairedTransactionFk != null) {
    try {
      other = await database.getTransactionFromPk(t.pairedTransactionFk!);
    } catch (e) {}
  }
  other ??= await (database.select(database.transactions)
        ..where((o) => o.pairedTransactionFk.equals(t.transactionPk)))
      .getSingleOrNull();
  return other != null && pockets.contains(other.walletFk);
}
