import 'package:budget/main.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/balancePages.dart';
import 'package:budget/pages/transactionsSearchPage.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/functions.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Map<Type, Action<Intent>> keyboardIntents = {
  EscapeIntent: CallbackAction<EscapeIntent>(
    onInvoke: (EscapeIntent intent) => {
      if (navigatorKey.currentState!.canPop())
        navigatorKey.currentState!.pop()
      else
        pageNavigationFrameworkKey.currentState!
            .changePage(0, switchNavbar: true)
    },
  ),
  Digit1Intent: CallbackAction<Digit1Intent>(
    onInvoke: (Digit1Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(0, switchNavbar: true)
    },
  ),
  Digit2Intent: CallbackAction<Digit2Intent>(
    onInvoke: (Digit2Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(1, switchNavbar: true)
    },
  ),
  Digit3Intent: CallbackAction<Digit3Intent>(
    onInvoke: (Digit3Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(2, switchNavbar: true)
    },
  ),
  Digit4Intent: CallbackAction<Digit4Intent>(
    onInvoke: (Digit4Intent intent) => {
      // we are on the root of navigation pages
      if (!navigatorKey.currentState!.canPop())
        pageNavigationFrameworkKey.currentState!
            .changePage(3, switchNavbar: true)
    },
  ),
  NewTransactionIntent: _RootOnlyAction<NewTransactionIntent>(() => pushRoute(
      navigatorKey.currentContext!,
      AddTransactionPage(routesToPopAfterDelete: RoutesToPopAfterDelete.None))),
  SearchIntent: _RootOnlyAction<SearchIntent>(
      () => pushRoute(navigatorKey.currentContext!, TransactionsSearchPage())),
  TransferIntent: _RootOnlyAction<TransferIntent>(
      () => pushRoute(navigatorKey.currentContext!, TransferBalancePage())),
  PrivacyIntent: _RootOnlyAction<PrivacyIntent>(() => togglePrivacyMode()),
};

bool isTypingInField() {
  BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

// Single key shortcuts (N, /, T, P). They only fire on the main pages with
// nothing open on top and never while typing, otherwise the key goes through.
class _RootOnlyAction<T extends Intent> extends Action<T> {
  _RootOnlyAction(this.onInvoked);
  final Function() onInvoked;

  @override
  bool isEnabled(T intent) =>
      navigatorKey.currentContext != null &&
      navigatorKey.currentState?.canPop() == false &&
      !isTypingInField();

  @override
  Object? invoke(T intent) => onInvoked();
}

Map<ShortcutActivator, Intent> shortcuts = {
  const CharacterActivator("n"): const NewTransactionIntent(),
  const CharacterActivator("/"): const SearchIntent(),
  const CharacterActivator("t"): const TransferIntent(),
  const CharacterActivator("p"): const PrivacyIntent(),
  LogicalKeySet(LogicalKeyboardKey.escape): const EscapeIntent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit1):
      const Digit1Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit2):
      const Digit2Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit3):
      const Digit3Intent(),
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit4):
      const Digit4Intent(),
};

class EscapeIntent extends Intent {
  const EscapeIntent();
}

class Digit1Intent extends Intent {
  const Digit1Intent();
}

class Digit2Intent extends Intent {
  const Digit2Intent();
}

class Digit3Intent extends Intent {
  const Digit3Intent();
}

class Digit4Intent extends Intent {
  const Digit4Intent();
}

class NewTransactionIntent extends Intent {
  const NewTransactionIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class TransferIntent extends Intent {
  const TransferIntent();
}

class PrivacyIntent extends Intent {
  const PrivacyIntent();
}
