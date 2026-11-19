import 'dart:convert';
import 'dart:math';

import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/aiActions.dart';
import 'package:budget/struct/aiChanges.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:drift/drift.dart';

// Read-only questions the chat AI can ask the app, so it is not limited to the
// last movements sent with each message: search the whole history with
// filters, or get totals grouped by category, month or pocket. They only read,
// so they run right away; the result goes back to the model in the next turn

const String aiQueryFence = "finza-query";
const int maxAiQueriesPerAnswer = 3;
// Rounds of query and answer before the chat gives the model a final turn
const int maxAiQueryRounds = 3;
const int maxSearchResults = 100;

const String aiQueryInstructions = """

Reading more data: the user data only has the last movements. To look further
back, filter or add things up, ask the app with a block; it runs at once
(nothing changes) and sends you the result in the next message:
```finza-query
{"query": "search", "text": "uber", "from": "2025-01-01", "to": "2025-12-31", "category": "Transporte", "pocket": "Nequi / Libre", "income": false, "min_amount": 10000, "max_amount": 50000, "limit": 50}
```
```finza-query
{"query": "totals", "from": "2025-01-01", "to": "2025-12-31", "group_by": "category", "income": false}
```
group_by is category, month, pocket or category_month. Every field but
"query" is optional. When you need data, answer with only the query blocks
(no other text), then answer the user once the result arrives. Prefer totals
over long searches for whole periods. At most $maxAiQueriesPerAnswer blocks.""";

final RegExp _queryBlock = RegExp(r"```" + aiQueryFence + r"\s*([\s\S]*?)```");

List<Map<String, dynamic>> extractAiQueries(String text) {
  List<Map<String, dynamic>> queries = [];
  for (RegExpMatch match in _queryBlock.allMatches(text)) {
    try {
      dynamic decoded = jsonDecode(match.group(1)!.trim());
      for (dynamic item in decoded is List ? decoded : [decoded]) {
        if (item is Map && item["query"] != null) {
          queries.add(Map<String, dynamic>.from(item));
        }
      }
    } catch (e) {}
  }
  return queries.take(maxAiQueriesPerAnswer).toList();
}

String stripAiQueries(String text) {
  String out = text.replaceAll(_queryBlock, "");
  int open = out.indexOf("```" + aiQueryFence);
  if (open != -1) out = out.substring(0, open);
  return out.trim();
}

// Filters shared by both queries, read from what the model sent
class AiQueryFilter {
  AiQueryFilter(this.json, this.categories, this.pockets);
  final Map<String, dynamic> json;
  final List<TransactionCategory> categories;
  final List<AiPocketOption> pockets;

  DateTime? get from => parseAiDate(json["from"]);
  DateTime? get to {
    DateTime? day = parseAiDate(json["to"]);
    return day == null ? null : DateTime(day.year, day.month, day.day + 1);
  }

  bool? get income =>
      json.containsKey("income") ? parseAiBool(json["income"]) : null;

  // Problems with names, said back to the model so it can fix them
  final List<String> notes = [];

  bool matches(Transaction t, Map<String, TransactionCategory> byPk) {
    if (from != null && t.dateCreated.isBefore(from!)) return false;
    if (to != null && !t.dateCreated.isBefore(to!)) return false;
    if (income != null && t.income != income) return false;
    double amount = t.amount.abs();
    double? min = parseColombianAmount(json["min_amount"]);
    double? max = parseColombianAmount(json["max_amount"]);
    if (min != null && amount < min) return false;
    if (max != null && amount > max) return false;
    String text = json["text"]?.toString().trim() ?? "";
    if (text.isNotEmpty) {
      String haystack = normalizeName(t.name + " " + t.note);
      if (!haystack.contains(normalizeName(text))) return false;
    }
    return true;
  }

  // Category and pocket filters, resolved once
  String? categoryPk;
  String? walletPk;

  void resolve() {
    String category = json["category"]?.toString().trim() ?? "";
    if (category.isNotEmpty) {
      TransactionCategory? found = exactCategory(category, categories);
      if (found == null) {
        notes.add("No category named \"$category\"; ignored that filter.");
      } else {
        categoryPk = found.categoryPk;
      }
    }
    String pocket = json["pocket"]?.toString().trim() ?? "";
    if (pocket.isNotEmpty) {
      AiPocketOption? found = exactPocket(pocket, pockets);
      if (found == null) {
        notes.add("No pocket named \"$pocket\"; ignored that filter.");
      } else {
        walletPk = found.wallet.walletPk;
      }
    }
  }
}

