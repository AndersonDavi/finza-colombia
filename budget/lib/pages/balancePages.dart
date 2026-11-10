import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/editWalletsPage.dart';
import 'package:budget/pages/exchangeRatesPage.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/widgets/viewAllTransactionsButton.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/saveBottomButton.dart';
import 'package:budget/widgets/selectAmount.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/transactionEntry/incomeAmountArrow.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:budget/widgets/centeredPageContent.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Full page versions of the transfer and balance correction popups: each
// account shows its balance before and after, the amount is typed in a popup
// that opens with the page.

class BalanceAccountCard extends StatelessWidget {
  const BalanceAccountCard({
    required this.wallet,
    required this.amountChange,
    required this.onTapAmount,
    this.onTapAccount,
    this.onClear,
    this.balanceOverride,
    super.key,
  });
  final TransactionWallet? wallet;
  // Signed change applied to the account, in its currency
  final double amountChange;
  final VoidCallback onTapAmount;
  final VoidCallback? onTapAccount;
  final VoidCallback? onClear;
  // Shown instead of the before/after line, used by the balance correction
  final Widget? balanceOverride;

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Color borderColor = wallet == null
        ? getColor(context, "lightDarkAccentHeavy")
        : pickedColor(context, wallet!.colour)
            .withOpacity(0.7);
    String money(double amount) => convertToMoney(allWallets, amount,
        currencyKey: wallet?.currency, decimals: wallet?.decimals);
    return Tappable(
      onTap: onTapAccount,
      borderRadius: 15,
      color: getColor(context, "lightDarkAccentHeavyLight"),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: borderColor, width: 2),
        ),
        padding: const EdgeInsetsDirectional.all(14),
        child: wallet == null
            ? TextFont(
                text: "select-account".tr(),
                fontSize: 17,
                textColor: getColor(context, "textLight"),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFont(
                          text: wallet!.name +
                              " • " +
                              (wallet!.currency ?? "").toUpperCase(),
                          fontSize: 17,
                        ),
                        SizedBox(height: 18),
                        balanceOverride ??
                            StreamBuilder<double?>(
                              stream: database.watchTotalOfWalletNoConversion(
                                  wallet!.walletPk),
                              builder: (context, snapshot) {
                                double balance = snapshot.data ?? 0;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextFont(
                                      text: money(balance) +
                                          (amountChange == 0
                                              ? ""
                                              : (amountChange < 0
                                                      ? " − "
                                                      : " + ") +
                                                  money(amountChange.abs())),
                                      fontSize: 13,
                                      textColor:
                                          getColor(context, "textLight"),
                                    ),
                                    if (amountChange != 0)
                                      TextFont(
                                        text: "= " +
                                            money(balance + amountChange),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        textColor:
                                            getColor(context, "textLight"),
                                      ),
                                  ],
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                  if (onClear != null && amountChange != 0)
                    IconButton(
                      onPressed: onClear,
                      icon: Icon(
                        appStateSettings["outlinedIcons"]
                            ? Icons.close_outlined
                            : Icons.close_rounded,
                        size: 20,
                      ),
                    ),
                  Tappable(
                    onTap: onTapAmount,
                    borderRadius: 10,
                    color: getColor(context, "lightDarkAccentHeavy")
                        .withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 10, vertical: 6),
                      child: amountChange == 0
                          ? TextFont(
                              text: money(0),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              textColor: getColor(context, "textLight"),
                            )
                          : AmountWithColorAndArrow(
                              showIncomeArrow: true,
                              totalSpent: amountChange,
                              fontSize: 22,
                              iconSize: 26,
                              iconWidth: 16,
                              currencyKey: wallet?.currency,
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class BalanceDateAndTitle extends StatelessWidget {
  const BalanceDateAndTitle({
    required this.dateTime,
    required this.setDateTime,
    required this.title,
    required this.setTitle,
    required this.titleLabel,
    super.key,
  });
  final DateTime? dateTime;
  final Function(DateTime dateTime) setDateTime;
  final String title;
  final Function(String title) setTitle;
  final String titleLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 30),
        DateButton(
          internalPadding: EdgeInsetsDirectional.only(end: 5),
          initialSelectedDate: dateTime ?? DateTime.now(),
          initialSelectedTime: TimeOfDay(
              hour: dateTime?.hour ?? TimeOfDay.now().hour,
              minute: dateTime?.minute ?? TimeOfDay.now().minute),
          setSelectedDate: (date) {
            setDateTime(date);
          },
          setSelectedTime: (time) {
            setDateTime((dateTime ?? DateTime.now())
                .copyWith(hour: time.hour, minute: time.minute));
          },
        ),
        SizedBox(height: 10),
        TextInput(
          icon: appStateSettings["outlinedIcons"]
              ? Icons.title_outlined
              : Icons.title_rounded,
          onChanged: setTitle,
          initialValue: title,
          labelText: titleLabel,
          padding: EdgeInsetsDirectional.zero,
        ),
      ],
    );
  }
}

