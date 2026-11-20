import 'package:budget/colors.dart';
import 'package:budget/database/generatePreviewData.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/languageMap.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/currencyPicker.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/helpGuide.dart';
import 'package:budget/widgets/moreIcons.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/onboardingAccounts.dart';
import 'package:budget/widgets/onboardingFixedItems.dart';
import 'package:budget/widgets/onboardingWidgets.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:budget/functions.dart';
import 'package:budget/database/initializeDefaultDatabase.dart';

class OnBoardingPage extends StatelessWidget {
  const OnBoardingPage({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);

  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        resizeToAvoidBottomInset: false,
        body: OnBoardingPageBody(
            popNavigationWhenDone: popNavigationWhenDone,
            showPreviewDemoButton: showPreviewDemoButton));
  }
}

class OnBoardingPageBody extends StatefulWidget {
  const OnBoardingPageBody({
    Key? key,
    this.popNavigationWhenDone = false,
    this.showPreviewDemoButton = true,
  }) : super(key: key);
  final bool popNavigationWhenDone;
  final bool showPreviewDemoButton;

  @override
  State<OnBoardingPageBody> createState() => OnBoardingPageBodyState();
}

// Steps of the onboarding, in order
enum OnboardingStep { welcome, accounts, explain, fixedItems, finish }

// Steps that can be skipped without picking anything. The accounts step is
// not here: a transaction needs an account and a pocket to live in, so at
// least one account must be picked
const Set<OnboardingStep> optionalOnboardingSteps = {
  OnboardingStep.fixedItems,
};

// Width of the onboarding column on wide screens
const double onboardingMaxWidth = 520;

class OnBoardingPageBodyState extends State<OnBoardingPageBody> {
  final PageController controller = PageController();
  int currentPage = 0;

  // Shown when Next is pressed before picking a country
  bool countryMissing = false;
  // Shown when Next is pressed before picking at least one account
  bool accountsMissing = false;
  // The language moved to Spanish when Colombia was picked
  bool switchedToSpanish = false;
  // Kept here: the pages of the PageView are rebuilt when swiped back to
  final ValueNotifier<List<OnboardingFixedItem>> fixedItems = ValueNotifier([]);

  final Image imageLanding1 = Image(
    image: AssetImage("assets/landing/Graph.png"),
  );
  final Image imageLanding3 = Image(
    image: AssetImage("assets/landing/PigBank.png"),
  );

  @override
  void didChangeDependencies() {
    precacheImage(imageLanding1.image, context);
    precacheImage(imageLanding3.image, context);
    super.didChangeDependencies();
  }

  nextNavigation({bool generatePreview = false}) async {
    if (generatePreview) {
      // The demo is made of Colombian accounts in pesos
      if (appStateSettings["country"] != countryColombia) {
        await pickCountry(countryColombia);
      }
      if (!mounted) return;
      openLoadingPopup(context);
      await generatePreviewData();
      popRoute(context);
    }
    if (widget.popNavigationWhenDone) {
      popRoute(context);
    } else {
      updateSettings("hasOnboarded", true,
          pagesNeedingRefresh: [], updateGlobalState: true);
    }
  }

  FocusNode _focusNode = FocusNode();
  late FocusAttachment _focusAttachment;

