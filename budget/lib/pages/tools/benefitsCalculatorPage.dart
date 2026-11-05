import 'package:budget/functions.dart';
import 'package:budget/pages/tools/cdtSimulatorPage.dart';
import 'package:budget/struct/colombia.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/selectChips.dart';
import 'package:budget/widgets/settingsContainers.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Benefits math ----------------------------------------------------------------

// Transport aid goes to whoever earns up to this many minimum wages
const double transportAidMaxWages = 2;
// Salario integral starts at 10 minimum wages plus a 30% factor prestacional
const double integralSalaryMinWages = 13;

// Days worked between two dates, both included, on the 360 day calendar used
// for labor settlements: every month counts 30 days
int days360(DateTime start, DateTime end) {
  start = DateTime(start.year, start.month, start.day);
  end = DateTime(end.year, end.month, end.day);
  if (end.isBefore(start)) return 0;
  int startDay = start.day;
  int endDay = end.day;
  if (startDay == 31 || isLastDayOfFebruary(start)) startDay = 30;
  if (endDay == 31 || isLastDayOfFebruary(end)) endDay = 30;
  return (end.year - start.year) * 360 +
      (end.month - start.month) * 30 +
      (endDay - startDay) +
      1;
}

bool isLastDayOfFebruary(DateTime date) =>
    date.month == 2 && DateTime(date.year, 3, 1).subtract(Duration(days: 1)).day == date.day;

bool defaultsToTransportAid(double salary, int year) =>
    salary <= transportAidMaxWages * colombiaYear(year).minimumWage;

bool reachesIntegralSalary(double salary, int year) =>
    salary >= integralSalaryMinWages * colombiaYear(year).minimumWage;

// Prima de servicios and cesantías both use salary plus transport aid
double primaForDays(double salary, double aid, int days) =>
    (salary + aid) * days / 360;

double severanceForDays(double salary, double aid, int days) =>
    (salary + aid) * days / 360;

double severanceInterestForDays(double severance, int days) =>
    severance * days * severanceInterestRate / 360;

// 15 working days of salary a year, aid does not count
double vacationForDays(double salary, int days) => salary * days / 720;

class BenefitsResult {
  const BenefitsResult({
    required this.primaDays,
    required this.severanceDays,
    required this.vacationDays,
    required this.prima,
    required this.severance,
    required this.severanceInterest,
    required this.vacation,
    required this.integralSalary,
    this.primaPaymentDate,
    this.severanceDepositDate,
    this.severanceInterestDate,
  });
  final int primaDays;
  final int severanceDays;
  final int vacationDays;
  final double prima;
  final double severance;
  final double severanceInterest;
  final double vacation;
  final bool integralSalary;
  // Only known when working from dates
  final DateTime? primaPaymentDate;
  final DateTime? severanceDepositDate;
  final DateTime? severanceInterestDate;
}

// Days worked are counted per period: prima for the semester of the cutoff,
// cesantías for its year and vacaciones since the start
BenefitsResult benefitsBetweenDates({
  required double salary,
  required double aid,
  required DateTime start,
  required DateTime cutoff,
  bool integralSalary = false,
}) {
  DateTime semesterStart = DateTime(cutoff.year, cutoff.month <= 6 ? 1 : 7, 1);
  DateTime yearStart = DateTime(cutoff.year, 1, 1);
  int primaDays =
      days360(start.isAfter(semesterStart) ? start : semesterStart, cutoff);
  int severanceDays =
      days360(start.isAfter(yearStart) ? start : yearStart, cutoff);
  int vacationDays = days360(start, cutoff);
  return _benefits(
    salary: salary,
    aid: aid,
    primaDays: primaDays,
    severanceDays: severanceDays,
    vacationDays: vacationDays,
    integralSalary: integralSalary,
    primaPaymentDate: cutoff.month <= 6
        ? DateTime(cutoff.year, 6, 30)
        : DateTime(cutoff.year, 12, 20),
    severanceDepositDate: DateTime(cutoff.year + 1, 2, 14),
    severanceInterestDate: DateTime(cutoff.year + 1, 1, 31),
  );
}

// The same days for every benefit
BenefitsResult benefitsForDays({
  required double salary,
  required double aid,
  required int days,
  bool integralSalary = false,
}) {
  return _benefits(
    salary: salary,
    aid: aid,
    primaDays: days,
    severanceDays: days,
    vacationDays: days,
    integralSalary: integralSalary,
  );
}

