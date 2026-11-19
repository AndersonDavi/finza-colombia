import 'dart:math';
import 'package:budget/colors.dart';
import 'package:budget/database/initializeDefaultDatabase.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/functions.dart';
import 'package:budget/main.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/tools/rateMath.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/notificationsSettings.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:budget/widgets/walletEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Demo with made up data: three accounts with their pockets, about three
// months of movements in pesos and the fixed payments coming up. Everything it
// makes is marked as preview (transactions) or uses the ids below (accounts
// and pockets), so leaving the demo removes exactly that

const List<String> _demoGroupPks = ["10", "11", "12"];
// Pocket "0" is the one every install starts with, it becomes the free pocket
// of the first account and goes back to normal when the demo ends
const List<String> _demoWalletPks = ["10", "11", "12", "13", "14"];

Future deletePreviewData({bool resetOnboard = false}) async {
  if (resetOnboard) {
    updateSettings("hasOnboarded", false, updateGlobalState: true);
    // The next person going through the onboarding sees the tour again
    updateSettings("homeTourSeen", false, updateGlobalState: false);
  }

  loadingIndeterminateKey.currentState?.setVisibility(true);
  try {
    await cancelUpcomingTransactionsNotification();
  } catch (e) {
    print(e.toString());
  }

  try {
    List<Transaction> transactionsToDelete =
        await database.getAllPreviewTransactions();
    List<String> transactionPks = transactionsToDelete
        .map((transaction) => transaction.transactionPk)
        .toList();
    await database.deleteTransactions(transactionPks, updateSharedEntry: false);
  } catch (e) {
    print(e.toString());
  }

  // Highest order first, so the order of the pockets that stay is kept
  for (String walletPk in _demoWalletPks.reversed) {
    try {
      TransactionWallet? wallet =
          await database.getWalletInstanceOrNull(walletPk);
      if (wallet != null) await database.deleteWallet(walletPk, wallet.order);
    } catch (e) {
      print(e.toString());
    }
  }
  for (String walletGroupPk in _demoGroupPks) {
    try {
      await database.deleteWalletGroup(walletGroupPk);
    } catch (e) {
      print(e.toString());
    }
  }

  await database.createOrUpdateWallet(
    defaultWallet(),
    customDateTimeModified: DateTime(0),
  );

  await setPrimaryWallet("0");

  await database.deleteAllDeleteLogs();

  await createDefaultCategories();

  loadingIndeterminateKey.currentState?.setVisibility(false);
  updateSettings("previewDemo", false, updateGlobalState: false);
}

class _DemoPocket {
  const _DemoPocket(this.pk, this.name, this.groupPk, this.colour,
      {this.goalAmount, this.goalMonths});
  final String pk;
  final String name;
  final String groupPk;
  final String colour;
  final double? goalAmount;
  // The goal date, in months from today
  final int? goalMonths;
}

