import 'package:budget/colors.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;

// Shared with the loan simulator

String rateTypeShortLabel(RateType type) => type.name.toUpperCase();

String rateTypeLabel(RateType type) => "tools-rate-${type.name}".tr();

// A fraction as a percent with the local decimal mark: 0.021 -> "2,10%"
String formatRatePercent(double fraction, {int decimals = 2}) {
  return (fraction * 100)
          .toStringAsFixed(decimals)
          .replaceAll(".", getDecimalSeparator()) +
      "%";
}

final List<TextInputFormatter> decimalInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

const TextInputType decimalKeyboard =
    TextInputType.numberWithOptions(decimal: true);

// Compares an effective annual rate with the usury and current banking rates
class UsuryWarning extends StatelessWidget {
  const UsuryWarning({required this.ea, super.key});
  final double ea;

  @override
  Widget build(BuildContext context) {
    double eaPercent = ea * 100;
    if (eaPercent > usuryRateEA) {
      return _RateNotice(
        color: getColor(context, "expenseAmount"),
        icon: Icons.warning_rounded,
        text: "tools-usury-exceeded".tr(namedArgs: {
          "rate": formatRatePercent(usuryRateEA / 100),
          "period": usuryRatePeriod,
        }),
      );
    }
    if (eaPercent > bankingCurrentRateEA) {
      return _RateNotice(
        color: getColor(context, "warningOrange"),
        icon: Icons.info_outline_rounded,
        text: "tools-above-banking-rate".tr(namedArgs: {
          "rate": formatRatePercent(bankingCurrentRateEA / 100),
          "usury": formatRatePercent(usuryRateEA / 100),
        }),
      );
    }
    return _RateNotice(
      color: getColor(context, "incomeAmount"),
      icon: Icons.check_circle_outline_rounded,
      text: "tools-usury-below".tr(namedArgs: {
        "rate": formatRatePercent(usuryRateEA / 100),
        "period": usuryRatePeriod,
      }),
    );
  }
}

class _RateNotice extends StatelessWidget {
  const _RateNotice(
      {required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 5),
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextFont(
                text: text,
                fontSize: 14,
                maxLines: 4,
                textColor: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RateCalculatorPage extends StatefulWidget {
  const RateCalculatorPage({super.key});

  @override
  State<RateCalculatorPage> createState() => _RateCalculatorPageState();
}

class _RateCalculatorPageState extends State<RateCalculatorPage> {
  String rateText = "";
  RateType rateType = RateType.ea;

  @override
  Widget build(BuildContext context) {
    double? rate = parseColombianNumber(rateText);
    RateEquivalents? equivalents;
    if (rate != null && isValidRate(rate / 100, rateType)) {
      equivalents = RateEquivalents.from(rate / 100, rateType);
    }

    return PageFramework(
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      title: "tools-rate-calculator".tr(),
      listWidgets: [
        TextInput(
          labelText: "tools-rate".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.percent_outlined
              : Icons.percent_rounded,
          suffix: "%",
          keyboardType: decimalKeyboard,
          inputFormatters: decimalInputFormatters,
          onChanged: (value) => setState(() => rateText = value),
        ),
        const SizedBox(height: 10),
        SelectChips<RateType>(
          items: RateType.values,
          wrapped: true,
          allowMultipleSelected: false,
          getSelected: (type) => type == rateType,
          onSelected: (type) => setState(() => rateType = type),
          getLabel: rateTypeLabel,
        ),
        SettingsHeader(title: "tools-equivalent-rates".tr()),
        if (equivalents == null)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 18, vertical: 10),
            child: TextFont(
              text: rateText.trim() == ""
                  ? "tools-enter-a-rate".tr()
                  : "tools-invalid-rate".tr(),
              fontSize: 15,
              maxLines: 3,
              textColor: getColor(context, "textLight"),
            ),
          )
        else ...[
          for (RateType type in RateType.values)
            _RateRow(
              short: rateTypeShortLabel(type),
              label: rateTypeLabel(type),
              value: formatRatePercent(equivalents.of(type), decimals: 4),
              selected: type == rateType,
            ),
          _RateRow(
            short: "ED",
            label: "tools-rate-daily".tr(),
            value: formatRatePercent(equivalents.daily, decimals: 4),
            selected: false,
          ),
          const SizedBox(height: 8),
          UsuryWarning(ea: equivalents.ea),
        ],
        SettingsHeader(title: "tools-ea-vs-nmv-title".tr()),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: TextFont(
            text: "tools-ea-vs-nmv-description".tr(),
            fontSize: 15,
            maxLines: 12,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _RateRow extends StatelessWidget {
  const _RateRow({
    required this.short,
    required this.label,
    required this.value,
    required this.selected,
  });
  final String short;
  final String label;
  final String value;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 3),
      child: Container(
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : getColor(context, "canvasContainer"),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: TextFont(
                text: short,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                textColor: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(
              child: TextFont(
                text: label,
                fontSize: 13,
                maxLines: 2,
                textColor: getColor(context, "textLight"),
              ),
            ),
            const SizedBox(width: 8),
            TextFont(
              text: value,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
      ),
    );
  }
}
