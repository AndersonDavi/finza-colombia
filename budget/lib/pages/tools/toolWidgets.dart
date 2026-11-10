import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Inputs, rows and number parsing shared by the tool pages

// Reads amounts typed the Colombian way ("1.500.000", "1'500.000", "4,5")
// and also "1,500,000" or "12.5". Returns null when nothing usable was typed
double? parseToolNumber(String text) {
  String s = text.replaceAll(RegExp(r"[\s$%'’]"), "");
  if (s.isEmpty) return null;
  bool negative = s.startsWith("-");
  s = s.replaceAll("-", "");
  int lastDot = s.lastIndexOf(".");
  int lastComma = s.lastIndexOf(",");
  if (lastDot >= 0 && lastComma >= 0) {
    // Whichever comes last is the decimal mark
    if (lastComma > lastDot) {
      s = s.replaceAll(".", "").replaceAll(",", ".");
    } else {
      s = s.replaceAll(",", "");
    }
  } else if (lastComma >= 0) {
    // 1,500,000 groups thousands, 4,5 is a decimal
    s = ",".allMatches(s).length > 1
        ? s.replaceAll(",", "")
        : s.replaceAll(",", ".");
  } else if (lastDot >= 0) {
    // 1.500.000 and 1.500 group thousands, 12.5 and 0.125 are decimals
    bool groups = ".".allMatches(s).length > 1 ||
        (s.length - lastDot - 1 == 3 && s.substring(0, lastDot) != "0");
    if (groups) s = s.replaceAll(".", "");
  }
  double? value = double.tryParse(s);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return negative ? -value : value;
}

// A number ready to go back into a text field
String toolNumberToInput(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return removeTrailingZeroes(value.toStringAsFixed(4))
      .replaceAll(".", getDecimalSeparator());
}

String formatToolMoney(BuildContext context, double amount) {
  return convertToMoney(
    Provider.of<AllWallets>(context, listen: false),
    amount,
    currencyKey: "cop",
    decimals: 0,
  );
}

// A fraction (0.125) as a percent ("12,5%")
String formatToolPercent(double fraction, {int decimals = 2}) {
  return removeTrailingZeroes((fraction * 100).toStringAsFixed(decimals))
          .replaceAll(".", getDecimalSeparator()) +
      "%";
}

class ToolInputField extends StatelessWidget {
  const ToolInputField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.suffix,
    this.prefix,
    super.key,
  });
  final String label;
  final String? hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? suffix;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 5, bottom: 5),
            child: TextFont(
              text: label,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              maxLines: 3,
            ),
          ),
          TextInput(
            labelText: hint ?? label,
            controller: controller,
            onChanged: onChanged,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            autocorrect: false,
            prefix: prefix,
            suffix: suffix,
          ),
        ],
      ),
    );
  }
}

class ToolSectionTitle extends StatelessWidget {
  const ToolSectionTitle({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 5, top: 10, bottom: 8),
      child: TextFont(
        text: text,
        fontSize: 15,
        fontWeight: FontWeight.bold,
        maxLines: 3,
      ),
    );
  }
}

// One result line, with an optional explanation below
class ToolResultRow extends StatelessWidget {
  const ToolResultRow({
    required this.label,
    required this.value,
    this.description,
    this.highlight = false,
    super.key,
  });
  final String label;
  final String value;
  final String? description;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 8),
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadiusDirectional.circular(
            getPlatform() == PlatformOS.isIOS ? 10 : 15),
        color: highlight
            ? Theme.of(context).colorScheme.secondaryContainer
            : getColor(context, "lightDarkAccent"),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFont(
                  text: label,
                  fontSize: 16,
                  maxLines: 3,
                  fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              SizedBox(width: 10),
              TextFont(
                text: value,
                fontSize: highlight ? 19 : 17,
                fontWeight: FontWeight.bold,
                textAlign: TextAlign.end,
              ),
            ],
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: TextFont(
                text: description!,
                fontSize: 13,
                maxLines: 10,
                textColor: getColor(context, "textLight"),
              ),
            ),
        ],
      ),
    );
  }
}

class ToolNote extends StatelessWidget {
  const ToolNote({required this.text, this.color, super.key});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 5, end: 5, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, top: 1),
            child: Icon(
              appStateSettings["outlinedIcons"]
                  ? Icons.info_outlined
                  : Icons.info_outline_rounded,
              size: 17,
              color: color ?? getColor(context, "textLight"),
            ),
          ),
          Expanded(
            child: TextFont(
              text: text,
              fontSize: 14,
              maxLines: 15,
              textColor: color ?? getColor(context, "textLight"),
            ),
          ),
        ],
      ),
    );
  }
}
