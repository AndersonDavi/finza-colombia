// Colombian figures that change every year. Each value says where it comes
// from; add the next year's values here when they are published.

class ColombiaYear {
  const ColombiaYear({
    required this.year,
    required this.uvt,
    required this.minimumWage,
    required this.transportAid,
  });
  final int year;
  // Unidad de Valor Tributario, set by the DIAN each December
  final double uvt;
  // Salario mínimo mensual legal vigente (SMMLV)
  final double minimumWage;
  // Auxilio de transporte, paid to whoever earns up to 2 minimum wages
  final double transportAid;
}

const Map<int, ColombiaYear> colombiaYears = {
  // UVT: Resolución DIAN 000193 de 2024. SMMLV: Decreto 1572 de 2024.
  // Auxilio: Decreto 1573 de 2024
  2025: ColombiaYear(
    year: 2025,
    uvt: 49799,
    minimumWage: 1423500,
    transportAid: 200000,
  ),
  // UVT: Resolución DIAN 000238 de 2025. SMMLV: Decreto 1469 de 2025.
  // Auxilio: Decreto 1470 de 2025
  2026: ColombiaYear(
    year: 2026,
    uvt: 52374,
    minimumWage: 1750905,
    transportAid: 249095,
  ),
};

// The values of the given year, or of the latest year known
ColombiaYear colombiaYear(int year) {
  if (colombiaYears.containsKey(year)) return colombiaYears[year]!;
  int latest = colombiaYears.keys.reduce((a, b) => a > b ? a : b);
  int earliest = colombiaYears.keys.reduce((a, b) => a < b ? a : b);
  return colombiaYears[year < earliest ? earliest : latest]!;
}

ColombiaYear currentColombiaYear() => colombiaYear(DateTime.now().year);

// Tasa de usura for consumer and ordinary credit, certified monthly by the
// Superintendencia Financiera. Noviembre 2026: Resolución 1707 de 2026
const double usuryRateEA = 28.34;
const double bankingCurrentRateEA = 18.89;
const String usuryRatePeriod = "noviembre 2026";

// Gravamen a los Movimientos Financieros (4x1000), art. 871 ET
const double gmfRate = 0.004;
// One account per person can be exempt up to this much a month, art. 879 ET
const double gmfExemptMonthlyUVT = 350;

// Retención en la fuente usually withheld on CDT interest
const double cdtWithholdingRate = 0.04;

// Who has to file the income tax return (personas naturales residentes),
// in UVT of the year being declared. Arts. 592 to 594-3 ET
const double filingGrossEquityUVT = 4500;
const double filingGrossIncomeUVT = 1400;
const double filingCreditCardUVT = 1400;
const double filingPurchasesUVT = 1400;
const double filingDepositsUVT = 1400;

// Rentas exentas y deducciones, Ley 2277 de 2022
const double laborExemptRate = 0.25; // art. 206 num. 10
const double laborExemptCapUVT = 790; // a year
const double exemptAndDeductionsCapRate = 0.40;
const double exemptAndDeductionsCapUVT = 1340; // a year
const double dependentDeductionUVT = 72; // each, up to 4, art. 336 num. 3
const int dependentDeductionMax = 4;
const double electronicInvoiceRate = 0.01; // art. 336 par. 5
const double electronicInvoiceCapUVT = 240;
const double housingInterestCapUVT = 1200; // a year, art. 119
const double prepaidHealthCapUVT = 192; // 16 a month, art. 387
const double voluntaryPensionRate = 0.30; // AFC / FPV, art. 126-1 and 126-4
const double voluntaryPensionCapUVT = 3800;

// Income tax table for personas naturales residentes, art. 241 ET, in UVT
class IncomeTaxBracket {
  const IncomeTaxBracket(this.fromUVT, this.rate, this.baseTaxUVT);
  final double fromUVT;
  final double rate;
  final double baseTaxUVT;
}

const List<IncomeTaxBracket> incomeTaxBrackets = [
  IncomeTaxBracket(0, 0, 0),
  IncomeTaxBracket(1090, 0.19, 0),
  IncomeTaxBracket(1700, 0.28, 116),
  IncomeTaxBracket(4100, 0.33, 788),
  IncomeTaxBracket(8670, 0.35, 2296),
  IncomeTaxBracket(18970, 0.37, 5901),
  IncomeTaxBracket(31000, 0.39, 10352),
];

// Tax in UVT for a taxable income in UVT
double incomeTaxUVT(double taxableUVT) {
  IncomeTaxBracket bracket = incomeTaxBrackets.first;
  for (IncomeTaxBracket b in incomeTaxBrackets) {
    if (taxableUVT > b.fromUVT) bracket = b;
  }
  return (taxableUVT - bracket.fromUVT) * bracket.rate + bracket.baseTaxUVT;
}

// Seguridad social for independientes: the contribution base is 40% of the
// monthly income, never below one minimum wage. Ley 1955 de 2019, art. 244
const double independentBaseRate = 0.40;
const double healthRate = 0.125;
const double pensionRate = 0.16;
// ARL by risk class I to V, Decreto 1772 de 1994
const List<double> arlRates = [0.00522, 0.01044, 0.02436, 0.0435, 0.0696];

// Interest on cesantías, Ley 52 de 1975
const double severanceInterestRate = 0.12;
