import 'package:budget/colors.dart';
import 'package:budget/pages/tools/incomeTaxMath.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Pieces of the income tax page, on top of the shared tool widgets

class IncomeTaxCard extends StatelessWidget {
  const IncomeTaxCard({required this.child, this.color, super.key});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: color ?? getColor(context, "standardContainerColor"),
        borderRadius: BorderRadiusDirectional.circular(15),
      ),
      child: child,
    );
  }
}

// Educational estimate warning, at the top and next to the result
class IncomeTaxDisclaimer extends StatelessWidget {
  const IncomeTaxDisclaimer({this.extra, super.key});
  final String? extra;

  @override
  Widget build(BuildContext context) {
    Color warning = getColor(context, "warningOrange");
    return IncomeTaxCard(
      color: warning.withOpacity(0.15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: warning),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                  text: "tax-disclaimer".tr(),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  maxLines: 10,
                ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 4),
                    child: TextFont(
                      text: extra!,
                      fontSize: 13,
                      maxLines: 10,
                      textColor: getColor(context, "textLight"),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class IncomeTaxStepHeader extends StatelessWidget {
  const IncomeTaxStepHeader(
      {required this.number, required this.title, super.key});
  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, top: 22, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary,
              shape: BoxShape.circle,
            ),
            child: TextFont(
              text: number.toString(),
              fontSize: 16,
              fontWeight: FontWeight.bold,
              textColor: colors.onPrimary,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: TextFont(
              text: title,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// "¿Qué es esto?" link that unfolds a short explanation
class IncomeTaxHelp extends StatefulWidget {
  const IncomeTaxHelp({required this.text, super.key});
  final String text;

  @override
  State<IncomeTaxHelp> createState() => _IncomeTaxHelpState();
}

class _IncomeTaxHelpState extends State<IncomeTaxHelp> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    Color primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tappable(
          onTap: () => setState(() => open = !open),
          borderRadius: 10,
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 5, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  open ? Icons.expand_less_rounded : Icons.help_outline_rounded,
                  size: 17,
                  color: primary,
                ),
                SizedBox(width: 5),
                TextFont(
                  text: "tax-what-is-this".tr(),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  textColor: primary,
                ),
              ],
            ),
          ),
        ),
        AnimatedExpanded(
          expand: open,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsetsDirectional.only(top: 4, bottom: 4),
            padding: const EdgeInsetsDirectional.all(10),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              borderRadius: BorderRadiusDirectional.circular(10),
            ),
            child: TextFont(
              text: widget.text,
              fontSize: 13.5,
              maxLines: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// An amount in pesos with its help and an optional line below
class IncomeTaxAmountField extends StatelessWidget {
  const IncomeTaxAmountField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.help,
    this.below,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String help;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToolInputField(
            label: label,
            hint: "0",
            prefix: "\$ ",
            controller: controller,
            onChanged: onChanged,
          ),
          if (below != null)
            Padding(
              padding:
                  const EdgeInsetsDirectional.only(start: 5, end: 5, bottom: 2),
              child: below!,
            ),
          IncomeTaxHelp(text: help),
        ],
      ),
    );
  }
}

// One filing condition: the amount, how far it is from its limit and help
class IncomeTaxFilingField extends StatelessWidget {
  const IncomeTaxFilingField({
    required this.label,
    required this.help,
    required this.controller,
    required this.check,
    required this.onChanged,
    super.key,
  });
  final String label;
  final String help;
  final TextEditingController controller;
  final FilingCheck check;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Color color = check.obliges
        ? getColor(context, "expenseAmount")
        : getColor(context, "incomeAmount");
    return IncomeTaxCard(
      child: IncomeTaxAmountField(
        label: label,
        help: help,
        controller: controller,
        onChanged: onChanged,
        below: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              check.obliges ? Icons.error_rounded : Icons.check_circle_rounded,
              color: color,
              size: 18,
            ),
            SizedBox(width: 6),
            Expanded(
              child: TextFont(
                text: "tax-threshold-line".tr(namedArgs: {
                  "uvt": formatTaxNumber(check.valueUVT, decimals: 1),
                  "limitUvt": formatTaxNumber(check.thresholdUVT),
                  "limit": formatToolMoney(context, check.threshold),
                }),
                fontSize: 13,
                maxLines: 3,
                textColor: getColor(context, "textLight"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IncomeTaxBreakdownRow extends StatelessWidget {
  const IncomeTaxBreakdownRow(this.label, this.value,
      {this.bold = false, this.note, super.key});
  final String label;
  final String value;
  final bool bold;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                  text: label,
                  fontSize: 14,
                  maxLines: 3,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
                if (note != null)
                  TextFont(
                    text: note!,
                    fontSize: 12,
                    maxLines: 3,
                    textColor: getColor(context, "textLight"),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10),
          TextFont(
            text: value,
            fontSize: 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ],
      ),
    );
  }
}

class IncomeTaxBreakdownDivider extends StatelessWidget {
  const IncomeTaxBreakdownDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 14, color: getColor(context, "dividerColor"));
  }
}