  @override
  void initState() {
    super.initState();
    _focusAttachment = _focusNode.attach(context, onKeyEvent: (node, event) {
      if (event.logicalKey.keyLabel == "Go Back" ||
          event.logicalKey == LogicalKeyboardKey.escape) {
        if (widget.popNavigationWhenDone) nextNavigation();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nextOnBoardPage();
      } else if (event.runtimeType == KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        previousOnBoardPage();
      }
      return KeyEventResult.handled;
    });
    _focusNode.requestFocus();

    Future.delayed(Duration.zero, () async {
      // Functions to run after entire UI loaded - landing page
      // Run here too, so user has a wallet when creating first budget
      // We need to run this after the UI is loaded - after translations are loaded
      await initializeDefaultDatabase();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    controller.dispose();
    fixedItems.dispose();
    super.dispose();
  }

  int get numPages => OnboardingStep.values.length;
  OnboardingStep get step => OnboardingStep.values[currentPage];

  void goToPage(int page) {
    controller.animateToPage(
      page,
      duration: Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> nextOnBoardPage() async {
    if (step == OnboardingStep.welcome && appStateSettings["country"] == null) {
      setState(() => countryMissing = true);
      return;
    }
    if (step == OnboardingStep.accounts) {
      bool hasAccount = (await database.getAllWalletGroups()).isNotEmpty;
      if (!mounted) return;
      if (hasAccount == false) {
        setState(() => accountsMissing = true);
        return;
      }
      if (accountsMissing) setState(() => accountsMissing = false);
    }
    if (currentPage + 1 >= numPages) {
      nextNavigation();
    } else {
      goToPage(currentPage + 1);
    }
  }

  void previousOnBoardPage() {
    if (currentPage > 0) goToPage(currentPage - 1);
  }

  Future<void> pickCountry(String country) async {
    await setCountry(country, setCurrency: true);
    if (!mounted) return;
    if (country == countryColombia) {
      if (await useSpanishForColombia(context)) switchedToSpanish = true;
    } else if (switchedToSpanish) {
      await resetLanguageToSystem(context);
      initializeLocalizedMonthNames();
      switchedToSpanish = false;
    }
    if (mounted) setState(() => countryMissing = false);
  }

  Widget onboardingTitle(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: TextFont(
        text: text,
        fontWeight: FontWeight.bold,
        textAlign: TextAlign.center,
        fontSize: 26,
        maxLines: 5,
      ),
    );
  }

  Widget onboardingText(String text, {bool faint = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: TextFont(
        text: text,
        textAlign: TextAlign.center,
        fontSize: faint ? 15 : 18,
        maxLines: 8,
        textColor: faint ? getColor(context, "black").withOpacity(0.6) : null,
      ),
    );
  }

  Widget landingImage(Image image) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 160, maxWidth: 240),
        child: image,
      ),
    );
  }

  Widget currencyButton() {
    return StreamBuilder<AllWallets>(
      stream: database.watchAllWalletsIndexed(),
      builder: (context, snapshot) {
        TransactionWallet? primaryWallet =
            snapshot.data?.indexedByPk[appStateSettings["selectedWalletPk"]];
        if (primaryWallet == null) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: 12),
          child: LowKeyButton(
            onTap: () {
              openBottomSheet(
                context,
                SizedBox.shrink(),
                customBuilder: (context2, scrollController, sheetState) {
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: PopupFramework(
                          title: "select-primary-currency".tr(),
                          subtitle: "select-primary-currency-description".tr(),
                          child: SizedBox.shrink(),
                          bottomSafeAreaExtraPadding: false,
                        ),
                      ),
                      CurrencyPicker(
                        showExchangeRateInfoNotice: false,
                        onSelected: (selectedCurrency) {
                          popRoute(context);
                          database.createOrUpdateWallet(primaryWallet.copyWith(
                              currency: Value(selectedCurrency)));
                        },
                        initialCurrency: primaryWallet.currency,
                        unSelectedColor: appStateSettings["materialYou"]
                            ? null
                            : getColor(context, "canvasContainer"),
                      ),
                    ],
                  );
                },
              );
            },
            text: "change-currency".tr(),
          ),
        );
      },
    );
  }

  Future<void> signInWithGoogle() async {
    loadingIndeterminateKey.currentState?.setVisibility(true);
    openLoadingPopupTryCatch(
      () async {
        // On web the first sign-in does not sync with signInAndSync, so the
        // steps run here one by one
        await signInGoogle(
          context: context,
          waitForCompletion: false,
          next: () {},
        );
        if (appStateSettings["username"] == "" && googleUser != null) {
          updateSettings("username", googleUser?.displayName ?? "",
              pagesNeedingRefresh: [0], updateGlobalState: false);
        }
        // Set this to true so cloud functions run
        entireAppLoaded = true;
        await runAllCloudFunctions(
          context,
          forceSignIn: true,
        );
        nextNavigation();
        loadingIndeterminateKey.currentState?.setVisibility(false);
      },
      onError: (e) {
        print("Error signing in: " + e.toString());
        loadingIndeterminateKey.currentState?.setVisibility(false);
      },
    );
  }

  Widget buildStep(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        String? country = appStateSettings["country"];
        return OnBoardPage(
          widgets: [
            landingImage(imageLanding1),
            SizedBox(height: 14),
            onboardingTitle(
                "onboarding-title-1".tr(namedArgs: {"app": globalAppName})),
            onboardingText("onboarding-info-1".tr()),
            SizedBox(height: 20),
            TextFont(
              text: "where-do-you-live".tr(),
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
              fontSize: 20,
              maxLines: 3,
            ),
            SizedBox(height: 12),
            OnboardingTile(
              leading: ColombiaFlag(),
              title: "country-CO".tr(),
              subtitle: "country-CO-description".tr(),
              selected: country == countryColombia,
              onTap: () => pickCountry(countryColombia),
            ),
            SizedBox(height: 10),
            OnboardingTile(
              leading: OnboardingAvatar(
                color: Theme.of(context).colorScheme.primary,
                icon: Icons.public_rounded,
              ),
              title: "country-other".tr(),
              subtitle: "country-other-description".tr(),
              selected: country == countryOther,
              onTap: () => pickCountry(countryOther),
            ),
            if (countryMissing)
              OnboardingErrorText(text: "onb-country-required".tr()),
            if (country == countryOther) currencyButton(),
            if (widget.showPreviewDemoButton)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 12),
                child: PreviewDemoButton(nextNavigation: nextNavigation),
              ),
          ],
        );
      case OnboardingStep.accounts:
        return OnBoardPage(
          widgets: [
            onboardingTitle("onboarding-accounts-title".tr()),
            onboardingText("onboarding-accounts-description".tr()),
            SizedBox(height: 16),
            OnboardingAccountsStep(
              onChanged: () {
                if (accountsMissing) setState(() => accountsMissing = false);
              },
            ),
            if (accountsMissing)
              OnboardingErrorText(text: "onb-accounts-required".tr()),
          ],
        );
      case OnboardingStep.explain:
        return OnBoardPage(
          widgets: [
            onboardingTitle("onb-explain-title".tr()),
            SizedBox(height: 8),
            HelpStepRow(
                number: 1, text: "onb-explain-pockets".tr(), fontSize: 18),
            PocketsExample(),
            SizedBox(height: 22),
            HelpStepRow(
                number: 2, text: "onb-explain-categories".tr(), fontSize: 18),
            CategoriesExample(limit: 8),
            SizedBox(height: 16),
            onboardingText("onb-explain-later".tr(), faint: true),
          ],
        );
      case OnboardingStep.fixedItems:
        ColorScheme colors = Theme.of(context).colorScheme;
        return OnBoardPage(
          widgets: [
            onboardingTitle("onb-fixed-title".tr()),
            onboardingText("onb-fixed-description".tr()),
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(onboardingTileRadius),
              ),
              child: Row(
                children: [
                  Icon(
                    appStateSettings["outlinedIcons"]
                        ? Icons.notifications_outlined
                        : Icons.notifications_rounded,
                    color: colors.onSecondaryContainer,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFont(
                      text: "onb-fixed-reminder-note".tr(),
                      fontSize: 15,
                      maxLines: 4,
                      textColor: colors.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            OnboardingFixedItemsStep(items: fixedItems),
          ],
        );
      case OnboardingStep.finish:
        bool offersGoogle = getPlatform() != PlatformOS.isIOS;
        return OnBoardPage(
          widgets: [
            landingImage(imageLanding3),
            SizedBox(height: 14),
            onboardingTitle(
                "onboarding-title-3".tr(namedArgs: {"app": globalAppName})),
            onboardingText("onb-final-text".tr()),
            if (offersGoogle) ...[
              SizedBox(height: 24),
              Center(
                child: SettingsContainerOutlined(
                  onTap: signInWithGoogle,
                  title: "sign-in-with-google".tr(),
                  icon: MoreIcons.google,
                  isExpanded: false,
                ),
              ),
              SizedBox(height: 10),
              onboardingText("onb-final-google-optional".tr(), faint: true),
            ],
          ],
        );
    }
  }

  Widget header() {
    bool optional = optionalOnboardingSteps.contains(step);
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 8, 6),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: "onb-step-of".tr(namedArgs: {
                      "current": (currentPage + 1).toString(),
                      "total": numPages.toString(),
                    }),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    textColor: getColor(context, "black").withOpacity(0.7),
                  ),
                ),
                AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  opacity: optional ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: optional == false,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: Size(88, 48),
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 16),
                      ),
                      onPressed: () => goToPage(currentPage + 1),
                      child: TextFont(
                        text: "skip".tr(),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        textColor: colors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12, top: 4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: (currentPage + 1) / numPages),
              duration: Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: getColor(context, "canvasContainer"),
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget bottomBar() {
    ColorScheme colors = Theme.of(context).colorScheme;
    bool last = currentPage + 1 >= numPages;
    String nextLabel = last
        ? (getPlatform() == PlatformOS.isIOS
            ? "lets-go".tr()
            : "onb-continue-without-account".tr())
        : "onb-next".tr();
    EdgeInsetsDirectional padding =
        const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 18);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
      child: Row(
        children: [
          if (currentPage > 0) ...[
            Expanded(
              flex: 2,
              child: Button(
                label: "onb-back".tr(),
                icon: Icons.arrow_back_rounded,
                fontSize: 17,
                padding: padding,
                color: getColor(context, "canvasContainer"),
                textColor: getColor(context, "black"),
                iconColor: getColor(context, "black"),
                onTap: previousOnBoardPage,
              ),
            ),
            SizedBox(width: 12),
          ],
          Expanded(
            flex: 3,
            child: Button(
              label: nextLabel,
              fontSize: 17,
              padding: padding,
              color: colors.primary,
              textColor: colors.onPrimary,
              onTap: nextOnBoardPage,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _focusAttachment.reparent();
    final List<Widget> children = [
      for (OnboardingStep step in OnboardingStep.values) buildStep(step),
    ];
    bool wide = MediaQuery.sizeOf(context).width >= 700;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: onboardingMaxWidth,
            maxHeight: wide ? 820 : double.infinity,
          ),
          child: Column(
            children: [
              header(),
              Expanded(
                child: PageView(
                  controller: controller,
                  // Only the buttons move between steps, so a required step
                  // can't be swiped past
                  physics: NeverScrollableScrollPhysics(),
                  onPageChanged: (page) => setState(() => currentPage = page),
                  children: children,
                ),
              ),
              bottomBar(),
            ],
          ),
        ),
      ),
    );
  }
}

// One step: its content scrolls on its own, between the step header and the
// Back / Next buttons
class OnBoardPage extends StatelessWidget {
  const OnBoardPage({Key? key, required this.widgets}) : super(key: key);
  final List<Widget> widgets;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 24),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        ),
      ],
    );
  }
}