Future generatePreviewData() async {
  updateSettings("previewDemo", true, updateGlobalState: false);
  loadingIndeterminateKey.currentState?.setVisibility(true);
  await createDefaultCategories();
  await initializeBalanceCorrectionCategory();

  DateTime now = DateTime.now();
  int decimals = 0;
  String currency = "cop";

  // Accounts: where the money is
  List<WalletGroup> groups = [
    WalletGroup(
      walletGroupPk: "10",
      name: "Bancolombia",
      colour: "0xfffdda24",
      kind: WalletGroupKind.digital,
      order: 0,
      dateCreated: now,
      dateTimeModified: null,
      freeWalletFk: "0",
      gmfExempt: true,
    ),
    WalletGroup(
      walletGroupPk: "11",
      name: "Nequi",
      colour: "0xffda0081",
      kind: WalletGroupKind.digitalWallet,
      order: 1,
      dateCreated: now,
      dateTimeModified: null,
      freeWalletFk: "12",
      gmfExempt: false,
    ),
    WalletGroup(
      walletGroupPk: "12",
      name: "cash".tr(),
      colour: "0xff2e7d32",
      kind: WalletGroupKind.cash,
      order: 2,
      dateCreated: now,
      dateTimeModified: null,
      freeWalletFk: "14",
      gmfExempt: false,
    ),
  ];
  for (WalletGroup group in groups) {
    await database.createOrUpdateWalletGroup(group);
  }

  // Pockets: money set apart inside each account
  List<_DemoPocket> pockets = [
    _DemoPocket("0", "free-money".tr(), "10", "0xfffdda24"),
    _DemoPocket("10", "Arriendo", "10", "0xffef6c00"),
    _DemoPocket("11", "Fondo de emergencia", "10", "0xff1565c0",
        goalAmount: 3000000),
    _DemoPocket("12", "free-money".tr(), "11", "0xffda0081"),
    _DemoPocket("13", "Viaje a Cartagena", "11", "0xff00838f",
        goalAmount: 1500000, goalMonths: 4),
    _DemoPocket("14", "free-money".tr(), "12", "0xff2e7d32"),
  ];
  for (int i = 0; i < pockets.length; i++) {
    _DemoPocket pocket = pockets[i];
    await database.createOrUpdateWallet(
      TransactionWallet(
        archived: false,
        walletPk: pocket.pk,
        name: pocket.name,
        colour: pocket.colour,
        iconName: null,
        dateCreated: now.subtract(Duration(days: 95)),
        dateTimeModified: null,
        order: i,
        currency: currency,
        decimals: decimals,
        homePageWidgetDisplay: defaultWalletHomePageWidgetDisplay,
        walletGroupFk: pocket.groupPk,
        goalAmount: pocket.goalAmount,
        goalDate: pocket.goalMonths == null
            ? null
            : DateTime(now.year, now.month + pocket.goalMonths!, 1),
      ),
    );
  }
  await setPrimaryWallet("0");

  String label(String walletPk) {
    _DemoPocket pocket = pockets.firstWhere((p) => p.pk == walletPk);
    String group =
        groups.firstWhere((g) => g.walletGroupPk == pocket.groupPk).name;
    return group + " · " + pocket.name;
  }

  // Same seed every time: the demo always looks the same
  Random random = Random(1907);
  double between(double low, double high, {double step = 100}) =>
      ((low + random.nextDouble() * (high - low)) / step).round() * step;

  List<TransactionsCompanion> rows = [];

  void add(String name, double amount, String categoryFk, String walletFk,
      DateTime date,
      {String note = ""}) {
    rows.add(Transaction(
      methodAdded: MethodAdded.preview,
      transactionPk: uuid.v4(),
      name: name,
      amount: amount,
      note: note,
      categoryFk: categoryFk,
      walletFk: walletFk,
      dateCreated: date,
      income: amount > 0,
      paid: true,
      skipPaid: true,
    ).toCompanion(true));
  }

  // Like a transfer made in the app: two paired balance corrections, the
  // incoming one a second later
  void transfer(String title, double amount, String fromPk, String toPk,
      DateTime date) {
    String note = "transferred-balance".tr() +
        "\n" +
        label(fromPk) +
        " → " +
        label(toPk);
    String toTransactionPk = uuid.v4();
    rows.add(Transaction(
      methodAdded: MethodAdded.preview,
      transactionPk: toTransactionPk,
      name: title,
      amount: amount,
      note: note,
      categoryFk: "0",
      walletFk: toPk,
      dateCreated: date.add(Duration(seconds: 1)),
      income: true,
      paid: true,
      skipPaid: false,
    ).toCompanion(true));
    rows.add(Transaction(
      methodAdded: MethodAdded.preview,
      transactionPk: uuid.v4(),
      pairedTransactionFk: toTransactionPk,
      name: title,
      amount: -amount,
      note: note,
      categoryFk: "0",
      walletFk: fromPk,
      dateCreated: date,
      income: false,
      paid: true,
      skipPaid: false,
    ).toCompanion(true));
  }

  DateTime today = DateTime(now.year, now.month, now.day);
  DateTime start = today.subtract(Duration(days: 89));

  // What each pocket had when the demo starts
  DateTime opening = start.add(Duration(hours: 8));
  String openingName = "Saldo inicial";
  add(openingName, 1200000, "0", "0", opening);
  add(openingName, 1100000, "0", "10", opening.add(Duration(minutes: 1)));
  add(openingName, 1200000, "0", "11", opening.add(Duration(minutes: 2)));
  add(openingName, 150000, "0", "12", opening.add(Duration(minutes: 3)));
  add(openingName, 300000, "0", "13", opening.add(Duration(minutes: 4)));
  add(openingName, 80000, "0", "14", opening.add(Duration(minutes: 5)));

  const List<String> groceries = [
    "Mercado D1",
    "Mercado Éxito",
    "Mercado Ara",
    "Plaza de mercado",
  ];
  int groceryIndex = 0;

  for (DateTime day = start.add(Duration(days: 1));
      !day.isAfter(today);
      day = DateTime(day.year, day.month, day.day + 1)) {
    DateTime at(int hour, int minute) =>
        DateTime(day.year, day.month, day.day, hour, minute);
    bool isToday = day == today;
    int lastDay = daysInMonth(day.year, day.month);
    int salaryEnd = min(30, lastDay);
    bool weekday = day.weekday <= DateTime.friday;

    // Biweekly salary, and where it goes
    if (day.day == 15 || day.day == salaryEnd) {
      add("Salario", 1800000, "11", "0", at(7, 30));
      if (day.day == 15) {
        transfer("Pasar a Nequi", 250000, "0", "12", at(8, 10));
        transfer("Ahorro del viaje", 150000, "0", "13", at(8, 12));
        transfer("Retiro en cajero", 120000, "0", "14", at(12, 40));
      } else {
        transfer("Apartar el arriendo", 1100000, "0", "10", at(8, 5));
        transfer("Ahorro del mes", 200000, "0", "11", at(8, 7));
        transfer("Pasar a Nequi", 150000, "0", "12", at(8, 9));
      }
    }

    // Fixed payments
    if (day.day == 1) add("Arriendo", -1100000, "6", "10", at(9, 15));
    if (day.day == 10) {
      add("Luz, agua y gas", -between(130000, 170000), "6", "0", at(18, 20));
    }
    if (day.day == 15) add("Internet y celular", -89900, "6", "0", at(19, 2));
    if (day.day == 20) add("Streaming", -26900, "5", "0", at(6, 0));

    // Day to day spending; today only gets the morning
    if (day.weekday == DateTime.saturday) {
      add(groceries[groceryIndex++ % groceries.length],
          -between(110000, 240000), "2", "0", at(10, 25));
    }
    if (weekday) {
      if (random.nextDouble() < 0.6) {
        add("Tinto", -between(2500, 3500, step: 500), "1", "14", at(7, 50));
      }
      add("Pasaje", -2950, "4", "12", at(6, 45));
      if (!isToday) {
        add("Pasaje", -2950, "4", "12", at(17, 55));
        if (random.nextDouble() < 0.7) {
          add("Almuerzo", -between(14000, 26000, step: 500), "1", "0",
              at(12, 35));
        }
      }
    }
    if (!isToday) {
      if (random.nextDouble() < 0.2) {
        add("Uber", -between(12000, 28000), "4", "12", at(21, 10));
      }
      if (day.weekday >= DateTime.friday && random.nextDouble() < 0.3) {
        add("Rappi", -between(32000, 65000), "1", "0", at(20, 30));
      }
      if (day.weekday >= DateTime.friday && random.nextDouble() < 0.15) {
        add("Cine", -between(18000, 26000), "5", "0", at(19, 40));
      }
      if (random.nextDouble() < 0.04) {
        add("Ropa", -between(70000, 160000, step: 1000), "3", "0",
            at(16, 15));
      }
    }
  }
  // A side job some weeks ago
  DateTime freelance = today.subtract(Duration(days: 38));
  add("Trabajo freelance", 350000, "11", "12",
      DateTime(freelance.year, freelance.month, freelance.day, 15, 0),
      note: "Diseño de un logo");

  // Coming up: the same fixed items the onboarding creates, waiting to be
  // confirmed when the money actually moves
  void upcoming(String name, double amount, String categoryFk,
      String walletFk, int dayOfMonth) {
    bool income = amount > 0;
    rows.add(Transaction(
      methodAdded: MethodAdded.preview,
      transactionPk: uuid.v4(),
      name: name,
      note: "onb-fixed-note".tr(),
      amount: amount,
      categoryFk: categoryFk,
      walletFk: walletFk,
      dateCreated: nextDayOfMonth(today.add(Duration(days: 1)), dayOfMonth)
          .add(Duration(hours: 9)),
      income: income,
      paid: false,
      skipPaid: false,
      type: income
          ? TransactionSpecialType.repetitive
          : TransactionSpecialType.subscription,
      reoccurrence: BudgetReoccurence.monthly,
      periodLength: 1,
      upcomingTransactionNotification: true,
      createdAnotherFutureTransaction: false,
    ).toCompanion(true));
  }

  upcoming("Salario", 1800000, "11", "0", 15);
  upcoming("Salario", 1800000, "11", "0", 30);
  upcoming("Arriendo", -1100000, "6", "10", 1);
  upcoming("Luz, agua y gas", -150000, "6", "0", 10);
  upcoming("Internet y celular", -89900, "6", "0", 15);
  upcoming("Streaming", -26900, "5", "0", 20);

  await database.createBatchTransactionsOnly(rows);

  loadingIndeterminateKey.currentState?.setVisibility(false);
}