Future<String> runAiQueries(
    List<Map<String, dynamic>> queries, AllWallets allWallets) async {
  List<TransactionCategory> categories = await database.getAllCategories();
  Map<String, TransactionCategory> byPk = {
    for (TransactionCategory c in categories) c.categoryPk: c
  };
  List<AiPocketOption> pockets = await aiPocketOptions(allWallets);
  Map<String, String> pocketLabel = {
    for (AiPocketOption p in pockets) p.wallet.walletPk: p.label
  };
  StringBuffer out = StringBuffer("Results from the app:\n");
  for (int i = 0; i < queries.length; i++) {
    Map<String, dynamic> json = queries[i];
    AiQueryFilter filter = AiQueryFilter(json, categories, pockets)..resolve();
    var select = database.select(database.transactions)
      ..where((t) => t.paid.equals(true));
    if (filter.categoryPk != null) {
      select.where((t) => t.categoryFk.equals(filter.categoryPk!));
    }
    if (filter.walletPk != null) {
      select.where((t) => t.walletFk.equals(filter.walletPk!));
    }
    select.orderBy([(t) => OrderingTerm.desc(t.dateCreated)]);
    List<Transaction> rows =
        (await select.get()).where((t) => filter.matches(t, byPk)).toList();

    out.writeln("\nQuery ${i + 1} (${jsonEncode(json)}):");
    for (String note in filter.notes) {
      out.writeln("Note: " + note);
    }
    String money(double amount) => convertToMoney(allWallets, amount);

    if (json["query"] == "totals") {
      // Transfers between pockets are not income nor spending
      List<Transaction> counted =
          rows.where((t) => t.categoryFk != "0").toList();
      String groupBy = json["group_by"]?.toString() ?? "category";
      String keyOf(Transaction t) {
        String month = t.dateCreated.toIso8601String().substring(0, 7);
        String category = byPk[t.categoryFk]?.name ?? "?";
        return switch (groupBy) {
          "month" => month,
          "pocket" => pocketLabel[t.walletFk] ?? "?",
          "category_month" => month + " | " + category,
          _ => category,
        };
      }

      Map<String, List<double>> groups = {};
      for (Transaction t in counted) {
        String key = (t.income ? "income" : "expense") + " | " + keyOf(t);
        List<double> g = groups.putIfAbsent(key, () => [0, 0]);
        g[0] += t.amount;
        g[1] += 1;
      }
      List<MapEntry<String, List<double>>> sorted = groups.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      double income =
          counted.where((t) => t.income).fold(0.0, (s, t) => s + t.amount);
      double expense =
          counted.where((t) => !t.income).fold(0.0, (s, t) => s + t.amount);
      out.writeln("${counted.length} movements. Income ${money(income)}, "
          "spending ${money(expense)} (primary currency, transfers left out).");
      out.writeln("type | group | total | movements");
      for (MapEntry<String, List<double>> entry in sorted.take(300)) {
        out.writeln(
            "${entry.key} | ${money(entry.value[0])} | ${entry.value[1].round()}");
      }
    } else {
      int limit = min(maxSearchResults,
          max(1, int.tryParse(json["limit"]?.toString() ?? "") ?? 50));
      double total = rows.fold(0.0, (s, t) => s + t.amount);
      out.writeln("${rows.length} movements found, adding up ${money(total)}"
          "${rows.length > limit ? "; showing the newest $limit" : ""}.");
      out.writeln("#id | date | title | category | pocket | amount");
      for (Transaction t in rows.take(limit)) {
        out.writeln([
          "#" + shortTransactionId(t.transactionPk),
          t.dateCreated.toIso8601String().substring(0, 10),
          t.name,
          byPk[t.categoryFk]?.name ?? "",
          pocketLabel[t.walletFk] ?? "",
          convertToMoney(allWallets, t.amount,
              currencyKey: allWallets.indexedByPk[t.walletFk]?.currency),
        ].join(" | "));
      }
    }
  }
  return out.toString();
}
