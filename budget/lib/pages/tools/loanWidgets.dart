import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/animatedExpanded.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Pieces shared by the loan simulator tabs

double loanBoxRadius() => getPlatform() == PlatformOS.isIOS ? 10 : 15;

// A short help text that opens under an input: "¿Cómo lo lleno?"
class LoanGuide extends StatefulWidget {
  const LoanGuide({required this.text, this.title, super.key});
  final String text;
  final String? title;

  @override
  State<LoanGuide> createState() => _LoanGuideState();
}

class _LoanGuideState extends State<LoanGuide> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    Color accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Tappable(
              borderRadius: 10,
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 5, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      appStateSettings["outlinedIcons"]
                          ? Icons.help_outline_outlined
                          : Icons.help_outline_rounded,
                      size: 17,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: TextFont(
                        text: widget.title ?? "loan-guide-how-to-fill".tr(),
                        fontSize: 14,
                        maxLines: 2,
                        fontWeight: FontWeight.bold,
                        textColor: accent,
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(Icons.expand_more_rounded,
                          size: 18, color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedExpanded(
            expand: open,
            child: Container(
              margin: const EdgeInsetsDirectional.only(top: 4),
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: getColor(context, "lightDarkAccent"),
                borderRadius: BorderRadius.circular(loanBoxRadius()),
              ),
              child: TextFont(
                text: widget.text,
                fontSize: 14,
                maxLines: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Segmented tabs with a sliding highlight
class LoanTabs extends StatelessWidget {
  const LoanTabs({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      padding: const EdgeInsetsDirectional.all(4),
      decoration: BoxDecoration(
        color: getColor(context, "lightDarkAccent"),
        borderRadius: BorderRadius.circular(loanBoxRadius() + 4),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        double width = constraints.maxWidth / labels.length;
        return Stack(
          children: [
            AnimatedPositionedDirectional(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              start: width * selected,
              top: 0,
              bottom: 0,
              width: width,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(loanBoxRadius()),
                ),
              ),
            ),
            Row(
              children: [
                for (int i = 0; i < labels.length; i++)
                  Expanded(
                    child: Tappable(
                      borderRadius: loanBoxRadius(),
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                icons[i],
                                size: 18,
                                color: i == selected
                                    ? colors.onSecondaryContainer
                                    : getColor(context, "textLight"),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: TextFont(
                                  text: labels[i],
                                  fontSize: 14,
                                  maxLines: 1,
                                  autoSizeText: true,
                                  minFontSize: 10,
                                  fontWeight: i == selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  textColor: i == selected
                                      ? colors.onSecondaryContainer
                                      : getColor(context, "textLight"),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

// A colored box with an icon, used for verdicts and the disclaimer
class LoanNotice extends StatelessWidget {
  const LoanNotice({
    required this.color,
    required this.icon,
    required this.text,
    this.title,
    super.key,
  });
  final Color color;
  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 10),
      padding:
          const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        border: Border.all(color: color.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(loanBoxRadius()),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  TextFont(
                    text: title!,
                    fontSize: 16,
                    maxLines: 3,
                    fontWeight: FontWeight.bold,
                    textColor: color,
                  ),
                TextFont(
                  text: text,
                  fontSize: 14,
                  maxLines: 10,
                  textColor: title == null ? color : null,
                  fontWeight:
                      title == null ? FontWeight.bold : FontWeight.normal,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// "Es una simulación con datos proyectados..."
class LoanDisclaimer extends StatelessWidget {
  const LoanDisclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return LoanNotice(
      color: getColor(context, "warningOrange"),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.info_outlined
          : Icons.info_outline_rounded,
      text: "loan-disclaimer".tr(),
    );
  }
}

// A row that opens a picker: label on the left, value on the right
class LoanPickerRow extends StatelessWidget {
  const LoanPickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Tappable(
        borderRadius: loanBoxRadius(),
        color: getColor(context, "lightDarkAccent"),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: getColor(context, "textLight")),
              const SizedBox(width: 12),
              Expanded(
                child: TextFont(
                  text: label,
                  fontSize: 15,
                  maxLines: 2,
                  textColor: getColor(context, "textLight"),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: TextFont(
                  text: value,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// A filled action button that spans the width
class LoanActionButton extends StatelessWidget {
  const LoanActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.secondary = false,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    Color background =
        secondary ? getColor(context, "lightDarkAccent") : colors.primary;
    Color foreground = secondary ? colors.primary : colors.onPrimary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Tappable(
        borderRadius: loanBoxRadius(),
        color: background,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: TextFont(
                  text: label,
                  fontSize: 15,
                  maxLines: 2,
                  fontWeight: FontWeight.bold,
                  textColor: foreground,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