class PreviewDemoWarning extends StatelessWidget {
  const PreviewDemoWarning({super.key});

  @override
  Widget build(BuildContext context) {
    if (appStateSettings["previewDemo"] != true) return SizedBox.shrink();
    ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(
          bottom: MediaQuery.viewPaddingOf(context).top),
      child: Tappable(
        onTap: () => confirmExitPreviewDemo(context),
        color: colors.tertiaryContainer,
        child: Padding(
          padding:
              const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.science_rounded, color: colors.onTertiaryContainer),
              SizedBox(width: 12),
              Expanded(
                child: TextFont(
                  text: "preview-demo-warning".tr(),
                  textColor: colors.onTertiaryContainer,
                  fontSize: 15,
                  maxLines: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> confirmExitPreviewDemo(BuildContext context) async {
  await openPopup(
    context,
    icon: Icons.science_rounded,
    title: "exit-demo".tr(),
    description: "exit-demo-description".tr(),
    onCancel: () {
      popRoute(context);
    },
    onCancelLabel: "cancel".tr(),
    onSubmit: () {
      popAllRoutes(context);
      deletePreviewData(resetOnboard: true);
    },
    onSubmitLabel: "exit-demo".tr(),
  );
}

class PreviewDemoButton extends StatelessWidget {
  const PreviewDemoButton({required this.nextNavigation, super.key});
  final Function nextNavigation;

  // A tool for debugging, not for users: only debug builds offer it
  @override
  Widget build(BuildContext context) {
    if (!allowDangerousDebugFlags) return SizedBox.shrink();
    return LowKeyButton(
      onTap: () {
        openPopup(
          context,
          icon: Icons.science_rounded,
          title: "preview-demo".tr(),
          description: "preview-demo-description".tr(),
          onCancel: () {
            popRoute(context);
          },
          onCancelLabel: "cancel".tr(),
          onSubmit: () {
            popRoute(context);
            nextNavigation(generatePreview: true);
          },
          onSubmitLabel: "activate".tr(),
        );
      },
      text: "preview-demo".tr(),
      extraWidget: Padding(
        padding: const EdgeInsetsDirectional.only(start: 5),
        child: Icon(
          Icons.science_rounded,
          size: 17,
          color: getColor(context, "black").withOpacity(0.5),
        ),
      ),
    );
  }
}

Future<bool> checkLockedFeatureIfInDemoMode(BuildContext? context) async {
  if (context == null && appStateSettings["previewDemo"] == true) return false;
  if (appStateSettings["previewDemo"] == true) {
    await openPopup(
      context!,
      icon: appStateSettings["outlinedIcons"]
          ? Icons.warning_outlined
          : Icons.warning_rounded,
      title: "not-available-in-preview-demo".tr(),
      description: "not-available-in-preview-demo-description".tr(),
      onCancel: () {
        popRoute(context);
      },
      onCancelLabel: "cancel".tr(),
      onSubmit: () {
        popAllRoutes(context);
        deletePreviewData(resetOnboard: true);
      },
      onSubmitLabel: "exit-demo".tr(),
    );
    return false;
  }
  return true;
}
