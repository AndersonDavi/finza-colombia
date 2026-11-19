import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// "How does this work?" guides: a help button for page headers that opens a
// few short steps, and a tip card shown once per screen until dismissed.
// Every guide lives in HelpGuides so the copy stays in one place

class HelpGuideAction {
  const HelpGuideAction({required this.label, required this.onTap, this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

class HelpGuide {
  const HelpGuide({
    required this.id,
    required this.title,
    required this.steps,
    this.tip,
    this.action,
  });
  // Stable id, remembered once the guide or its tip has been seen
  final String id;
  final String title;
  final List<String> steps;
  // One line for the first-time tip card; no card when null
  final String? tip;
  final HelpGuideAction? action;
}

const String helpGuidesSeenSetting = "helpGuidesSeen";

// Bumps when a guide is marked as seen, so open tip cards hide themselves
final ValueNotifier<int> helpGuidesSeenChanged = ValueNotifier(0);

bool helpGuideSeen(String id) {
  dynamic seen = appStateSettings[helpGuidesSeenSetting];
  return seen is List && seen.contains(id);
}

Future<void> markHelpGuideSeen(String id) async {
  if (helpGuideSeen(id)) return;
  dynamic seen = appStateSettings[helpGuidesSeenSetting];
  List<String> list = [
    if (seen is List) ...seen.map((e) => e.toString()),
    id,
  ];
  await updateSettings(helpGuidesSeenSetting, list, updateGlobalState: false);
  helpGuidesSeenChanged.value++;
}

Future openHelpGuide(BuildContext context, HelpGuide guide) {
  markHelpGuideSeen(guide.id);
  return openBottomSheet(
    context,
    PopupFramework(
      title: guide.title,
      child: HelpGuideSteps(guide: guide),
    ),
  );
}

class HelpGuideSteps extends StatelessWidget {
  const HelpGuideSteps({required this.guide, super.key});
  final HelpGuide guide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < guide.steps.length; i++)
          HelpStepRow(number: i + 1, text: guide.steps[i]),
        SizedBox(height: 8),
        if (guide.action != null) ...[
          Button(
            label: guide.action!.label,
            icon: guide.action!.icon,
            expandedLayout: true,
            onTap: guide.action!.onTap,
          ),
          SizedBox(height: 10),
        ],
        Button(
          label: "help-got-it".tr(),
          expandedLayout: true,
          color: guide.action != null
              ? getColor(context, "lightDarkAccentHeavy")
              : null,
          textColor:
              guide.action != null ? getColor(context, "black") : null,
          onTap: () => popRoute(context),
        ),
      ],
    );
  }
}

// A numbered step: a round badge and one or two short sentences
class HelpStepRow extends StatelessWidget {
  const HelpStepRow(
      {required this.number, required this.text, this.fontSize = 16, super.key});
  final int number;
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: TextFont(
              text: number.toString(),
              fontSize: 15,
              fontWeight: FontWeight.bold,
              textColor: colors.onSecondaryContainer,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: TextFont(text: text, fontSize: fontSize, maxLines: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// Header action that opens the guide
class HelpGuideButton extends StatelessWidget {
  const HelpGuideButton({required this.guide, super.key});
  final HelpGuide guide;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsetsDirectional.all(15),
      tooltip: "help-how-it-works".tr(),
      onPressed: () => openHelpGuide(context, guide),
      icon: Icon(appStateSettings["outlinedIcons"]
          ? Icons.help_outline_outlined
          : Icons.help_outline_rounded),
    );
  }
}

// Card shown the first time a screen opens, until "Got it" or the guide
// is opened
class HelpFirstTimeTip extends StatelessWidget {
  const HelpFirstTimeTip({
    required this.guide,
    this.padding =
        const EdgeInsetsDirectional.symmetric(horizontal: 13, vertical: 5),
    super.key,
  });
  final HelpGuide guide;
  final EdgeInsetsDirectional padding;

  @override
  Widget build(BuildContext context) {
    if (guide.tip == null) return SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: helpGuidesSeenChanged,
      builder: (context, _, __) {
        bool show = helpGuideSeen(guide.id) == false;
        return AnimatedSize(
          duration: Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: show
              ? Padding(padding: padding, child: _tipCard(context))
              : SizedBox(width: double.infinity),
        );
      },
    );
  }

  Widget _tipCard(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.only(
          start: 15, end: 8, top: 13, bottom: 4),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadiusDirectional.circular(
            getPlatform() == PlatformOS.isIOS ? 10 : 15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                appStateSettings["outlinedIcons"]
                    ? Icons.lightbulb_outlined
                    : Icons.lightbulb_rounded,
                size: 20,
                color: colors.onSecondaryContainer,
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextFont(
                  text: guide.tip!,
                  fontSize: 15,
                  maxLines: 6,
                  textColor: colors.onSecondaryContainer,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => markHelpGuideSeen(guide.id),
                child: TextFont(
                  text: "help-got-it".tr(),
                  fontSize: 14,
                  textColor: colors.onSecondaryContainer,
                ),
              ),
              TextButton(
                onPressed: () => openHelpGuide(context, guide),
                child: TextFont(
                  text: "help-show-guide".tr(),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  textColor: colors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const String geminiKeyUrl = "https://aistudio.google.com/apikey";

// The guides themselves, one per screen
class HelpGuides {
  static List<String> _steps(String id, int count) =>
      [for (int i = 1; i <= count; i++) "help-$id-step-$i".tr()];

  static HelpGuide _guide(String id, int steps,
          {bool tip = false, HelpGuideAction? action}) =>
      HelpGuide(
        id: id,
        title: "help-$id-title".tr(),
        steps: _steps(id, steps),
        tip: tip ? "help-$id-tip".tr() : null,
        action: action,
      );

  static HelpGuide home() => _guide("home", 4, tip: true);
  static HelpGuide addTransaction() => _guide("add-transaction", 4);
  static HelpGuide transactions() => _guide("transactions", 4);
  static HelpGuide budgets() => _guide("budgets", 4, tip: true);
  static HelpGuide pockets() => _guide("pockets", 4, tip: true);
  static HelpGuide pocketEditor() => _guide("pocket", 4);
  static HelpGuide more() => _guide("more", 4);
  static HelpGuide settings() => _guide("settings", 3);
  static HelpGuide tools() => _guide("tools", 4, tip: true);
  static HelpGuide paymentsCenter() => _guide("payments", 4, tip: true);
  static HelpGuide accountEditor() => _guide("account", 4);
  static HelpGuide incomeTax() => _guide("income-tax", 4);
  static HelpGuide aiChat() => _guide(
        "ai-chat",
        4,
        action: HelpGuideAction(
          label: "help-ai-chat-get-key".tr(),
          icon: Icons.open_in_new_rounded,
          onTap: () => openUrl(geminiKeyUrl),
        ),
      );
}
