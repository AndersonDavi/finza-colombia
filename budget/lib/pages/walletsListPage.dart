import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/distributePage.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/homePage/homePageNetWorth.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/fab.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/walletEntry.dart';
import 'package:budget/widgets/walletGroups.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:flutter/material.dart';

// Every account with its balance. Tapping one opens its details.
class WalletsListPage extends StatefulWidget {
  const WalletsListPage({super.key});

  @override
  State<WalletsListPage> createState() => WalletsListPageState();
}

class WalletsListPageState extends State<WalletsListPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      key: pageState,
      title: "accounts".tr(),
      backButton: false,
      actions: [
        IconButton(
          tooltip: "distribute".tr(),
          onPressed: () => pushRoute(context, DistributePage()),
          icon: Icon(appStateSettings["outlinedIcons"]
              ? Icons.call_split_outlined
              : Icons.call_split_rounded),
        ),
      ],
      dragDownToDismiss: true,
      floatingActionButton: AnimateFABDelayed(
        fab: AddFAB(
          tooltip: "add-account".tr(),
          openPage: AddWalletPage(
            routesToPopAfterDelete: RoutesToPopAfterDelete.None,
          ),
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 700,
            horizontalPadding: 0,
            child: HomePageNetWorth(),
          ),
        ),
        StreamBuilder<List<WalletWithDetails>>(
          stream: database.watchAllWalletsWithDetails(),
          builder: (context, snapshot) {
            List<WalletWithDetails> wallets = snapshot.data ?? [];
            return SliverToBoxAdapter(
              child: CenteredPageContent(
                maxWidth: 700,
                horizontalPadding: 13,
                child: ClipRRect(
                  borderRadius: BorderRadiusDirectional.circular(15),
                  child: Container(
                    color: getColor(context, "lightDarkAccentHeavyLight"),
                    padding: EdgeInsetsDirectional.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        // Same as the home list: tap selects, tap again opens
                        GroupedWalletRows(
                          showOrganizer: true,
                          wallets: wallets,
                          rowBuilder: (wallet) => WalletEntryRow(
                            walletWithDetails: wallet,
                            selected: wallet.wallet.walletPk ==
                                appStateSettings["selectedWalletPk"],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}
