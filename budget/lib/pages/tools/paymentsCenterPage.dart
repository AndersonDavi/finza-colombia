import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/subscriptionsPage.dart';
import 'package:budget/pages/tools/toolWidgets.dart';
import 'package:budget/pages/upcomingOverdueTransactionsPage.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Payments that come back every so often in Colombia, to add with one tap
class DuePreset {
  const DuePreset(this.titleKey, this.type, this.recurrence, this.icon);
  final String titleKey;
  final TransactionSpecialType type;
  final BudgetReoccurence? recurrence;
  final IconData icon;
}

List<DuePreset> duePresets() => [
      DuePreset("due-preset-installment", TransactionSpecialType.subscription,
          BudgetReoccurence.monthly, Icons.two_wheeler_rounded),
      DuePreset("due-preset-utilities", TransactionSpecialType.subscription,
          BudgetReoccurence.monthly, Icons.lightbulb_rounded),
      DuePreset("due-preset-rent", TransactionSpecialType.subscription,
          BudgetReoccurence.monthly, Icons.home_rounded),
      if (livesInColombia()) ...[
        DuePreset("due-preset-soat", TransactionSpecialType.subscription,
            BudgetReoccurence.yearly, Icons.health_and_safety_rounded),
        DuePreset("due-preset-inspection", TransactionSpecialType.subscription,
            BudgetReoccurence.yearly, Icons.build_circle_rounded),
        DuePreset("due-preset-vehicle-tax", TransactionSpecialType.subscription,
            BudgetReoccurence.yearly, Icons.directions_car_rounded),
        DuePreset("due-preset-property-tax", TransactionSpecialType.subscription,
            BudgetReoccurence.yearly, Icons.house_siding_rounded),
        DuePreset("due-preset-income-tax", TransactionSpecialType.upcoming,
            null, Icons.account_balance_rounded),
      ],
    ];

class PaymentsCenterPage extends StatelessWidget {
  const PaymentsCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    DateTime now = DateTime.now();
    return PageFramework(
      title: "payments-center".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        StreamBuilder<List<Transaction>>(
          stream: database.getAllSubscriptions().$1,
          builder: (context, snapshot) {
            List<Transaction> subscriptions = snapshot.data ?? [];
            double monthly = getTotalSubscriptions(allWallets,
                    SelectedSubscriptionsType.monthly, subscriptions)
                .abs();
            double yearly = getTotalSubscriptions(allWallets,
                    SelectedSubscriptionsType.yearly, subscriptions)
                .abs();
            return Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
              child: Column(
                children: [
                  ToolResultRow(
                    label: "subscriptions-a-month".tr(),
                    value: convertToMoney(allWallets, monthly),
                    description: "subscriptions-count".tr(namedArgs: {
                      "count": subscriptions.length.toString()
                    }),
                    highlight: true,
                  ),
                  ToolResultRow(
                    label: "subscriptions-a-year".tr(),
                    value: convertToMoney(allWallets, yearly),
                  ),
                ],
              ),
            );
          },
        ),
        SettingsContainerOpenPage(
          openPage: SubscriptionsPage(),
          title: "subscriptions".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.event_repeat_outlined
              : Icons.event_repeat_rounded,
        ),
        SettingsContainerOpenPage(
          openPage: UpcomingOverdueTransactions(overdueTransactions: null),
          title: "upcoming-and-overdue".tr(),
          icon: appStateSettings["outlinedIcons"]
              ? Icons.schedule_outlined
              : Icons.schedule_rounded,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: ToolSectionTitle(text: "add-a-due-payment".tr()),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (DuePreset preset in duePresets())
                ActionChip(
                  avatar: Icon(preset.icon, size: 18),
                  label: Text(preset.titleKey.tr()),
                  onPressed: () => pushRoute(
                    context,
                    AddTransactionPage(
                      routesToPopAfterDelete: RoutesToPopAfterDelete.None,
                      selectedTitle: preset.titleKey.tr(),
                      selectedType: preset.type,
                      selectedRecurrence: preset.recurrence,
                      selectedIncome: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: ToolNote(text: "due-payment-note".tr()),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
          child: ToolSectionTitle(text: "next-payments".tr()),
        ),
        FutureBuilder<List<Transaction>>(
          future: database.getAllUpcomingTransactions(
            startDate: now.subtract(Duration(days: 60)),
            endDate: now.add(Duration(days: 60)),
          ),
          builder: (context, snapshot) {
            List<Transaction> upcoming = snapshot.data ?? [];
            if (snapshot.hasData && upcoming.isEmpty) {
              return Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
                child: ToolNote(text: "no-upcoming-payments".tr()),
              );
            }
            return Column(
              children: [
                for (Transaction transaction in upcoming)
                  TransactionEntry(
                    openPage: AddTransactionPage(
                      transaction: transaction,
                      routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                    ),
                    transaction: transaction,
                    listID: "paymentsCenter",
                  ),
              ],
            );
          },
        ),
        SizedBox(height: 50),
      ],
    );
  }
}
