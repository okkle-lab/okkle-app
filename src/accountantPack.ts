import * as Print from 'expo-print';
import * as FileSystem from 'expo-file-system';
import { shareFileAs } from './exportFile';
import {
  getUser, getTrips, getRecords, getTaxYearSummary, getTaxYearMiles,
  getTaxYearExpenses, kvGet, kvGetNum, kvSet, taxYearStart,
} from './db';
import { taxPosition, compareMethods, caRate } from './db/taxcalc';
import { fmtGbp, fmtMiles, taxYearLabel, vehicleLabel, regionLabel } from './db/tax';

const VEHICLE_COST_WORDS = /fuel|petrol|diesel|tyre|tire|mot|service|servicing|repair|insurance|road tax|breakdown|oil|brake|battery/i;

function esc(s: string): string {
  return (s ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string));
}

// UK date format DD/MM/YYYY from an ISO date/datetime string.
function ukDate(iso: string): string {
  const d = iso.slice(0, 10).split('-');
  return d.length === 3 ? `${d[2]}/${d[1]}/${d[0]}` : iso;
}

async function imageDataUri(uri: string | null): Promise<string | null> {
  if (!uri) return null;
  try {
    const b64 = await (FileSystem as any).readAsStringAsync(uri, { encoding: 'base64' });
    return `data:image/jpeg;base64,${b64}`;
  } catch {
    return null;
  }
}

