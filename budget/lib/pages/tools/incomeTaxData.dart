import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/pages/tools/incomeTaxMath.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:drift/drift.dart';

// Tag the purchases backed by an electronic invoice are marked with
const List<String> electronicInvoiceTagNames = [
  "factura electrónica",
  "factura electronica",
];

class IncomeTaxData {
  const IncomeTaxData({
    required this.filing,
    required this.electronicInvoicePurchases,
  });
  final FilingValues filing;
  final double electronicInvoicePurchases;
}

// What the app knows of a taxable year, in the primary currency. Transfers,
// balance corrections and loans are left out of income and spending.
extension IncomeTaxQueries on FinanceDatabase {
  Future<IncomeTaxData> getIncomeTaxData(
      int year, AllWallets allWallets) async {
    DateTime start = DateTime(year);
    DateTime end = DateTime(year + 1);
    List<Transaction> ofYear = await (select(transactions)
          ..where((t) =>
              t.paid.equals(true) &
              t.categoryFk.equals("0").not() &
              t.pairedTransactionFk.isNull() &
              t.objectiveLoanFk.isNull() &
              (t.type.isNull() |
                  t.type.isNotInValues([
                    TransactionSpecialType.credit,
                    TransactionSpecialType.debt
                  ])) &
              t.dateCreated.isBiggerOrEqualValue(start) &
              t.dateCreated.isSmallerThanValue(end)))
        .get();

    Map<String, WalletGroup> groups = {
      for (WalletGroup g in await getAllWalletGroups()) g.walletGroupPk: g
    };
    WalletGroup? groupOf(String walletPk) =>
        groups[allWallets.indexedByPk[walletPk]?.walletGroupFk];

    Set<String> invoiced = await _electronicInvoiceTransactionPks();

    double income = 0;
    double purchases = 0;
    double creditCard = 0;
    double deposits = 0;
    double invoicePurchases = 0;
    for (Transaction t in ofYear) {
      double amount = t.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
      WalletGroup? group = groupOf(t.walletFk);
      // Compared by name, the credit card kind may not exist in this schema
      String? kind = group?.kind.name;
      if (t.income) {
        income += amount;
        if (group != null && kind != "cash" && kind != "creditCard") {
          deposits += amount;
        }
      } else {
        purchases += amount;
        if (kind == "creditCard") creditCard += amount;
        if (invoiced.contains(t.transactionPk)) invoicePurchases += amount;
      }
    }

    return IncomeTaxData(
      filing: FilingValues(
        grossIncome: income,
        purchases: purchases,
        creditCard: creditCard,
        deposits: deposits,
        grossEquity: await _grossEquityAt(end, allWallets),
      ),
      electronicInvoicePurchases: invoicePurchases,
    );
  }

  // Patrimonio bruto: what each account held before the given date, every
  // transaction counted. Accounts in debt (credit cards) add nothing.
  Future<double> _grossEquityAt(DateTime before, AllWallets allWallets) async {
    final total = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([transactions.walletFk, total])
      ..where(transactions.paid.equals(true) &
          transactions.dateCreated.isSmallerThanValue(before))
      ..groupBy([transactions.walletFk]);
    double equity = 0;
    for (TypedResult row in await query.get()) {
      String? walletPk = row.read(transactions.walletFk);
      double balance = row.read(total) ?? 0;
      if (walletPk == null || balance <= 0) continue;
      equity +=
          balance * amountRatioToPrimaryCurrencyGivenPk(allWallets, walletPk);
    }
    return equity;
  }

  // Older databases may not have the tag tables
  Future<Set<String>> _electronicInvoiceTransactionPks() async {
    try {
      List<String> tagPks = (await select(tags).get())
          .where((tag) =>
              electronicInvoiceTagNames.contains(tag.name.trim().toLowerCase()))
          .map((tag) => tag.tagPk)
          .toList();
      if (tagPks.isEmpty) return {};
      return (await (select(transactionToTagLinks)
                ..where((l) => l.tagPk.isIn(tagPks)))
              .get())
          .map((l) => l.transactionPk)
          .whereType<String>()
          .toSet();
    } catch (e) {
      print("No tags for the electronic invoice: " + e.toString());
      return {};
    }
  }
}
