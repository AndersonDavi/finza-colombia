import 'dart:async';
import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/pages/walletDetailsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/widgets/walletEntry.dart';
import 'package:budget/widgets/transactionEntry/transferIcon.dart';
import 'package:home_widget/home_widget.dart';
import 'package:provider/provider.dart';
import 'package:budget/pages/addWalletPage.dart';
import "package:budget/struct/throttler.dart";

class AndroidOnly extends StatelessWidget {
  const AndroidOnly({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (getPlatform(ignoreEmulation: true) != PlatformOS.isAndroid)
      return SizedBox.shrink();
    return child;
  }
}

class CheckWidgetLaunch extends StatefulWidget {
  const CheckWidgetLaunch({super.key});

  @override
  State<CheckWidgetLaunch> createState() => _CheckWidgetLaunchState();
}

Throttler widgetActionThrottler =
    Throttler(duration: Duration(milliseconds: 350));

class _CheckWidgetLaunchState extends State<CheckWidgetLaunch> {
  @override
  void initState() {
    super.initState();
    HomeWidget.setAppGroupId('WIDGET_GROUP_ID');
    Future.delayed(Duration(milliseconds: 50), () {
      _checkForWidgetLaunch();
    });
    HomeWidget.widgetClicked.listen(_launchedFromWidget);
  }