// The art. 241 brackets as equal segments, with a marker on the taxable
// income and the effective rate below
class IncomeTaxBracketBar extends StatelessWidget {
  const IncomeTaxBracketBar({required this.result, super.key});
  final IncomeTaxResult result;

  // Where the marker goes, 0 to 1. Each bracket takes the same width
  double markerPosition() {
    int count = incomeTaxBrackets.length;
    int index = result.bracketIndex;
    IncomeTaxBracket bracket = incomeTaxBrackets[index];
    double span = index + 1 < count
        ? incomeTaxBrackets[index + 1].fromUVT - bracket.fromUVT
        : bracket.fromUVT;
    double within =
        span <= 0 ? 0 : ((result.taxableUVT - bracket.fromUVT) / span);
    return ((index + within.clamp(0.0, 1.0)) / count).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    int current = result.bracketIndex;
    double? toNext = result.uvtToNextBracket;
    double position = markerPosition();

    List<Widget> segments = [];
    for (int i = 0; i < incomeTaxBrackets.length; i++) {
      bool selected = i == current;
      Color background = selected
          ? colors.primary
          : i < current
              ? colors.primary.withOpacity(0.3)
              : getColor(context, "lightDarkAccent");
      segments.add(Expanded(
        child: AnimatedContainer(
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
          height: 34,
          margin: const EdgeInsetsDirectional.symmetric(horizontal: 1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadiusDirectional.circular(8),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
              child: TextFont(
                text: formatToolPercent(incomeTaxBrackets[i].rate, decimals: 0),
                fontSize: 13,
                fontWeight: FontWeight.bold,
                textColor: selected ? colors.onPrimary : null,
              ),
            ),
          ),
        ),
      ));
    }

    return IncomeTaxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFont(
            text: "tax-bracket-title".tr(),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            maxLines: 2,
          ),
          SizedBox(height: 12),
          Row(children: segments),
          TweenAnimationBuilder<double>(
            tween: Tween(end: position),
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
            builder: (context, value, _) => Align(
              alignment: AlignmentDirectional(value * 2 - 1, 0),
              child: Icon(
                Icons.arrow_drop_up_rounded,
                size: 32,
                color: colors.primary,
              ),
            ),
          ),
          TextFont(
            text: "tax-bracket-line".tr(namedArgs: {
              "rate": formatToolPercent(result.bracket.rate, decimals: 0),
              "from": formatTaxNumber(result.bracket.fromUVT),
              "uvt": formatTaxNumber(result.taxableUVT, decimals: 1),
            }),
            fontSize: 14,
            maxLines: 4,
          ),
          SizedBox(height: 4),
          TextFont(
            text: "tax-effective-rate".tr(namedArgs: {
              "rate": formatToolPercent(result.effectiveRate),
            }),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            maxLines: 3,
          ),
          if (toNext != null) ...[
            SizedBox(height: 4),
            TextFont(
              text: "tax-next-bracket".tr(namedArgs: {
                "uvt": formatTaxNumber(toNext, decimals: 1),
                "amount": formatToolMoney(context, toNext * result.uvt),
                "rate": formatToolPercent(incomeTaxBrackets[current + 1].rate,
                    decimals: 0),
              }),
              fontSize: 13,
              maxLines: 4,
              textColor: getColor(context, "textLight"),
            ),
          ],
        ],
      ),
    );
  }
}
