import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Icons a pocket can show inside its colour dot. Saved in the account's
// emojiIconName as "icon:<key>", so the keys must never change.
const Map<String, IconData> pocketIcons = {
  "savings": Icons.savings_rounded,
  "wallet": Icons.account_balance_wallet_rounded,
  "bank": Icons.account_balance_rounded,
  "card": Icons.credit_card_rounded,
  "cash": Icons.payments_rounded,
  "invest": Icons.trending_up_rounded,
  "home": Icons.home_rounded,
  "rent": Icons.key_rounded,
  "bills": Icons.receipt_long_rounded,
  "power": Icons.bolt_rounded,
  "wifi": Icons.wifi_rounded,
  "phone": Icons.smartphone_rounded,
  "gas": Icons.local_gas_station_rounded,
  "car": Icons.directions_car_rounded,
  "moto": Icons.two_wheeler_rounded,
  "bus": Icons.directions_bus_rounded,
  "travel": Icons.flight_rounded,
  "beach": Icons.beach_access_rounded,
  "food": Icons.restaurant_rounded,
  "groceries": Icons.shopping_cart_rounded,
  "coffee": Icons.local_cafe_rounded,
  "shopping": Icons.shopping_bag_rounded,
  "gift": Icons.card_giftcard_rounded,
  "gym": Icons.fitness_center_rounded,
  "health": Icons.favorite_rounded,
  "medical": Icons.medical_services_rounded,
  "pet": Icons.pets_rounded,
  "kids": Icons.child_care_rounded,
  "school": Icons.school_rounded,
  "work": Icons.work_rounded,
  "tech": Icons.computer_rounded,
  "games": Icons.sports_esports_rounded,
  "music": Icons.music_note_rounded,
  "movies": Icons.movie_rounded,
  "loan": Icons.handshake_rounded,
  "emergency": Icons.health_and_safety_rounded,
  "star": Icons.star_rounded,
  "flag": Icons.flag_rounded,
};

const String pocketIconPrefix = "icon:";

IconData? pocketIconOf(TransactionWallet wallet) {
  String? value = wallet.emojiIconName;
  if (value == null || !value.startsWith(pocketIconPrefix)) return null;
  return pocketIcons[value.substring(pocketIconPrefix.length)];
}

// An emoji saved by the official app, shown as is
String? pocketEmojiOf(TransactionWallet wallet) {
  String? value = wallet.emojiIconName;
  if (value == null || value.isEmpty || value.startsWith(pocketIconPrefix))
    return null;
  return value;
}

// Row in the edit account page. The popup returns "" for no icon.
class PocketIconSetting extends StatelessWidget {
  const PocketIconSetting({
    required this.emojiIconName,
    required this.colour,
    required this.onChanged,
    super.key,
  });
  final String? emojiIconName;
  final Color colour;
  final Function(String? emojiIconName) onChanged;

  @override
  Widget build(BuildContext context) {
    IconData? icon = emojiIconName?.startsWith(pocketIconPrefix) == true
        ? pocketIcons[emojiIconName!.substring(pocketIconPrefix.length)]
        : null;
    return SettingsContainer(
      isOutlined: true,
      isWideOutlined: true,
      title: "icon".tr(),
      icon: appStateSettings["outlinedIcons"]
          ? Icons.emoji_symbols_outlined
          : Icons.emoji_symbols_rounded,
      afterWidget: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colour.withOpacity(0.7),
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: dotIconColor(colour))
            : emojiIconName != null && emojiIconName != ""
                ? TextFont(text: emojiIconName!, fontSize: 16)
                : null,
      ),
      onTap: () async {
        dynamic result = await openBottomSheet(
          context,
          PocketIconPopup(selected: emojiIconName, colour: colour),
        );
        if (result is String) onChanged(result == "" ? null : result);
      },
    );
  }
}

Color dotIconColor(Color background) =>
    (background.withOpacity(1).computeLuminance() > 0.4
            ? Colors.black
            : Colors.white)
        .withOpacity(0.85);

class PocketIconPopup extends StatelessWidget {
  const PocketIconPopup({this.selected, required this.colour, super.key});
  final String? selected;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    Widget option(String value, Widget child) {
      bool isSelected = (selected ?? "") == value;
      return Tappable(
        borderRadius: 100,
        color: isSelected
            ? colour.withOpacity(0.7)
            : getColor(context, "lightDarkAccentHeavyLight"),
        onTap: () => popRoute(context, value),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: getColor(context, "black"), width: 2)
                : null,
          ),
          child: child,
        ),
      );
    }

    List<Widget> options = [
          option(
            "",
            Icon(
              Icons.block_rounded,
              size: 20,
              color: getColor(context, "textLight"),
            ),
          ),
          for (MapEntry<String, IconData> entry in pocketIcons.entries)
            option(
              pocketIconPrefix + entry.key,
              Icon(
                entry.value,
                size: 22,
                color: (selected ?? "") == pocketIconPrefix + entry.key
                    ? dotIconColor(colour)
                    : getColor(context, "black"),
              ),
            ),
    ];
    // Even grid: the last row starts at the left like the others
    return PopupFramework(
      title: "icon".tr(),
      child: LayoutBuilder(builder: (context, constraints) {
        int columns = ((constraints.maxWidth + 10) / 56).floor().clamp(1, 99);
        double cellWidth = constraints.maxWidth / columns;
        return Wrap(
          runSpacing: 10,
          children: [
            for (Widget child in options)
              SizedBox(width: cellWidth, child: Center(child: child)),
          ],
        );
      }),
    );
  }
}
