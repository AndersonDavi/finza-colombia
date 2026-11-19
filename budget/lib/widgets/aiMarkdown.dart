import 'package:flutter/material.dart';

// The little Markdown the AI answers use, drawn as text instead of showing the
// symbols: **bold**, *italic*, `code`, headings (#), bullet lists (- or *),
// numbered lists (1.) and tables (| a | b |). Anything else stays as it is
class AiMarkdownText extends StatelessWidget {
  const AiMarkdownText(this.text, {this.fontSize = 15, this.color, super.key});
  final String text;
  final double fontSize;
  final Color? color;

  static final RegExp _inline =
      RegExp(r"\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|\*(?!\s)([^*]+?)\*");
  static final RegExp _bullet = RegExp(r"^\s*[-*•]\s+");
  static final RegExp _numbered = RegExp(r"^\s*(\d+)[.)]\s+");
  static final RegExp _heading = RegExp(r"^\s*#{1,6}\s+");
  static final RegExp _tableSeparator = RegExp(r"^\s*\|?[\s:|-]+\|?\s*$");

  static List<String> _cells(String line) {
    String row = line.trim();
    if (row.startsWith("|")) row = row.substring(1);
    if (row.endsWith("|")) row = row.substring(0, row.length - 1);
    return row.split("|").map((c) => c.trim()).toList();
  }

  // A table scrolls sideways when it does not fit the bubble
  Widget _table(List<String> lines, TextStyle base, Color border) {
    List<List<String>> rows = [
      for (String line in lines)
        if (!_tableSeparator.hasMatch(line)) _cells(line)
    ];
    int columns = rows.fold(0, (n, r) => r.length > n ? r.length : n);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: IntrinsicColumnWidth(),
          border: TableBorder.all(color: border, width: 0.8),
          children: [
            for (int r = 0; r < rows.length; r++)
              TableRow(children: [
                for (int c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 8, vertical: 5),
                    child: Text.rich(TextSpan(
                      style: r == 0
                          ? base.copyWith(fontWeight: FontWeight.bold)
                          : base,
                      children:
                          _spans(c < rows[r].length ? rows[r][c] : "", base),
                    )),
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _spans(String line, TextStyle base) {
    List<InlineSpan> spans = [];
    int start = 0;
    for (RegExpMatch match in _inline.allMatches(line)) {
      if (match.start > start) {
        spans.add(TextSpan(text: line.substring(start, match.start)));
      }
      if (match.group(1) != null || match.group(2) != null) {
        spans.add(TextSpan(
            text: match.group(1) ?? match.group(2),
            style: TextStyle(fontWeight: FontWeight.bold)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(
            text: match.group(3),
            style: TextStyle(
                fontFamily: "monospace",
                backgroundColor:
                    (base.color ?? Colors.grey).withOpacity(0.12))));
      } else {
        spans.add(TextSpan(
            text: match.group(4),
            style: TextStyle(fontStyle: FontStyle.italic)));
      }
      start = match.end;
    }
    if (start < line.length) spans.add(TextSpan(text: line.substring(start)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    TextStyle base = TextStyle(
      fontSize: fontSize,
      height: 1.35,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );
    List<Widget> blocks = [];
    List<String> tableLines = [];
    void flushTable() {
      if (tableLines.isEmpty) return;
      blocks.add(_table(tableLines, base, base.color!.withOpacity(0.25)));
      tableLines = [];
    }

    for (String raw in text.trimRight().split("\n")) {
      String line = raw.trimRight();
      if (line.trimLeft().startsWith("|")) {
        tableLines.add(line);
        continue;
      }
      flushTable();
      if (line.trim().isEmpty) {
        blocks.add(SizedBox(height: fontSize * 0.5));
        continue;
      }
      Widget? marker;
      TextStyle style = base;
      if (_heading.hasMatch(line)) {
        line = line.replaceFirst(_heading, "");
        style = base.copyWith(
            fontWeight: FontWeight.bold, fontSize: fontSize + 1.5);
      } else if (_bullet.hasMatch(line)) {
        line = line.replaceFirst(_bullet, "");
        marker = Text("•  ", style: base.copyWith(fontWeight: FontWeight.bold));
      } else if (_numbered.hasMatch(line)) {
        String number = _numbered.firstMatch(line)!.group(1)!;
        line = line.replaceFirst(_numbered, "");
        marker = Text(number + ". ",
            style: base.copyWith(fontWeight: FontWeight.bold));
      }
      Widget body =
          Text.rich(TextSpan(style: style, children: _spans(line, base)));
      blocks.add(Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 2),
        child: marker == null
            ? body
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [marker, Expanded(child: body)],
                ),
              ),
      ));
    }
    flushTable();
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: blocks,
      ),
    );
  }
}
