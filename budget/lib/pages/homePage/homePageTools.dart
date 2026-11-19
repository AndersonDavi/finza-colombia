import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/tools/aiChatPage.dart';
import 'package:budget/pages/tools/incomeTaxPage.dart';
import 'package:budget/pages/tools/loanSimulatorPage.dart';
import 'package:budget/pages/tools/paymentsCenterPage.dart';
import 'package:budget/pages/tools/toolsPage.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/navBarIconsData.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Opens the Tools tab when it is in the bottom bar, the page otherwise
void openToolsPage(BuildContext context) {
  bool toolsInNavBar = [
    appStateSettings["customNavBarShortcut0"],
    appStateSettings["customNavBarShortcut1"],
    appStateSettings["customNavBarShortcut2"],
  ].contains("tools");
  if (toolsInNavBar && pageNavigationFrameworkKey.currentState != null) {
    pageNavigationFrameworkKey.currentState!
        .changePage(navBarIconsData["tools"]!.navigationIndexedStackIndex);
  } else {
    pushRoute(context, ToolsPage());
  }
}

// Big tiles on Home for the most used tools
class HomePageTools extends StatelessWidget {
  const HomePageTools({super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> tiles = [
      HomeToolTile(
        title: "tools-loan-simulator".tr(),
        icon: Icons.request_quote_rounded,
        page: LoanSimulatorPage(),
      ),
      HomeToolTile(
        title: "payments-center".tr(),
        icon: Icons.event_available_rounded,
        page: PaymentsCenterPage(),
      ),
      HomeToolTile(
        title: "ai-chat".tr(),
        icon: Icons.auto_awesome_rounded,
        page: AiChatPage(),
      ),
      if (livesInColombia())
        HomeToolTile(
          title: "tax-title".tr(),
          icon: Icons.account_balance_rounded,
          page: IncomeTaxPage(),
        ),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 13, end: 13, bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 5),
                  child: TextFont(
                    text: "tools".tr(),
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => openToolsPage(context),
                child: TextFont(
                  text: "home-tools-see-all".tr(),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  textColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          // Two per row; an odd last tile takes the whole row
          for (int i = 0; i < tiles.length; i += 2)
            Padding(
              padding: EdgeInsetsDirectional.only(
                  bottom: i + 2 < tiles.length ? 10 : 0),
              child: Row(
                children: [
                  Expanded(child: tiles[i]),
                  if (i + 1 < tiles.length) ...[
                    SizedBox(width: 10),
                    Expanded(child: tiles[i + 1]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class HomeToolTile extends StatelessWidget {
  const HomeToolTile({
    required this.title,
    required this.icon,
    required this.page,
    super.key,
  });
  final String title;
  final IconData icon;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadiusDirectional.circular(
            getPlatform() == PlatformOS.isIOS ? 10 : 15),
        boxShadow: boxShadowCheck(boxShadowGeneral(context)),
      ),
      child: Tappable(
        color: getColor(context, "lightDarkAccentHeavyLight"),
        borderRadius: getPlatform() == PlatformOS.isIOS ? 10 : 15,
        onTap: () => pushRoute(context, page),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 23, color: colors.onSecondaryContainer),
              ),
              SizedBox(width: 10),
              Expanded(
                child: TextFont(
                  text: title,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
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
