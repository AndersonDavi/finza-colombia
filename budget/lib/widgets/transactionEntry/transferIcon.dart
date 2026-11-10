import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/pocketIcons.dart';
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Both sides of every balance transfer, each one pointing at the other, so a
// row knows where its money came from or went without waiting on a query
ValueNotifier<Map<String, Transaction>> transferPartners = ValueNotifier({});

void listenToTransferPartners(FinanceDatabase database) {
  final paired = database.transactions;
  (database.select(paired)
        ..where((t) =>
            t.categoryFk.equals("0") &
            (t.pairedTransactionFk.isNotNull() |
                t.transactionPk.isInQuery(database.selectOnly(paired)
                  ..addColumns([paired.pairedTransactionFk])
                  ..where(paired.pairedTransactionFk.isNotNull())))))
      .watch()
      .listen((transactions) {
    Map<String, Transaction> byPk = {
      for (Transaction t in transactions) t.transactionPk: t
    };
    Map<String, Transaction> partners = {};
    for (Transaction t in transactions) {
      Transaction? other = byPk[t.pairedTransactionFk];
      if (other == null) continue;
      partners[t.transactionPk] = other;
      partners[other.transactionPk] = t;
    }
    transferPartners.value = partners;
  });
}

// The transaction the money left from, then the one it arrived to
(Transaction, Transaction)? transferSides(Transaction transaction) {
  Transaction? partner = transferPartners.value[transaction.transactionPk];
  if (partner == null) return null;
  return transaction.amount <= 0 ? (transaction, partner) : (partner, transaction);
}

// "Libre · Bancolombia → Nequi" instead of the "<account> Transfer Out" the
// app writes as the title, which also stays in the language it was made in
String? transferTitle(AllWallets allWallets, Transaction transaction) {
  (Transaction, Transaction)? sides = transferSides(transaction);
  if (sides == null) return null;
  TransactionWallet? from = allWallets.indexedByPk[sides.$1.walletFk];
  TransactionWallet? to = allWallets.indexedByPk[sides.$2.walletFk];
  if (from == null || to == null) return null;
  String name = transaction.name.trim();
  bool generated = name == "" ||
      name.endsWith(" Transfer In") ||
      name.endsWith(" Transfer Out") ||
      name.endsWith(" " + "transfer-in".tr()) ||
      name.endsWith(" " + "transfer-out".tr());
  if (!generated) return null;
  return getWalletStringName(allWallets, from) +
      " → " +
      getWalletStringName(allWallets, to);
}

IconData walletIconOf(TransactionWallet wallet) {
  return pocketIconOf(wallet) ??
      (freeWalletPksCache.contains(wallet.walletPk)
          ? Icons.savings_rounded
          : Icons.account_balance_wallet_rounded);
}

// A circle split down the middle: the pocket the money left on the left, the
// one it went to on the right, each with its color and icon
class TransferSplitIcon extends StatelessWidget {
  const TransferSplitIcon({
    required this.transaction,
    required this.fallback,
    this.onTap,
    super.key,
  });
  final Transaction transaction;
  final Widget fallback;
  final VoidCallback? onTap;

  static const double diameter = 47;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, Transaction>>(
      valueListenable: transferPartners,
      builder: (context, _, __) {
        AllWallets allWallets = Provider.of<AllWallets>(context);
        (Transaction, Transaction)? sides = transferSides(transaction);
        TransactionWallet? from =
            allWallets.indexedByPk[sides?.$1.walletFk];
        TransactionWallet? to = allWallets.indexedByPk[sides?.$2.walletFk];
        if (sides == null || from == null || to == null) return fallback;
        Widget half(TransactionWallet wallet, AlignmentDirectional alignment) {
          Color color = pickedColor(context, wallet.colour);
          return Expanded(
            child: Container(
              color: color.withOpacity(0.85),
              alignment: alignment,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
              child: Icon(
                walletIconOf(wallet),
                size: 15,
                color: color.computeLuminance() > 0.5
                    ? Colors.black.withOpacity(0.75)
                    : Colors.white,
              ),
            ),
          );
        }

        return Tooltip(
          message: getWalletStringName(allWallets, from) +
              " → " +
              getWalletStringName(allWallets, to),
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: ClipOval(
                child: Row(
                  children: [
                    half(from, AlignmentDirectional.centerEnd),
                    Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    half(to, AlignmentDirectional.centerStart),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