  void _checkForWidgetLaunch() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_launchedFromWidget);
  }

  // For some reason, older Android versions open an entirely new app instance... weird!
  // has this been fixed with: android:launchMode="singleInstance" ?
  void _launchedFromWidget(Uri? uri) async {
    // Only perform one widget action per launch/continue of the app
    if (!widgetActionThrottler.canProceed()) return;

    String widgetPayload = (uri ?? "").toString();
    if (widgetPayload == "addTransactionWidget") {
      // Add a delay so the keyboard can focus
      Future.delayed(Duration(milliseconds: 50), () {
        pushRoute(
          context,
          AddTransactionPage(
            routesToPopAfterDelete: RoutesToPopAfterDelete.None,
          ),
        );
      });
    } else if (widgetPayload == "transferTransactionWidget") {
      // This fixes an issue on older versions of Android where the route would popup twice
      // We can detect when this is going to happen if the Provider is not yet loaded, so just pop
      // the route when this is called so the first time routing does not persist (i.e. we end with one route)
      if (Provider.of<AllWallets>(context, listen: false)
              .indexedByPk[appStateSettings["selectedWalletPk"]] ==
          null) popAllRoutes(context);

      openBottomSheet(
        context,
        fullSnap: true,
        TransferBalancePopup(
          allowEditWallet: true,
          wallet: Provider.of<AllWallets>(context, listen: false)
              .indexedByPk[appStateSettings["selectedWalletPk"]],
          showAllEditDetails: true,
        ),
      );
    } else if (widgetPayload == "netWorthLaunchWidget") {
      pushRoute(
        context,
        WalletDetailsPage(
          wallet: null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink();
  }
}

class RenderHomePageWidgets extends StatefulWidget {
  const RenderHomePageWidgets({super.key});

  @override
  State<RenderHomePageWidgets> createState() => RenderHomePageWidgetsState();
}

Future updateWidgetColorsAndText(BuildContext context) async {
  if (getPlatform(ignoreEmulation: true) != PlatformOS.isAndroid) return;
  await Future.delayed(Duration(milliseconds: 500), () async {
    double widgetBackgroundOpacity =
        (double.tryParse((appStateSettings["widgetOpacity"] ?? 1).toString()) ??
                1)
            .clamp(0, 1);
    ThemeData widgetTheme = appStateSettings["widgetTheme"] == "light"
        ? getLightTheme()
        : appStateSettings["widgetTheme"] == "dark"
            ? getDarkTheme()
            : Theme.of(context);

    await HomeWidget.saveWidgetData<String>('netWorthTitle', "net-worth".tr());
    await HomeWidget.saveWidgetData<String>(
      'widgetColorBackground',
      colorToHex(widgetTheme.colorScheme.secondaryContainer),
    );
    await HomeWidget.saveWidgetData<String>(
      'widgetAlpha',
      widgetTheme.colorScheme.secondaryContainer
          .withOpacity(widgetBackgroundOpacity)
          .alpha
          .toString(),
    );
    await HomeWidget.saveWidgetData<String>(
      'widgetColorPrimary',
      colorToHex(widgetTheme.colorScheme.primary),
    );
    await HomeWidget.saveWidgetData<String>(
      'widgetColorText',
      colorToHex(widgetTheme.colorScheme.onSecondaryContainer),
    );
    await HomeWidget.updateWidget(
      name: 'NetWorthWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'NetWorthPlusWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'PlusWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'TransferWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'PocketsWidgetProvider',
    );
  });

  return;
}

class RenderHomePageWidgetsState extends State<RenderHomePageWidgets> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {
      updateWidgetColorsAndText(context);
    });
  }

  void refreshState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [netWorthWidget(context), PocketsWidgetData()],
    );
  }

  Widget netWorthWidget(BuildContext context) {
    return StreamBuilder<List<TransactionWallet>>(
      stream: database.getAllPinnedWallets(HomePageWidgetDisplay.NetWorth).$1,
      builder: (context, snapshot) {
        List<String>? walletPks =
            (snapshot.data ?? []).map((item) => item.walletPk).toList();
        if (walletPks.length <= 0 ||
            appStateSettings["netWorthAllWallets"] == true) walletPks = null;
        return Container(
          child: StreamBuilder<TotalWithCount?>(
            stream: database.watchTotalWithCountOfWallet(
              isIncome: null,
              allWallets: Provider.of<AllWallets>(context),
              followCustomPeriodCycle: true,
              cycleSettingsExtension: "NetWorth",
              searchFilters: SearchFilters(walletPks: walletPks ?? []),
            ),
            builder: (context, snapshot) {
              Future.delayed(Duration.zero, () async {
                int totalCount = snapshot.data?.count ?? 0;
                String netWorthTransactionsNumber = totalCount.toString() +
                    " " +
                    (totalCount == 1
                        ? "transaction".tr().toLowerCase()
                        : "transactions".tr().toLowerCase());
                double totalSpent = snapshot.data?.total ?? 0;
                String netWorthAmount = convertToMoney(
                  Provider.of<AllWallets>(context, listen: false),
                  totalSpent,
                );
                await HomeWidget.saveWidgetData<String>(
                  'netWorthAmount',
                  netWorthAmount,
                );
                await HomeWidget.saveWidgetData<String>(
                  'netWorthTransactionsNumber',
                  netWorthTransactionsNumber,
                );
                await HomeWidget.updateWidget(
                  name: 'NetWorthWidgetProvider',
                );
                await HomeWidget.updateWidget(
                  name: 'NetWorthPlusWidgetProvider',
                );
              });

              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

// Pockets widget: free money of all the groups and the pockets chosen in the
// widget settings (the free pockets when none is chosen)
class PocketsWidgetData extends StatelessWidget {
  const PocketsWidgetData({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WalletWithDetails>>(
      stream: database.watchAllWalletsWithDetails(),
      builder: (context, snapshot) {
        if (snapshot.data == null) return SizedBox.shrink();
        AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
        double inPrimary(WalletWithDetails w) =>
            (w.totalSpent ?? 0) *
            amountRatioToPrimaryCurrencyGivenPk(allWallets, w.wallet.walletPk);
        double freeTotal = snapshot.data!
            .where((w) => freeWalletPksCache.contains(w.wallet.walletPk))
            .fold(0.0, (sum, w) => sum + inPrimary(w));
        List<String> chosen =
            List<String>.from(appStateSettings["widgetPocketPks"] ?? []);
        List<WalletWithDetails> shown = snapshot.data!
            .where((w) => chosen.isEmpty
                ? freeWalletPksCache.contains(w.wallet.walletPk)
                : chosen.contains(w.wallet.walletPk))
            .take(6)
            .toList();
        String lines = [
          for (WalletWithDetails w in shown)
            getWalletStringName(allWallets, w.wallet) +
                "  " +
                convertToMoney(allWallets, w.totalSpent ?? 0,
                    currencyKey: w.wallet.currency)
        ].join("\n");
        ThemeData widgetTheme = appStateSettings["widgetTheme"] == "light"
            ? getLightTheme()
            : appStateSettings["widgetTheme"] == "dark"
                ? getDarkTheme()
                : Theme.of(context);
        Widget card = PocketsWidgetCard(
          theme: widgetTheme,
          title: "free-money".tr(),
          total: convertToMoney(allWallets, freeTotal),
          rows: [
            for (WalletWithDetails w in shown)
              PocketsWidgetRow(
                // A free pocket goes by its account's name ("Libre · Nequi"
                // is just Nequi here)
                name: freeWalletPksCache.contains(w.wallet.walletPk)
                    ? walletGroupNamesCache[w.wallet.walletGroupFk] ??
                        getWalletStringName(allWallets, w.wallet)
                    : getWalletStringName(allWallets, w.wallet),
                amount: convertToMoney(allWallets, w.totalSpent ?? 0,
                    currencyKey: w.wallet.currency),
                colour: w.wallet.colour,
                icon: walletIconOf(w.wallet),
              ),
          ],
          opacity: (double.tryParse(
                      (appStateSettings["widgetOpacity"] ?? 1).toString()) ??
                  1)
              .clamp(0, 1)
              .toDouble(),
        );
        Future.delayed(Duration.zero, () async {
          await HomeWidget.saveWidgetData<String>(
              'pocketsTitle', "free-money".tr());
          await HomeWidget.saveWidgetData<String>(
              'pocketsAmount', convertToMoney(allWallets, freeTotal));
          await HomeWidget.saveWidgetData<String>('pocketsLines', lines);
          // The widget shows this picture; the texts above are the fallback
          try {
            await HomeWidget.renderFlutterWidget(
              card,
              key: 'pocketsImage',
              logicalSize: Size(PocketsWidgetCard.width,
                  PocketsWidgetCard.heightFor(shown.length)),
            );
          } catch (e) {
            print("Could not draw the pockets widget: " + e.toString());
          }
          await HomeWidget.updateWidget(name: 'PocketsWidgetProvider');
        });
        return SizedBox.shrink();
      },
    );
  }
}

class PocketsWidgetRow {
  PocketsWidgetRow({
    required this.name,
    required this.amount,
    required this.colour,
    required this.icon,
  });
  final String name;
  final String amount;
  final String? colour;
  final IconData icon;
}

// The pockets widget drawn like the free money card of the app, saved as a
// picture the home screen widget shows
class PocketsWidgetCard extends StatelessWidget {
  const PocketsWidgetCard({
    required this.theme,
    required this.title,
    required this.total,
    required this.rows,
    required this.opacity,
    super.key,
  });
  final ThemeData theme;
  final String title;
  final String total;
  final List<PocketsWidgetRow> rows;
  final double opacity;

  static const double width = 340;
  static double heightFor(int rows) => 96 + rows * 34.0;

  @override
  Widget build(BuildContext context) {
    Color background = theme.colorScheme.secondaryContainer;
    Color text = theme.colorScheme.onSecondaryContainer;
    TextStyle style(double size, {bool bold = false, double alpha = 1}) =>
        TextStyle(
          fontFamily: theme.textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback: theme.textTheme.bodyMedium?.fontFamilyFallback,
          fontSize: size,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          color: text.withOpacity(alpha),
          decoration: TextDecoration.none,
        );
    return MediaQuery(
      data: MediaQueryData(),
      child: Theme(
        data: theme,
        child: Builder(builder: (context) {
          return Container(
            width: width,
            height: heightFor(rows.length),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            decoration: BoxDecoration(
              color: background.withOpacity(opacity),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.savings_rounded,
                        size: 18, color: text.withOpacity(0.8)),
                    SizedBox(width: 6),
                    Text(title, style: style(15, bold: true, alpha: 0.8)),
                  ],
                ),
                SizedBox(height: 2),
                Text(total, style: style(28, bold: true)),
                SizedBox(height: 8),
                for (PocketsWidgetRow row in rows)
                  SizedBox(
                    height: 34,
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: pickedColor(context, row.colour),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(row.icon,
                              size: 15,
                              color: pickedColor(context, row.colour)
                                          .computeLuminance() >
                                      0.5
                                  ? Colors.black.withOpacity(0.75)
                                  : Colors.white),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style(15),
                          ),
                        ),
                        Text(row.amount, style: style(15, bold: true)),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