BenefitsResult _benefits({
  required double salary,
  required double aid,
  required int primaDays,
  required int severanceDays,
  required int vacationDays,
  required bool integralSalary,
  DateTime? primaPaymentDate,
  DateTime? severanceDepositDate,
  DateTime? severanceInterestDate,
}) {
  // Salario integral already includes prima and cesantías
  double severance =
      integralSalary ? 0 : severanceForDays(salary, aid, severanceDays);
  return BenefitsResult(
    primaDays: primaDays,
    severanceDays: severanceDays,
    vacationDays: vacationDays,
    prima: integralSalary ? 0 : primaForDays(salary, aid, primaDays),
    severance: severance,
    severanceInterest:
        integralSalary ? 0 : severanceInterestForDays(severance, severanceDays),
    vacation: vacationForDays(salary, vacationDays),
    integralSalary: integralSalary,
    primaPaymentDate: primaPaymentDate,
    severanceDepositDate: severanceDepositDate,
    severanceInterestDate: severanceInterestDate,
  );
}

// Page -------------------------------------------------------------------------

enum _PeriodMode { dates, days }

class BenefitsCalculatorPage extends StatefulWidget {
  const BenefitsCalculatorPage({super.key});

  @override
  State<BenefitsCalculatorPage> createState() => _BenefitsCalculatorPageState();
}

class _BenefitsCalculatorPageState extends State<BenefitsCalculatorPage> {
  final TextEditingController salaryController = TextEditingController();
  final TextEditingController daysController = TextEditingController();
  _PeriodMode mode = _PeriodMode.dates;
  DateTime startDate = DateTime(DateTime.now().year, 1, 1);
  DateTime cutoffDate = DateTime.now();
  // Null follows the salary, otherwise what was picked
  bool? transportAidOverride;
  bool? integralSalaryOverride;

  @override
  void dispose() {
    salaryController.dispose();
    daysController.dispose();
    super.dispose();
  }

  Future<void> pickStartDate() async {
    DateTime? picked = await showCustomDatePicker(context, startDate);
    if (picked != null) setState(() => startDate = picked);
  }

  Future<void> pickCutoffDate() async {
    DateTime? picked = await showCustomDatePicker(context, cutoffDate);
    if (picked != null) setState(() => cutoffDate = picked);
  }

  String formatDate(DateTime date) =>
      getWordedDateShortMore(date, includeYear: true, showTodayTomorrow: false);