export async function buildAccountantPackHtml(): Promise<string> {
  const user = getUser();
  const year = getTaxYearSummary();
  const bizMiles = getTaxYearMiles();
  const otherExpenses = getTaxYearExpenses();
  const start = taxYearStart();

  const method = compareMethods({
    businessMiles: bizMiles,
    personalMiles: kvGetNum('personal_miles'),
    runningCosts: kvGetNum('running_costs'),
    vehicleValue: kvGetNum('vehicle_value'),
    capitalAllowanceRate: caRate(kvGet('ca_basis') || 'low'),
    simplifiedDeduction: year.deduction,
  });
  const usingActual = kvGetNum('running_costs') > 0 && method.recommended === 'actual';
  const chosenDeduction = usingActual ? method.actual : method.simplified;
  const pos = taxPosition(year.earnings, chosenDeduction + otherExpenses, user?.region ?? 'ruk', kvGetNum('other_income'));

  const trips = getTrips(1000)
    .filter(t => t.started_at.slice(0, 10) >= start)
    .sort((a, b) => a.started_at.localeCompare(b.started_at));
  const records = getRecords(1000).filter(r => r.created_at.slice(0, 10) >= start);
  const income = records.filter(r => r.record_type === 'income');
  const expenses = records.filter(r => r.record_type === 'expense');

  // Income by platform (trips + manual income).
  const byPlatform: { [p: string]: number } = {};
  for (const t of trips) byPlatform[t.platform] = (byPlatform[t.platform] ?? 0) + (t.earnings ?? 0);
  for (const r of income) byPlatform[r.platform ?? 'Other'] = (byPlatform[r.platform ?? 'Other'] ?? 0) + (r.amount ?? 0);

  // Receipt images.
  const expenseRows = await Promise.all(expenses.map(async r => {
    const img = await imageDataUri(r.receipt_uri);
    const review = VEHICLE_COST_WORDS.test(`${r.category ?? ''} ${r.notes ?? ''}`);
    return { r, img, review };
  }));

  const mileageMilesTotal = trips.reduce((s, t) => s + t.miles, 0);
  const mileageDedTotal = trips.reduce((s, t) => s + t.deduction, 0);
  const mileageRows = trips.map(t => `
    <tr>
      <td>${ukDate(t.started_at)}</td>
      <td>${esc(vehicleLabel(t.vehicle))}</td>
      <td>${esc(t.platform)} delivery</td>
      <td class="num">${t.miles.toFixed(1)}</td>
      <td class="num">${fmtGbp(t.deduction)}</td>
    </tr>`).join('');

  const platformTotal = Object.values(byPlatform).reduce((s, v) => s + v, 0);
  const platformRows = Object.entries(byPlatform)
    .sort((a, b) => b[1] - a[1])
    .map(([p, amt]) => `<tr><td>${esc(p)}</td><td class="num">${fmtGbp(amt)}</td></tr>`).join('');

  const reviewItems = expenseRows.filter(x => x.review);
  const cleanExpenses = expenseRows.filter(x => !x.review);

  const expenseTable = (rows: typeof expenseRows) => {
    if (!rows.length) return '<p class="muted">None recorded.</p>';
    const total = rows.reduce((s, x) => s + (x.r.amount ?? 0), 0);
    return `
    <table>
      <thead><tr><th>Date</th><th>Description</th><th class="num">Amount</th><th>Receipt</th></tr></thead>
      <tbody>${rows.map(x => `
        <tr>
          <td>${ukDate(x.r.created_at)}</td>
          <td>${esc(x.r.category ?? x.r.notes ?? 'Expense')}</td>
          <td class="num">${fmtGbp(x.r.amount ?? 0)}</td>
          <td>${x.img ? '✓ attached' : '—'}</td>
        </tr>`).join('')}
      </tbody>
      <tfoot><tr><td colspan="2"><b>Total (${rows.length})</b></td><td class="num"><b>${fmtGbp(total)}</b></td><td></td></tr></tfoot>
    </table>`;
  };

  const receiptGallery = expenseRows.filter(x => x.img).map(x => `
    <div class="receipt">
      <div class="receipt-cap">${ukDate(x.r.created_at)} · ${esc(x.r.category ?? 'Expense')} · ${fmtGbp(x.r.amount ?? 0)}</div>
      <img src="${x.img}" />
    </div>`).join('');

  const today = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
  const periodEnd = `${parseInt(start.slice(0, 4), 10) + 1}-04-05`;
  const ref = `OK-${(user?.name ?? 'XX').slice(0, 2).toUpperCase()}-${taxYearLabel().replace('/', '')}`;

  return `<!DOCTYPE html><html><head><meta charset="utf-8" />
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #22302c; margin: 0; padding: 32px; font-size: 13px; line-height: 1.45; }
    h1 { font-size: 22px; margin: 0 0 6px; letter-spacing: -0.3px; }
    h2 { font-size: 15px; margin: 26px 0 10px; color: #0e8e78; border-bottom: 2px solid #e2f6f1; padding-bottom: 6px; page-break-after: avoid; }
    h3.ctrl { font-size: 13px; margin: 18px 0 6px; color: #22302c; page-break-after: avoid; }
    .sub { color: #6b756f; margin: 0 0 16px; }
    table { width: 100%; border-collapse: collapse; margin: 6px 0 4px; page-break-inside: auto; }
    tr { page-break-inside: avoid; }
    th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eee; vertical-align: top; }
    th { background: #f1efea; font-weight: 600; }
    thead { display: table-header-group; }
    tfoot td { border-top: 2px solid #d3d1c9; border-bottom: none; background: #faf9f6; }
    tr.strong td { background: #f6fcfa; }
    .box { color: #6b756f; font-variant-numeric: tabular-nums; width: 70px; }
    .num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
    .kv { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #eee; }
    .kv b { font-weight: 600; font-variant-numeric: tabular-nums; }
    .total { color: #0e8e78; font-weight: 700; }
    .muted { color: #a2aba5; }
    .badge { display: inline-block; background: #fbefd6; color: #b07a16; padding: 2px 8px; border-radius: 10px; font-size: 11px; vertical-align: middle; }
    .receipt { margin: 12px 0; page-break-inside: avoid; }
    .receipt-cap { font-size: 11px; color: #6b756f; margin-bottom: 4px; }
    .receipt img { max-width: 320px; max-height: 360px; border: 1px solid #ddd; border-radius: 6px; }
    .note { background: #f1efea; border-radius: 8px; padding: 14px; color: #6b756f; font-size: 11px; margin-top: 24px; line-height: 1.5; page-break-inside: avoid; }
    .cover { border-bottom: 3px solid #1fb89a; padding-bottom: 16px; margin-bottom: 8px; }
    .coverkv { display: grid; grid-template-columns: max-content 1fr; gap: 4px 16px; margin-top: 12px; font-size: 12px; }
    .coverkv span { color: #6b756f; }
    .coverkv b { font-weight: 600; }
  </style></head><body>

  <div class="cover">
    <h1>Self Assessment — Accountant Pack</h1>
    <p class="sub">${esc(user?.name ?? 'Courier')} · Sole trader (delivery courier)</p>
    <div class="coverkv">
      <span>Accounting period</span><b>${ukDate(start)} to ${ukDate(periodEnd)} (${taxYearLabel()})</b>
      <span>Reference</span><b>${esc(ref)}</b>
      <span>Prepared</span><b>${today}</b>
    </div>
  </div>

  <h2>Basis of preparation</h2>
  <div class="kv"><span>Tax region</span><b>${esc(regionLabel(user?.region ?? 'ruk'))}</b></div>
  <div class="kv"><span>Accounting basis</span><b>Cash basis</b></div>
  <div class="kv"><span>Mileage method</span><b>${usingActual ? 'Actual costs + capital allowances' : 'Simplified mileage (HMRC flat rate)'}</b></div>
  ${usingActual ? `<div class="kv"><span>Business-use proportion</span><b>${(method.businessUsePct * 100).toFixed(0)}%</b></div>` : ''}
  <div class="kv"><span>Rates basis</span><b>2025/26 HMRC rates</b></div>
  <div class="kv"><span>Records source</span><b>GPS trips and manual entries logged in Okkle</b></div>

  <h3 class="ctrl">Record counts (completeness check)</h3>
  <div class="kv"><span>GPS / mileage trips</span><b>${trips.length}</b></div>
  <div class="kv"><span>Income entries</span><b>${income.length}</b></div>
  <div class="kv"><span>Expense entries</span><b>${expenses.length} (${expenseRows.filter(x => x.img).length} with receipts)</b></div>

  <h2>Self Assessment summary (SA103S)</h2>
  <table>
    <thead><tr><th>SA103S box</th><th>Description</th><th class="num">Amount</th></tr></thead>
    <tbody>
      <tr><td class="box">9</td><td>Turnover — business income</td><td class="num">${fmtGbp(pos.turnover)}</td></tr>
      <tr><td class="box">${usingActual ? '17–30' : '20'}</td><td>Allowable business expenses${usingActual ? '' : ' (incl. simplified mileage)'}</td><td class="num">${fmtGbp(pos.expenses)}</td></tr>
      <tr class="strong"><td class="box">31</td><td>Net profit</td><td class="num total">${fmtGbp(pos.profit)}</td></tr>
    </tbody>
  </table>

  <h3 class="ctrl">Estimated tax &amp; National Insurance</h3>
  <div class="kv"><span>Income Tax</span><b>${fmtGbp(pos.incomeTax)}</b></div>
  <div class="kv"><span>Class 4 NIC</span><b>${fmtGbp(pos.class4)}</b></div>
  <div class="kv"><span>Estimated total due</span><b class="total">${fmtGbp(pos.totalDue)}</b></div>
  ${pos.paymentOnAccount > 0 ? `<div class="kv"><span>Payment on account (×2)</span><b>${fmtGbp(pos.paymentOnAccount)} each</b></div>` : ''}

  <h2>Income by platform</h2>
  <table>
    <thead><tr><th>Platform</th><th class="num">Amount</th></tr></thead>
    <tbody>${platformRows || '<tr><td colspan="2" class="muted">None recorded.</td></tr>'}</tbody>
    ${platformRows ? `<tfoot><tr><td><b>Total turnover</b></td><td class="num"><b>${fmtGbp(platformTotal)}</b></td></tr></tfoot>` : ''}
  </table>

  <h2>Mileage log</h2>
  <p class="sub">${fmtMiles(mileageMilesTotal)} business miles across ${trips.length} trips.</p>
  <table>
    <thead><tr><th>Date</th><th>Vehicle</th><th>Purpose</th><th class="num">Miles</th><th class="num">Deduction</th></tr></thead>
    <tbody>${mileageRows || '<tr><td colspan="5" class="muted">No trips recorded.</td></tr>'}</tbody>
    ${trips.length ? `<tfoot><tr><td colspan="3"><b>Total</b></td><td class="num"><b>${mileageMilesTotal.toFixed(1)}</b></td><td class="num"><b>${fmtGbp(mileageDedTotal)}</b></td></tr></tfoot>` : ''}
  </table>

  <h2>Expenses</h2>
  ${expenseTable(cleanExpenses)}

  ${reviewItems.length ? `
  <h2>Items flagged for your review <span class="badge">needs review</span></h2>
  <p class="sub">These appear to be vehicle running costs. Under the simplified method they are covered by the mileage rate and should not be claimed separately; under actual costs they may be claimable. Please advise on treatment.</p>
  ${expenseTable(reviewItems)}` : ''}

  ${receiptGallery ? `<h2>Receipts</h2>${receiptGallery}` : ''}

  <div class="note">
    <b>Basis &amp; limitations.</b> Prepared by Okkle from records kept on the client's device, on the cash basis,
    using 2025/26 HMRC rates. Figures are estimates derived solely from data the client logged; they have
    not been independently verified or reconciled to bank records, and do not constitute tax advice.
    The mileage deduction and the actual-cost figures are mutually exclusive — only one method applies per vehicle,
    and a vehicle on the actual-cost basis cannot revert to simplified. Please confirm completeness and all
    figures before submission.
  </div>

  </body></html>`;
}

export async function shareAccountantPack(): Promise<void> {
  const html = await buildAccountantPackHtml();
  const { uri } = await Print.printToFileAsync({ html });
  kvSet('pack_exported', 1); // unlocks the "Audit-ready" achievement
  // Re-share under a clear, dated filename instead of the random print name.
  await shareFileAs(uri, 'Accountant-Pack', 'pdf');
}