class TransferBalancePage extends StatefulWidget {
  const TransferBalancePage({
    this.wallet,
    this.allowEditWallet = true,
    this.initialAmount,
    this.initialDate,
    this.initialTitle,
    this.objectiveLoanPk,
    this.isNegative = false,
    super.key,
  });
  final TransactionWallet? wallet;
  final bool allowEditWallet;
  final double? initialAmount;
  final DateTime? initialDate;
  final String? initialTitle;
  final String? objectiveLoanPk;
  // The money goes from the second account to the first one (loan payments)
  final bool isNegative;

  @override
  State<TransferBalancePage> createState() => _TransferBalancePageState();
}

class _TransferBalancePageState extends State<TransferBalancePage> {
  late TransactionWallet? walletFrom = widget.wallet ??
      Provider.of<AllWallets>(context, listen: false)
          .indexedByPk[appStateSettings["selectedWalletPk"]];
  TransactionWallet? walletTo;
  // In the currency of walletFrom
  late double enteredAmount = (widget.initialAmount ?? 0).abs();
  late DateTime? selectedDateTime = widget.initialDate;
  late String selectedTitle = widget.initialTitle ?? "";
  late double direction = widget.isNegative ? -1 : 1;

  @override
  void initState() {
    super.initState();
    // Wait for the page transition, a sheet opened during it does not show
    if (enteredAmount == 0)
      Future.delayed(Duration(milliseconds: 700), () {
        if (mounted) enterAmount();
      });
  }

  // Rate from the currency of walletFrom to the one of walletTo
  double transferRatio(AllWallets allWallets) {
    if (walletFrom == null || walletTo == null) return 1;
    return amountRatioFromToCurrency(
            walletFrom!.currency ?? "", walletTo!.currency ?? "") ??
        1;
  }

  Future<void> selectWallet({required bool from}) async {
    TransactionWallet? result = await selectWalletPopup(
      context,
      selectedWallet: from ? walletFrom : walletTo,
      allowEditWallet: widget.allowEditWallet,
    );
    if (result != null) {
      setState(() {
        if (from)
          walletFrom = result;
        else
          walletTo = result;
      });
    }
  }

