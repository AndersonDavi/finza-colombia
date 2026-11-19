import 'dart:math';

import 'package:budget/colors.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

// Large choices and fields for the onboarding: easy to hit with a thumb or a
// mouse, with a clear selected state. Every onboarding step builds on these

const double onboardingTileRadius = 18;

// A tappable card: avatar, title, optional subtitle and a check when picked.
// Vertical tiles stack the avatar over the title, for grids
class OnboardingTile extends StatelessWidget {
  const OnboardingTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.selected = false,
    this.showCheck = true,
    this.vertical = false,
    super.key,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final bool showCheck;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    Widget check = AnimatedScale(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      scale: selected ? 1 : 0,
      child: Container(
        width: 26,
        height: 26,
        decoration:
            BoxDecoration(color: colors.primary, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 19, color: colors.onPrimary),
      ),
    );
    Widget texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFont(
          text: title,
          fontSize: 17,
          fontWeight: FontWeight.bold,
          maxLines: 3,
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 3),
            child: TextFont(
              text: subtitle!,
              fontSize: 14,
              maxLines: 3,
              textColor: getColor(context, "black").withOpacity(0.6),
            ),
          ),
      ],
    );
    Widget content = vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leading != null) leading!,
                  Spacer(),
                  if (showCheck) check,
                ],
              ),
              SizedBox(height: 10),
              texts,
            ],
          )
        : Row(
            children: [
              if (leading != null) ...[leading!, SizedBox(width: 14)],
              Expanded(child: texts),
              if (showCheck) ...[SizedBox(width: 10), check],
            ],
          );
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(onboardingTileRadius + 2.5),
          border: Border.all(
            color: selected ? colors.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Tappable(
          onTap: onTap,
          borderRadius: onboardingTileRadius,
          color: selected
              ? colors.secondaryContainer
              : getColor(context, "canvasContainer"),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: vertical ? 100 : 68),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14, vertical: 14),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

// Round avatar with a colour and the initials of a name, or an icon. No
// logos: only letters and colours
class OnboardingAvatar extends StatelessWidget {
  const OnboardingAvatar({
    required this.color,
    this.name,
    this.icon,
    this.size = 44,
    super.key,
  });
  final Color color;
  final String? name;
  final IconData? icon;
  final double size;

  // "Banco de Bogotá" -> "BB", "Nequi" -> "N"
  static String initials(String name) {
    const Set<String> skip = {"de", "del", "la", "las", "el", "los", "y"};
    List<String> words = name
        .trim()
        .split(RegExp(r"\s+"))
        .where((w) => w.isNotEmpty && skip.contains(w.toLowerCase()) == false)
        .toList();
    if (words.isEmpty) return "?";
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words[0].characters.first + words[1].characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    Color foreground =
        color.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, color: foreground, size: size * 0.55)
          : TextFont(
              text: initials(name ?? ""),
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
              textColor: foreground,
            ),
    );
  }
}

// Tiles in rows of equal height: two columns on phones, three when there
// is room
class OnboardingTileGrid extends StatelessWidget {
  const OnboardingTileGrid({
    required this.children,
    this.minTileWidth = 140,
    this.maxColumns = 3,
    this.spacing = 10,
    super.key,
  });
  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      int columns = max(
          1,
          min(maxColumns,
              ((constraints.maxWidth + spacing) / (minTileWidth + spacing))
                  .floor()));
      List<Widget> rows = [];
      for (int start = 0; start < children.length; start += columns) {
        List<Widget> cells = [];
        for (int i = 0; i < columns; i++) {
          if (i > 0) cells.add(SizedBox(width: spacing));
          int index = start + i;
          cells.add(Expanded(
            child: index < children.length ? children[index] : SizedBox(),
          ));
        }
        if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ));
      }
      return Column(children: rows);
    });
  }
}

// The Colombian flag drawn with its three stripes, so it shows the same on
// every device
class ColombiaFlag extends StatelessWidget {
  const ColombiaFlag({this.width = 44, super.key});
  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: width,
        height: width * 2 / 3,
        child: Column(
          children: [
            Expanded(flex: 2, child: Container(color: Color(0xFFFCD116))),
            Expanded(child: Container(color: Color(0xFF003893))),
            Expanded(child: Container(color: Color(0xFFCE1126))),
          ],
        ),
      ),
    );
  }
}

// A labelled text field. Required fields show "*"; when [error] is set the
// field gets a red border and the message under it
class OnboardingField extends StatelessWidget {
  const OnboardingField({
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.required = false,
    this.focusNode,
    this.keyboardType,
    this.prefix,
    this.onChanged,
    super.key,
  });
  final String label;
  final String? hint;
  final String? error;
  final bool required;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final String? prefix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    Color errorColor = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
            child: Row(
              children: [
                Flexible(
                  child: TextFont(
                    text: label,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    maxLines: 3,
                  ),
                ),
                if (required)
                  TextFont(
                    text: " *",
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    textColor: errorColor,
                  ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: error != null ? errorColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: TextInput(
              labelText: hint ?? label,
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              padding: EdgeInsetsDirectional.zero,
              keyboardType: keyboardType,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              prefix: prefix,
              fontSize: 18,
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 6),
              child: TextFont(
                text: error!,
                fontSize: 14,
                maxLines: 3,
                textColor: errorColor,
              ),
            ),
        ],
      ),
    );
  }
}

// A red line under a group of choices, shown when none was picked
class OnboardingErrorText extends StatelessWidget {
  const OnboardingErrorText({required this.text, super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8, start: 4),
      child: TextFont(
        text: text,
        fontSize: 15,
        maxLines: 3,
        textColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
