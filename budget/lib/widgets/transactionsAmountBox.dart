import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/upcomingOverdueTransactionsPage.dart';
import 'package:budget/widgets/openContainerNavigation.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:budget/widgets/countNumber.dart';
import 'package:provider/provider.dart';

// If you just added an upcoming transaction and mark it as paid, it will not show up here
// This is because the query transactionsAmountStream needs to be updated to have the new DateTime.now(),
// as it won't catch the new transaction amount!

class TransactionsAmountBox extends StatelessWidget {
  const TransactionsAmountBox({
    this.openPage,
    this.onLongPress,
    required this.label,
    required this.totalWithCountStream,
    this.totalWithCountStream2,
    required this.textColor,
    this.absolute = true,
    this.invertSign = false,
    this.getTextColor,
    this.currencyKey,
    this.labelIcon,
    this.topEndLabel,
    this.bottomEndLabel,
    this.shortCount = false,
    super.key,
  });
  final Widget? openPage;
  final Function? onLongPress;
  final String label;
  final Stream<TotalWithCount?> totalWithCountStream;
  final Stream<TotalWithCount?>? totalWithCountStream2;
  final Color textColor;
  final bool absolute;
  final bool invertSign;
  final String? currencyKey;
  final Function(double)? getTextColor;
  // Detailed layout (6.x style): label with an icon at the start, the number of
  // accounts and the period in the corners and the amount aligned to the end.
  // Used when any of these is set.
  final Widget? labelIcon;
  final String? topEndLabel;
  final String? bottomEndLabel;
  // "×11" instead of "×11 transactions", for the half width cards
  final bool shortCount;

  bool get detailedLayout =>
      labelIcon != null || topEndLabel != null || bottomEndLabel != null;

  Widget buildDetailed(BuildContext context) {
    TextFont smallLabel(String text) => TextFont(
          text: text,
          fontSize: 12,
          maxLines: 1,
          textColor: getColor(context, "textLight"),
        );
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 15, vertical: 15),
      child: DoubleTotalWithCountStreamBuilder(
        totalWithCountStream: totalWithCountStream,
        totalWithCountStream2: totalWithCountStream2,
        builder: (context, snapshot) {
          double totalSpent = snapshot.data?.total ?? 0;
          int totalCount = snapshot.data?.count ?? 0;
          double finalAmount = snapshot.hasData == false || snapshot.data == null
              ? 0
              : absolute == true
                  ? (totalSpent).abs()
                  : totalSpent * (invertSign == true ? -1 : 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (labelIcon != null) labelIcon!,
                  if (labelIcon != null) SizedBox(width: 4),
                  Expanded(
                    child: TextFont(
                      text: label,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      maxLines: 1,
                    ),
                  ),
                  if (topEndLabel != null) smallLabel(topEndLabel!),
                ],
              ),
              SizedBox(height: 8),
              CountNumber(
                count: finalAmount,
                duration: Duration(milliseconds: 1000),
                initialCount: (0),
                textBuilder: (number) {
                  // Blank while the total loads instead of a $0
                  return Opacity(
                    opacity: snapshot.hasData ? 1 : 0,
                    child: TextFont(
                    text: convertToMoney(
                        Provider.of<AllWallets>(context), number,
                        currencyKey: currencyKey,
                        addCurrencyName: currencyKey != null,
                        finalNumber: finalAmount),
                    textColor: getTextColor != null
                        ? getTextColor!(totalSpent)
                        : textColor,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.end,
                    autoSizeText: true,
                    fontSize: 21,
                    maxFontSize: 21,
                    minFontSize: 10,
                    maxLines: 1,
                    ),
                  );
                },
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  smallLabel("×" +
                      totalCount.toString() +
                      (shortCount
                          ? ""
                          : " " +
                              (totalCount == 1
                                  ? "transaction".tr().toLowerCase()
                                  : "transactions".tr().toLowerCase()))),
                  Spacer(),
                  if (bottomEndLabel != null) smallLabel(bottomEndLabel!),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
          BoxDecoration(boxShadow: boxShadowCheck(boxShadowGeneral(context))),
      child: OpenContainerNavigation(
        closedColor: getColor(context, "lightDarkAccentHeavyLight"),
        openPage: openPage ?? SizedBox.shrink(),
        borderRadius: 15,
        button: (openContainer) {
          return Tappable(
            color: getColor(context, "lightDarkAccentHeavyLight"),
            onTap: () {
              if (openPage != null) openContainer();
            },
            onLongPress: () {
              if (onLongPress != null) onLongPress!();
            },
            child: detailedLayout ? buildDetailed(context) : Container(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 15, vertical: 17),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFont(
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      text: label,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    SizedBox(height: 6),
                    DoubleTotalWithCountStreamBuilder(
                      totalWithCountStream: totalWithCountStream,
                      totalWithCountStream2: totalWithCountStream2,
                      builder: (context, snapshot) {
                        double totalSpent = snapshot.data?.total ?? 0;
                        int totalCount = snapshot.data?.count ?? 0;
                        double finalAmount = snapshot.hasData == false ||
                                snapshot.data == null
                            ? 0
                            : absolute == true
                                ? (totalSpent).abs()
                                : totalSpent * (invertSign == true ? -1 : 1);
                        return Column(
                          children: [
                            CountNumber(
                              count: finalAmount,
                              duration: Duration(milliseconds: 1000),
                              initialCount: (0),
                              textBuilder: (number) {
                                return Opacity(
                                  opacity: snapshot.hasData ? 1 : 0,
                                  child: TextFont(
                                  text: convertToMoney(
                                      Provider.of<AllWallets>(context), number,
                                      currencyKey: currencyKey,
                                      addCurrencyName: currencyKey != null,
                                      finalNumber: finalAmount),
                                  textColor: getTextColor != null
                                      ? getTextColor!(totalSpent)
                                      : textColor,
                                  fontWeight: FontWeight.bold,
                                  textAlign: TextAlign.center,
                                  autoSizeText: true,
                                  fontSize: 21,
                                  maxFontSize: 21,
                                  minFontSize: 10,
                                  maxLines: 1,
                                  ),
                                );
                              },
                            ),
                            SizedBox(height: 6),
                            TextFont(
                              maxLines: 2,
                              text: totalCount.toString() +
                                  " " +
                                  (totalCount == 1
                                      ? "transaction".tr().toLowerCase()
                                      : "transactions".tr().toLowerCase()),
                              fontSize: 13,
                              textAlign: TextAlign.center,
                              textColor: getColor(context, "textLight"),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