  Future<void> enterAmount() async {
    await openBottomSheet(
      context,
      fullSnap: true,
      PopupFramework(
        title: "enter-amount".tr(),
        hasPadding: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: SelectAmount(
            amountPassed: enteredAmount == 0 ? "" : enteredAmount.toString(),
            currencyKey: walletFrom?.currency,
            enableWalletPicker: true,
            showWholeBalance: true,
            selectedWalletPk: walletFrom?.walletPk,
            setSelectedWalletPk: (walletPk) {
              setState(() {
                walletFrom = Provider.of<AllWallets>(context, listen: false)
                    .indexedByPk[walletPk];
              });
            },
            setSelectedAmount: (amount, calculation) {
              setState(() {
                enteredAmount = amount.abs();
              });
            },
            next: () => popRoute(context),
            nextLabel: "set-amount".tr(),
          ),
        ),
      ),
    );
  }

  Future<void> transfer() async {
    AllWallets allWallets = Provider.of<AllWallets>(context, listen: false);
    if (walletFrom == null) return selectWallet(from: true);
    if (walletTo == null) return selectWallet(from: false);
    if (enteredAmount == 0) return enterAmount();
    bool transferred = await createBalanceTransfer(
      allWallets,
      // createBalanceTransfer takes the amount in the primary currency
      amount: enteredAmount *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, walletFrom!.walletPk),
      walletFrom: walletFrom!,
      walletTo: walletTo!,
      isNegative: widget.isNegative,
      dateTime: selectedDateTime,
      title: selectedTitle,
      objectiveLoanPk: widget.objectiveLoanPk,
    );
    if (transferred) {
      savingHapticFeedback();
      popRoute(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    double ratio = transferRatio(allWallets);
    return PageFramework(
      title: "transfer-balance".tr(),
      dragDownToDismiss: true,
      staticOverlay: Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: SaveBottomButton(
          label: walletTo == null
              ? "select-account".tr()
              : enteredAmount == 0
                  ? "set-amount".tr()
                  : "transfer".tr(),
          onTap: transfer,
        ),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: CenteredPageContent(
            maxWidth: 520,
            horizontalPadding: 20,
            child: Column(
              children: [
                BalanceAccountCard(
                  wallet: walletFrom,
                  amountChange: -enteredAmount * direction,
                  onTapAccount: () => selectWallet(from: true),
                  onTapAmount: enterAmount,
                  onClear: () => setState(() => enteredAmount = 0),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      ButtonIcon(
                        onTap: () {
                          setState(() {
                            TransactionWallet? previousFrom = walletFrom;
                            walletFrom = walletTo ?? walletFrom;
                            walletTo = previousFrom;
                          });
                        },
                        icon: appStateSettings["outlinedIcons"]
                            ? Icons.arrow_downward_outlined
                            : Icons.arrow_downward_rounded,
                        size: 38,
                      ),
                      Spacer(),
                      if (walletTo != null)
                        TextFont(
                          text: "× " + ratio.toStringAsFixed(ratio == 1 ? 0 : 4),
                          fontSize: 15,
                          textColor: getColor(context, "textLight"),
                        ),
                    ],
                  ),
                ),
                BalanceAccountCard(
                  wallet: walletTo,
                  amountChange:
                      walletTo == null ? 0 : enteredAmount * ratio * direction,
                  onTapAccount: () => selectWallet(from: false),
                  onTapAmount: enterAmount,
                ),
                BalanceDateAndTitle(
                  dateTime: selectedDateTime,
                  setDateTime: (dateTime) =>
                      setState(() => selectedDateTime = dateTime),
                  title: selectedTitle,
                  setTitle: (title) => selectedTitle = title,
                  titleLabel: "transfer-balance".tr(),
                ),
                if (allWallets.allContainSameCurrency() == false)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 15),
                    child: LowKeyButton(
                      text: "exchange-rates".tr(),
                      onTap: () => pushRoute(context, ExchangeRates()),
                    ),
                  ),
                SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CorrectBalancePage extends StatefulWidget {
  const CorrectBalancePage({required this.wallet, super.key});
  final TransactionWallet wallet;

  @override
  State<CorrectBalancePage> createState() => _CorrectBalancePageState();
}

class _CorrectBalancePageState extends State<CorrectBalancePage> {
  double? enteredAmount;
  bool isNegative = false;
  DateTime? selectedDateTime;
  String selectedTitle = "";

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 700), () {
      if (mounted) enterAmount();
    });
  }

  Future<void> enterAmount() async {
    await openBottomSheet(
      context,
      fullSnap: true,
      PopupFramework(
        title: "enter-amount".tr(),
        subtitle: "new-account-balance".tr(),
        hasPadding: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 18),
          child: SelectAmount(
            extraWidgetAboveNumbers: SettingsContainerSwitch(
              title: "negative-amount".tr(),
              onSwitched: (value) {
                setState(() {
                  isNegative = value;
                  if (enteredAmount != null)
                    enteredAmount =
                        enteredAmount!.abs() * (isNegative ? -1 : 1);
                });
              },
              enableBorderRadius: true,
              initialValue: isNegative,
              syncWithInitialValue: false,
              icon: appStateSettings["outlinedIcons"]
                  ? Icons.exposure_outlined
                  : Icons.exposure_rounded,
            ),
            amountPassed: "",
            currencyKey: widget.wallet.currency,
            allowZero: true,
            setSelectedAmount: (amount, calculation) {
              setState(() {
                enteredAmount = amount.abs() * (isNegative ? -1 : 1);
              });
            },
            next: () => popRoute(context),
            nextLabel: "set-amount".tr(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double amount) => convertToMoney(allWallets, amount,
        currencyKey: widget.wallet.currency,
        decimals: widget.wallet.decimals,
        forceAbsoluteZero: false);
    return StreamBuilder<double?>(
      stream: database.watchTotalOfWalletNoConversion(widget.wallet.walletPk),
      builder: (context, snapshot) {
        double balance = snapshot.data ?? 0;
        double newBalance = enteredAmount ?? balance;
        double difference = newBalance - balance;
        return PageFramework(
          title: "correct-balance".tr(),
          dragDownToDismiss: true,
          staticOverlay: Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: SaveBottomButton(
              label: enteredAmount == null
                  ? "set-amount".tr()
                  : "update-total-balance".tr(),
              onTap: () async {
                if (enteredAmount == null) return enterAmount();
                await correctWalletBalance(
                  context,
                  difference,
                  newBalance,
                  widget.wallet,
                  selectedDateTime,
                  selectedTitle,
                );
                savingHapticFeedback();
                popRoute(context);
              },
            ),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: CenteredPageContent(
                maxWidth: 520,
                horizontalPadding: 20,
                child: Column(
                  children: [
                    Tappable(
                      onTap: enterAmount,
                      borderRadius: 15,
                      color: getColor(context, "lightDarkAccentHeavyLight"),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: pickedColor(context, widget.wallet.colour)
                                .withOpacity(0.7),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsetsDirectional.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFont(text: widget.wallet.name, fontSize: 17),
                            TextFont(
                              text: money(balance),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              textAlign: TextAlign.end,
                              textColor: getColor(context, "textLight"),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Icon(
                                appStateSettings["outlinedIcons"]
                                    ? Icons.arrow_downward_outlined
                                    : Icons.arrow_downward_rounded,
                                size: 20,
                              ),
                            ),
                            Row(
                              children: [
                                if (difference != 0)
                                  AmountWithColorAndArrow(
                                    showIncomeArrow: true,
                                    totalSpent: difference,
                                    fontSize: 13,
                                    iconSize: 18,
                                    iconWidth: 12,
                                    currencyKey: widget.wallet.currency,
                                  ),
                                Spacer(),
                                TextFont(
                                  text: money(newBalance),
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    BalanceDateAndTitle(
                      dateTime: selectedDateTime,
                      setDateTime: (dateTime) =>
                          setState(() => selectedDateTime = dateTime),
                      title: selectedTitle,
                      setTitle: (title) => selectedTitle = title,
                      titleLabel: "correct-balance".tr(),
                    ),
                    SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
