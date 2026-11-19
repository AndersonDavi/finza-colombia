import 'package:budget/struct/aiChanges.dart';
import 'package:budget/struct/aiQueries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("proposed changes", () {
    String answer = """Listo, te propongo esto:
```finza-change
{"action": "create_pocket", "account": "Nequi", "name": "Viaje"}
```
Y también:
```finza-change
[{"action": "rename_pocket", "pocket": "Nequi / Libre", "new_name": "Diario"},
 {"action": "hack_the_bank"}]
```""";

    test("reads every block and skips unknown actions", () {
      List<Map<String, dynamic>> changes = extractAiChanges(answer);
      expect(changes.length, 2);
      expect(changes[0]["action"], "create_pocket");
      expect(changes[1]["new_name"], "Diario");
    });

    test("bad JSON is ignored", () {
      expect(extractAiChanges("```finza-change\n{not json}\n```"), isEmpty);
    });

    test("caps the number of changes", () {
      String many = List.filled(
              8, '```finza-change\n{"action": "delete_transaction", "id": "#a"}\n```')
          .join("\n");
      expect(extractAiChanges(many).length, maxAiChangesPerAnswer);
    });

    test("the bubble hides the blocks, even one still being written", () {
      expect(stripAiChanges(answer), "Listo, te propongo esto:\n\nY también:");
      expect(stripAiChanges('Ok\n```finza-change\n{"action": "cre'), "Ok");
    });

    test("action names", () {
      expect(aiChangeKindOf("DELETE_POCKET"), AiChangeKind.deletePocket);
      expect(aiChangeKindOf("drop_table"), isNull);
    });

    test("status note for the model", () {
      expect(aiChangeStatusNote({}), "");
      expect(aiChangeStatusNote({0: "done", 1: "cancelled"}),
          "\n\n[Change 1: confirmed and applied; Change 2: cancelled by the user]");
    });
  });

  group("data queries", () {
    test("reads query blocks and strips them", () {
      String reply = '```finza-query\n{"query": "totals", "group_by": "month"}\n```';
      expect(extractAiQueries(reply).single["group_by"], "month");
      expect(stripAiQueries(reply), "");
      expect(stripAiQueries("Un momento\n```finza-query\n{\"que"), "Un momento");
    });

    test("caps the number of queries", () {
      String many =
          List.filled(5, '```finza-query\n{"query": "search"}\n```').join();
      expect(extractAiQueries(many).length, maxAiQueriesPerAnswer);
    });
  });

  test("short ids", () {
    expect(shortTransactionId("1234567890abcdef"), "12345678");
    expect(shortTransactionId("12"), "12");
  });
}
