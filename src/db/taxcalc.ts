// UK tax estimates for self-employed couriers — 2025/26 figures.
// These are ESTIMATES to help users understand their position, not tax advice.

// The tax year these rates/allowances are confirmed for. The personal allowance
// and higher-rate threshold are frozen to 2027/28, and Class 4 NIC is unchanged,
// so these remain a sound basis for the current year — but we label them honestly.
export const RATES_YEAR = '2025/26';

export const PERSONAL_ALLOWANCE = 12570;
export const TRADING_ALLOWANCE = 1000;

// Class 4 NIC (2025/26): 6% between LPL and UPL, 2% above.
const CLASS4_LOWER = 12570;
const CLASS4_UPPER = 50270;
const CLASS4_MAIN = 0.06;
const CLASS4_UPPER_RATE = 0.02;
// Class 2 is no longer payable by most self-employed (profits >= this get the
// NI benefit without paying) since 2024/25.
const CLASS2_SMALL_PROFITS = 6725;

// Capital allowance bases (HMRC). Cars use writing-down allowances by CO2;
// new zero-emission cars get a 100% first-year allowance; vans and motorbikes
// are plant & machinery and qualify for the 100% Annual Investment Allowance.
export const CAPITAL_ALLOWANCE_BASES = [
  { key: 'ev', label: 'New electric car', sub: '100% first-year allowance', rate: 1.0 },
  { key: 'low', label: 'Low-emission car (≤50g/km)', sub: '18% writing-down', rate: 0.18 },
  { key: 'other', label: 'Other car (>50g/km)', sub: '6% writing-down', rate: 0.06 },
  { key: 'plant', label: 'Van or motorbike', sub: '100% (AIA)', rate: 1.0 },
] as const;

export function caRate(basis: string): number {
  return CAPITAL_ALLOWANCE_BASES.find(b => b.key === basis)?.rate ?? 0.18;
}

// --- Income tax: progressive bands ------------------------------------------

type Band = { upTo: number; rate: number };

// Bands are expressed on TAXABLE income (after personal allowance).
const RUK_BANDS: Band[] = [
  { upTo: 37700, rate: 0.20 },
  { upTo: 125140 - PERSONAL_ALLOWANCE, rate: 0.40 },
  { upTo: Infinity, rate: 0.45 },
];

// Scotland 2025/26 (taxable income after personal allowance).
const SCOT_BANDS: Band[] = [
  { upTo: 2827, rate: 0.19 },
  { upTo: 2827 + 12094, rate: 0.20 },
  { upTo: 2827 + 12094 + 16170, rate: 0.21 },
  { upTo: 125140 - PERSONAL_ALLOWANCE, rate: 0.42 },
  { upTo: Infinity, rate: 0.48 },
];

function personalAllowanceFor(income: number): number {
  // Tapers £1 for every £2 over £100,000.
  if (income <= 100000) return PERSONAL_ALLOWANCE;
  return Math.max(0, PERSONAL_ALLOWANCE - (income - 100000) / 2);
}

export function incomeTax(profit: number, region: string): number {
  const pa = personalAllowanceFor(profit);
  let taxable = Math.max(0, profit - pa);
  const bands = region === 'scotland' ? SCOT_BANDS : RUK_BANDS;
  let tax = 0;
  let prev = 0;
  for (const b of bands) {
    const slice = Math.min(taxable, b.upTo) - prev;
    if (slice > 0) { tax += slice * b.rate; prev = Math.min(taxable, b.upTo); }
    if (taxable <= b.upTo) break;
  }
  return Math.max(0, tax);
}

export function class4Nic(profit: number): number {
  if (profit <= CLASS4_LOWER) return 0;
  const main = Math.min(profit, CLASS4_UPPER) - CLASS4_LOWER;
  const upper = Math.max(0, profit - CLASS4_UPPER);
  return main * CLASS4_MAIN + upper * CLASS4_UPPER_RATE;
}

export function class2Note(profit: number): string {
  return profit >= CLASS2_SMALL_PROFITS
    ? 'Class 2 NIC: not payable — you get the National Insurance benefit for free.'
    : 'Class 2 NIC: optional voluntary contributions may protect your State Pension.';
}

// --- Method comparison: simplified vs actual costs --------------------------

export type MethodInput = {
  businessMiles: number;
  personalMiles: number;
  runningCosts: number;   // fuel, insurance, tax, repairs, servicing (annual)
  vehicleValue: number;   // for capital allowances
  capitalAllowanceRate?: number; // defaults to 18% main-rate WDA
  simplifiedDeduction: number;
};

export type MethodResult = {
  simplified: number;
  actual: number;
  businessUsePct: number;
  capitalAllowance: number;
  recommended: 'simplified' | 'actual';
  difference: number;
};

export function compareMethods(i: MethodInput): MethodResult {
  const totalMiles = i.businessMiles + i.personalMiles;
  const pct = totalMiles > 0 ? i.businessMiles / totalMiles : 1;
  const capitalAllowance = i.vehicleValue * (i.capitalAllowanceRate ?? 0.18) * pct;
  const actual = i.runningCosts * pct + capitalAllowance;
  const recommended = actual > i.simplifiedDeduction ? 'actual' : 'simplified';
  return {
    simplified: i.simplifiedDeduction,
    actual,
    businessUsePct: pct,
    capitalAllowance,
    recommended,
    difference: Math.abs(actual - i.simplifiedDeduction),
  };
}

// --- Full position ----------------------------------------------------------

export type TaxPosition = {
  turnover: number;
  expenses: number;
  profit: number;
  incomeTax: number;
  class4: number;
  totalDue: number;
  paymentOnAccount: number;
  usesTradingAllowance: boolean;
  effectiveRate: number;
};

export function taxPosition(turnover: number, expenses: number, region: string, otherIncome = 0): TaxPosition {
  // You can deduct either your actual expenses or the £1,000 trading allowance,
  // whichever is higher (you can't claim both).
  const useTrading = TRADING_ALLOWANCE > expenses;
  const deductible = Math.min(turnover, useTrading ? TRADING_ALLOWANCE : expenses);
  const profit = Math.max(0, turnover - deductible);
  // Self-employment profit stacks ON TOP of any other (e.g. PAYE) income, so it
  // is taxed at the marginal rate — tax on (other + profit) minus tax on other.
  const it = incomeTax(otherIncome + profit, region) - incomeTax(otherIncome, region);
  const c4 = class4Nic(profit);
  const totalDue = it + c4; // self-employed tax that is NOT collected at source
  // Payments on account are due only when BOTH HMRC conditions are met:
  //   (1) the Self Assessment bill is over £1,000, AND
  //   (2) less than 80% of your total tax was already collected at source (PAYE/CIS).
  // For a pure self-employed courier nothing is collected at source, so this is
  // just the £1,000 test (unchanged). Users with substantial PAYE income whose
  // tax is mostly collected at source are no longer over-warned.
  const totalLiability = incomeTax(otherIncome + profit, region) + c4;
  const taxAtSource = incomeTax(otherIncome, region); // ~tax already withheld via PAYE
  const collectedAtSourcePct = totalLiability > 0 ? taxAtSource / totalLiability : 0;
  const poa = totalDue > 1000 && collectedAtSourcePct < 0.8 ? totalDue * 0.5 : 0;
  return {
    turnover, expenses: deductible, profit,
    incomeTax: it, class4: c4, totalDue,
    paymentOnAccount: poa,
    usesTradingAllowance: useTrading,
    effectiveRate: turnover > 0 ? totalDue / turnover : 0,
  };
}
