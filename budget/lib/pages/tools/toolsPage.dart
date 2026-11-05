import 'package:budget/pages/tools/aiChatPage.dart';
import 'package:budget/pages/tools/benefitsCalculatorPage.dart';
import 'package:budget/pages/tools/cdtSimulatorPage.dart';
import 'package:budget/pages/tools/incomeTaxPage.dart';
import 'package:budget/pages/tools/loanSimulatorPage.dart';
import 'package:budget/pages/tools/paymentsCenterPage.dart';
import 'package:budget/pages/tools/pilaCalculatorPage.dart';
import 'package:budget/pages/tools/rateCalculatorPage.dart';
import 'package:budget/struct/country.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Calculators and helpers around the user's money. The Colombian ones only
// show for people living there
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tool(String title, String description, IconData icon, Widget page) {
      return SettingsContainerOpenPage(
        openPage: page,
        title: title.tr(),
        description: description.tr(),
        icon: icon,
      );
    }

    return PageFramework(
      title: "tools".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      listWidgets: [
        SettingsHeader(title: "tools-section-money".tr()),
        tool("payments-center", "payments-center-description",
            Icons.event_available_rounded, PaymentsCenterPage()),
        tool("ai-chat", "ai-chat-description", Icons.auto_awesome_rounded,
            AiChatPage()),
        SettingsHeader(title: "tools-section-calculators".tr()),
        tool("tools-rate-calculator", "tools-rate-calculator-description",
            Icons.percent_rounded, RateCalculatorPage()),
        tool("tools-loan-simulator", "tools-loan-simulator-description",
            Icons.request_quote_rounded, LoanSimulatorPage()),
        tool("tools-cdt-title", "tools-cdt-description", Icons.savings_rounded,
            CdtSimulatorPage()),
        if (livesInColombia()) ...[
          SettingsHeader(title: "tools-section-colombia".tr()),
          tool("tax-title", "tax-description", Icons.account_balance_rounded,
              IncomeTaxPage()),
          tool("tools-benefits-title", "tools-benefits-description",
              Icons.work_rounded, BenefitsCalculatorPage()),
          tool("tools-pila-title", "tools-pila-description",
              Icons.health_and_safety_rounded, PilaCalculatorPage()),
        ],
        SizedBox(height: 50),
      ],
    );
  }
}
