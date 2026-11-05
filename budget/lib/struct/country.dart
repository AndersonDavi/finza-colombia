import 'package:budget/database/tables.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:drift/drift.dart';

// Where the user lives. Colombia turns on its taxes (4x1000 and the rest);
// any other country keeps plain pockets with no taxes
const String countryColombia = "CO";
const String countryOther = "other";
const List<String> countries = [countryColombia, countryOther];

bool livesInColombia() => appStateSettings["country"] == countryColombia;

// Only the onboarding moves the first pocket to pesos: later on the pocket
// already has transactions in its own currency
Future<void> setCountry(String country, {bool setCurrency = false}) async {
  await updateSettings("country", country, updateGlobalState: false);
  if (setCurrency == false || country != countryColombia) return;
  TransactionWallet? wallet = await database
      .getWalletInstanceOrNull(appStateSettings["selectedWalletPk"]);
  // Pesos are written 1.500.000 and have no cents in practice
  await updateSettings("customNumberFormat", true, updateGlobalState: false);
  await updateSettings("numberFormatDelimiter", ".", updateGlobalState: false);
  await updateSettings("numberFormatDecimal", ",", updateGlobalState: false);
  await updateSettings("numberFormatCurrencyFirst", true,
      updateGlobalState: true);
  if (wallet != null && (wallet.currency != "cop" || wallet.decimals != 0)) {
    await database.createOrUpdateWallet(
        wallet.copyWith(currency: Value("cop"), decimals: 0));
  }
}

// Decimals for a new pocket in the user's country
int defaultPocketDecimals() => livesInColombia() ? 0 : 2;
