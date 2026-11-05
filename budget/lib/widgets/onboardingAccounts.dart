import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/database/walletGroups.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/walletGroups.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// An account offered in the onboarding: where people keep their money
class AccountPreset {
  const AccountPreset(this.name, this.colour, this.kind);
  final String name;
  final Color colour;
  final WalletGroupKind kind;
}

List<AccountPreset> accountPresets() {
  if (livesInColombia()) {
    return const [
      AccountPreset("Bancolombia", Color(0xFFFDDA24), WalletGroupKind.digital),
      AccountPreset("Nequi", Color(0xFFDA0081), WalletGroupKind.digitalWallet),
      AccountPreset(
          "Daviplata", Color(0xFFE4002B), WalletGroupKind.digitalWallet),
      AccountPreset("Davivienda", Color(0xFFED1C24), WalletGroupKind.digital),
      AccountPreset(
          "Banco de Bogotá", Color(0xFF00408E), WalletGroupKind.digital),
      AccountPreset("BBVA", Color(0xFF004481), WalletGroupKind.digital),
      AccountPreset("Nu", Color(0xFF820AD1), WalletGroupKind.digital),
    ];
  }
  return const [
    AccountPreset("Bank", Color(0xFF1565C0), WalletGroupKind.digital),
    AccountPreset(
        "Digital wallet", Color(0xFF6A1B9A), WalletGroupKind.digitalWallet),
    AccountPreset("Credit card", Color(0xFF37474F), WalletGroupKind.creditCard),
  ];
}

// Cash is offered everywhere, in the app's language
AccountPreset cashPreset() =>
    AccountPreset("cash".tr(), Color(0xFF2E7D32), WalletGroupKind.cash);

// The first account takes the pocket every new install starts with, so no
// loose pocket is left outside the accounts
Future<bool> adoptStarterPocket(String walletGroupPk, String? colour) async {
  TransactionWallet? starter = await database.getWalletInstanceOrNull("0");
  if (starter == null || starter.walletGroupFk != null) return false;
  List<TransactionWallet> created = (await database.getAllWallets())
      .where((w) => w.walletGroupFk == walletGroupPk && w.walletPk != "0")
      .toList();
  for (TransactionWallet wallet in created) {
    await database.deleteWallet(wallet.walletPk, wallet.order);
  }
  await database.createOrUpdateWallet(starter.copyWith(
    name: "free-money".tr(),
    colour: Value(colour),
    walletGroupFk: Value(walletGroupPk),
  ));
  WalletGroup? group = (await database.getAllWalletGroups())
      .where((g) => g.walletGroupPk == walletGroupPk)
      .firstOrNull;
  if (group != null) {
    await database
        .createOrUpdateWalletGroup(group.copyWith(freeWalletFk: Value("0")));
  }
  return true;
}

Future<void> createAccountFromPreset(AccountPreset preset) async {
  String colour = toHexString(preset.colour)!;
  String walletGroupPk = await database.createOrUpdateWalletGroup(
    insert: true,
    WalletGroup(
      walletGroupPk: "-1",
      name: preset.name,
      colour: colour,
      kind: preset.kind,
      order: 0,
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      freeWalletFk: null,
      gmfExempt: false,
    ),
  );
  if (await adoptStarterPocket(walletGroupPk, colour)) return;
  TransactionWallet? starter = await database.getWalletInstanceOrNull("0");
  await database.createFreePocket(
    walletGroupPk,
    name: "free-money".tr(),
    colour: colour,
    currency: starter?.currency,
  );
}

// Unchecking an account made in the onboarding: its new pockets go with it,
// the starter pocket goes back to being loose
Future<void> removeOnboardingAccount(WalletGroup group) async {
  for (TransactionWallet wallet in await database.getAllWallets()) {
    if (wallet.walletGroupFk != group.walletGroupPk) continue;
    if (wallet.walletPk == "0") {
      await database.createOrUpdateWallet(wallet.copyWith(
        name: "default-account-name".tr(),
        walletGroupFk: Value(null),
      ));
    } else {
      await database.deleteWallet(wallet.walletPk, wallet.order);
    }
  }
  await database.deleteWalletGroup(group.walletGroupPk);
}

class OnboardingAccountsStep extends StatelessWidget {
  const OnboardingAccountsStep({super.key});