  @override
  Widget build(BuildContext context) {
    double? salary = parseToolNumber(salaryController.text);
    int year = mode == _PeriodMode.dates ? cutoffDate.year : DateTime.now().year;
    ColombiaYear figures = colombiaYear(year);
    bool canBeIntegral = salary != null && reachesIntegralSalary(salary, year);
    bool integralSalary = canBeIntegral && (integralSalaryOverride ?? true);
    bool getsAid = integralSalary
        ? false
        : transportAidOverride ??
            (salary != null && defaultsToTransportAid(salary, year));
    double aid = getsAid ? figures.transportAid : 0;
    int? days = parseToolNumber(daysController.text)?.round();

    BenefitsResult? result;
    if (salary != null && salary > 0) {
      if (mode == _PeriodMode.dates && !cutoffDate.isBefore(startDate)) {
        result = benefitsBetweenDates(
          salary: salary,
          aid: aid,
          start: startDate,
          cutoff: cutoffDate,
          integralSalary: integralSalary,
        );
      } else if (mode == _PeriodMode.days && days != null && days > 0) {
        result = benefitsForDays(
          salary: salary,
          aid: aid,
          days: days,
          integralSalary: integralSalary,
        );
      }
    }

    return PageFramework(
      title: "tools-benefits-title".tr(),
      dragDownToDismiss: true,
      horizontalPaddingConstrained: true,
      getExtraHorizontalPadding: (_) => 13,
      listWidgets: [
        ToolInputField(
          label: "tools-benefits-salary".tr(),
          hint: toolNumberToInput(figures.minimumWage),
          prefix: "\$ ",
          controller: salaryController,
          onChanged: (_) => setState(() {}),
        ),
        SelectChips<_PeriodMode>(
          items: _PeriodMode.values,
          allowMultipleSelected: false,
          wrapped: true,
          padding: EdgeInsetsDirectional.zero,
          getLabel: (_PeriodMode item) => item == _PeriodMode.dates
              ? "tools-benefits-by-dates".tr()
              : "tools-benefits-by-days".tr(),
          getSelected: (_PeriodMode item) => mode == item,
          onSelected: (_PeriodMode item) => setState(() => mode = item),
        ),
        SizedBox(height: 8),
        if (mode == _PeriodMode.dates) ...[
          SettingsContainer(
            title: "tools-benefits-start-date".tr(),
            description: formatDate(startDate),
            icon: Icons.event_rounded,
            onTap: pickStartDate,
            enableBorderRadius: true,
          ),
          SettingsContainer(
            title: "tools-benefits-cutoff-date".tr(),
            description: formatDate(cutoffDate),
            icon: Icons.event_available_rounded,
            onTap: pickCutoffDate,
            enableBorderRadius: true,
          ),
          if (cutoffDate.isBefore(startDate))
            ToolNote(text: "tools-benefits-dates-wrong".tr()),
        ] else
          ToolInputField(
            label: "tools-benefits-days-worked".tr(),
            hint: "360",
            suffix: "tools-days".tr(),
            controller: daysController,
            onChanged: (_) => setState(() {}),
          ),
        if (canBeIntegral)
          SettingsContainerSwitch(
            title: "tools-benefits-integral-salary".tr(),
            description: "tools-benefits-integral-salary-description".tr(),
            initialValue: integralSalary,
            onSwitched: (bool value) {
              setState(() => integralSalaryOverride = value);
            },
            enableBorderRadius: true,
          ),
        if (!integralSalary)
          SettingsContainerSwitch(
            title: "tools-benefits-transport-aid".tr(),
            description: "tools-benefits-transport-aid-description".tr(
              namedArgs: {"amount": formatToolMoney(context, figures.transportAid)},
            ),
            initialValue: getsAid,
            onSwitched: (bool value) {
              setState(() => transportAidOverride = value);
            },
            enableBorderRadius: true,
          ),
        if (result == null)
          ToolNote(text: "tools-benefits-fill-in".tr())
        else ...[
          ToolSectionTitle(text: "tools-results".tr()),
          if (result.integralSalary)
            ToolNote(text: "tools-benefits-integral-note".tr())
          else ...[
            ToolResultRow(
              label: "tools-benefits-prima".tr(),
              value: formatToolMoney(context, result.prima),
              description: "tools-benefits-prima-description".tr(
                    namedArgs: {"days": result.primaDays.toString()},
                  ) +
                  " " +
                  (result.primaPaymentDate == null
                      ? "tools-benefits-prima-paid".tr()
                      : "tools-benefits-paid-by".tr(namedArgs: {
                          "date": formatDate(result.primaPaymentDate!)
                        })),
            ),
            ToolResultRow(
              label: "tools-benefits-severance".tr(),
              value: formatToolMoney(context, result.severance),
              description: "tools-benefits-severance-description".tr(
                    namedArgs: {"days": result.severanceDays.toString()},
                  ) +
                  " " +
                  (result.severanceDepositDate == null
                      ? "tools-benefits-severance-paid".tr()
                      : "tools-benefits-deposited-by".tr(namedArgs: {
                          "date": formatDate(result.severanceDepositDate!)
                        })),
            ),
            ToolResultRow(
              label: "tools-benefits-severance-interest".tr(),
              value: formatToolMoney(context, result.severanceInterest),
              description: "tools-benefits-severance-interest-description"
                      .tr(namedArgs: {
                    "rate": formatToolPercent(severanceInterestRate),
                  }) +
                  " " +
                  (result.severanceInterestDate == null
                      ? "tools-benefits-severance-interest-paid".tr()
                      : "tools-benefits-paid-by".tr(namedArgs: {
                          "date": formatDate(result.severanceInterestDate!)
                        })),
            ),
          ],
          ToolResultRow(
            label: "tools-benefits-vacation".tr(),
            value: formatToolMoney(context, result.vacation),
            description: "tools-benefits-vacation-description".tr(
              namedArgs: {"days": result.vacationDays.toString()},
            ),
          ),
          ToolResultRow(
            label: "tools-benefits-total".tr(),
            value: formatToolMoney(
              context,
              result.prima +
                  result.severance +
                  result.severanceInterest +
                  result.vacation,
            ),
            highlight: true,
          ),
          ToolNote(text: "tools-benefits-termination-note".tr()),
        ],
      ],
    );
  }
}