  Future<void> addOther(BuildContext context) async {
    String? walletGroupPk = await openEditWalletGroupPopup(context);
    if (walletGroupPk == null) return;
    WalletGroup? group = (await database.getAllWalletGroups())
        .where((g) => g.walletGroupPk == walletGroupPk)
        .firstOrNull;
    await adoptStarterPocket(walletGroupPk, group?.colour);
  }

  @override
  Widget build(BuildContext context) {
    List<AccountPreset> presets = [...accountPresets(), cashPreset()];
    return StreamBuilder<List<WalletGroup>>(
      stream: database.watchAllWalletGroups(),
      builder: (context, snapshot) {
        List<WalletGroup> groups = snapshot.data ?? [];
        WalletGroup? groupNamed(String name) => groups
            .where((g) => g.name.trim().toLowerCase() == name.toLowerCase())
            .firstOrNull;
        List<WalletGroup> custom = groups
            .where((g) => presets.every(
                (p) => p.name.toLowerCase() != g.name.trim().toLowerCase()))
            .toList();
        return Column(
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (AccountPreset preset in presets)
                  Builder(builder: (context) {
                    WalletGroup? existing = groupNamed(preset.name);
                    return FilterChip(
                      avatar: Icon(
                        walletGroupKindIcon(preset.kind),
                        size: 18,
                        color: pickedColor(context, toHexString(preset.colour)),
                      ),
                      label: TextFont(text: preset.name, fontSize: 15),
                      selected: existing != null,
                      onSelected: (selected) async {
                        if (existing != null) {
                          await removeOnboardingAccount(existing);
                        } else {
                          await createAccountFromPreset(preset);
                        }
                      },
                    );
                  }),
                for (WalletGroup group in custom)
                  FilterChip(
                    avatar: Icon(
                      walletGroupKindIcon(group.kind),
                      size: 18,
                      color: pickedColor(context, group.colour),
                    ),
                    label: TextFont(text: group.name, fontSize: 15),
                    selected: true,
                    onSelected: (_) =>
                        openEditWalletGroupPopup(context, group: group),
                  ),
                ActionChip(
                  avatar: Icon(Icons.add_rounded, size: 18),
                  label: TextFont(
                      text: "onboarding-other-account".tr(), fontSize: 15),
                  onPressed: () => addOther(context),
                ),
              ],
            ),
            if (groups.isNotEmpty) ...[
              SizedBox(height: 15),
              TextFont(
                text: "onboarding-accounts-edit-hint".tr(),
                fontSize: 14,
                textAlign: TextAlign.center,
                maxLines: 3,
                textColor: getColor(context, "black").withOpacity(0.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

// A made-up account with three pockets, to show what pockets are for
class PocketsExample extends StatelessWidget {
  const PocketsExample({super.key});

  @override
  Widget build(BuildContext context) {
    Widget pocket(String name, String amount, Color color, {bool free = false}) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: 8),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 10),
            Expanded(
              child: TextFont(
                text: name,
                fontSize: 16,
                fontWeight: free ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            TextFont(text: amount, fontSize: 16, fontWeight: FontWeight.bold),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: 360),
      margin: const EdgeInsetsDirectional.symmetric(horizontal: 25),
      padding: const EdgeInsetsDirectional.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(walletGroupKindIcon(WalletGroupKind.digital),
                  color: Theme.of(context).colorScheme.primary),
              SizedBox(width: 8),
              TextFont(
                text: "onboarding-pockets-example-account".tr(),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ],
          ),
          SizedBox(height: 4),
          pocket("free-money".tr(), "\$450.000", getColor(context, "incomeAmount"),
              free: true),
          pocket("onboarding-pockets-example-rent".tr(), "\$1.200.000",
              Colors.orange),
          pocket("onboarding-pockets-example-goal".tr(), "\$800.000",
              Colors.blue),
        ],
      ),
    );
  }
}

// The default categories, so the user sees what is already there
class CategoriesExample extends StatelessWidget {
  const CategoriesExample({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransactionCategory>>(
      stream: database.watchAllCategories(),
      builder: (context, snapshot) {
        List<TransactionCategory> categories = (snapshot.data ?? [])
            .where((c) => c.categoryPk != "0" && c.mainCategoryPk == null)
            .take(12)
            .toList();
        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (TransactionCategory category in categories)
              SizedBox(
                width: 78,
                child: CategoryIcon(
                  category: category,
                  categoryPk: category.categoryPk,
                  size: 32,
                  label: true,
                  labelSize: 12,
                  canEditByLongPress: false,
                  enableTooltip: false,
                ),
              ),
          ],
        );
      },
    );
  }
}
