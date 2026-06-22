import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import * as FileSystem from 'expo-file-system';
import {
  getUser, getTrips, getRecords, getTaxYearSummary, getTaxYearMiles,
  getTaxYearExpenses, kvGetNum, taxYearStart,
} from './db';
import { taxPosition, compareMethods } from './db/taxcalc';
import { fmtGbp, fmtMiles, taxYearLabel, vehicleLabel, regionLabel } from './db/tax';

const VEHICLE_COST_WORDS = /fuel|petrol|diesel|tyre|tire|mot|service|servicing|repair|insurance|road tax|breakdown|oil|brake|battery/i;

function esc(s: string): string {
  return (s ?? '').replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c] as string));
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

  const mileageRows = trips.map(t => `
    <tr>
      <td>${t.started_at.slice(0, 10)}</td>
      <td>${esc(vehicleLabel(t.vehicle))}</td>
      <td>${esc(t.platform)} delivery</td>
      <td class="num">${t.miles.toFixed(1)}</td>
      <td class="num">${t.deduction.toFixed(2)}</td>
    </tr>`).join('');

  const platformRows = Object.entries(byPlatform)
    .sort((a, b) => b[1] - a[1])
    .map(([p, amt]) => `<tr><td>${esc(p)}</td><td class="num">£${amt.toFixed(2)}</td></tr>`).join('');

  const reviewItems = expenseRows.filter(x => x.review);
  const cleanExpenses = expenseRows.filter(x => !x.review);

  const expenseTable = (rows: typeof expenseRows) => rows.length ? `
    <table>
      <thead><tr><th>Date</th><th>Description</th><th class="num">Amount</th><th>Receipt</th></tr></thead>
      <tbody>${rows.map(x => `
        <tr>
          <td>${x.r.created_at.slice(0, 10)}</td>
          <td>${esc(x.r.category ?? x.r.notes ?? 'Expense')}</td>
          <td class="num">£${(x.r.amount ?? 0).toFixed(2)}</td>
          <td>${x.img ? '✓ attached' : '—'}</td>
        </tr>`).join('')}
      </tbody>
    </table>` : '<p class="muted">None recorded.</p>';

  const receiptGallery = expenseRows.filter(x => x.img).map(x => `
    <div class="receipt">
      <div class="receipt-cap">${x.r.created_at.slice(0, 10)} · ${esc(x.r.category ?? 'Expense')} · £${(x.r.amount ?? 0).toFixed(2)}</div>
      <img src="${x.img}" />
    </div>`).join('');

  const today = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });

  return `<!DOCTYPE html><html><head><meta charset="utf-8" />
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #22302c; margin: 0; padding: 32px; font-size: 13px; }
    h1 { font-size: 24px; margin: 0 0 4px; }
    h2 { font-size: 15px; margin: 28px 0 10px; color: #0e8e78; border-bottom: 2px solid #e2f6f1; padding-bottom: 6px; }
    .sub { color: #6b756f; margin: 0 0 20px; }
    table { width: 100%; border-collapse: collapse; margin: 6px 0; }
    th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid #eee; }
    th { background: #f1efea; font-weight: 600; }
    .num { text-align: right; font-variant-numeric: tabular-nums; }
    .kv { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #eee; }
    .kv b { font-weight: 600; }
    .total { color: #0e8e78; font-weight: 700; font-size: 15px; }
    .muted { color: #a2aba5; }
    .badge { display: inline-block; background: #fbefd6; color: #b07a16; padding: 2px 8px; border-radius: 10px; font-size: 11px; }
    .receipt { margin: 12px 0; page-break-inside: avoid; }
    .receipt-cap { font-size: 11px; color: #6b756f; margin-bottom: 4px; }
    .receipt img { max-width: 320px; max-height: 360px; border: 1px solid #ddd; border-radius: 6px; }
    .note { background: #f1efea; border-radius: 8px; padding: 12px; color: #6b756f; font-size: 11px; margin-top: 24px; }
    .cover { border-bottom: 3px solid #1fb89a; padding-bottom: 16px; }
  </style></head><body>

  <div class="cover">
    <h1>Accountant Pack</h1>
    <p class="sub">${esc(user?.name ?? 'Courier')} · Tax year ${taxYearLabel()} · Prepared ${today}</p>
  </div>

  <h2>Assumptions</h2>
  <div class="kv"><span>Tax region</span><b>${esc(regionLabel(user?.region ?? 'ruk'))}</b></div>
  <div class="kv"><span>Mileage method</span><b>${usingActual ? 'Actual costs + capital allowances' : 'Simplified (HMRC flat rate)'}</b></div>
  ${usingActual ? `<div class="kv"><span>Business-use proportion</span><b>${(method.businessUsePct * 100).toFixed(0)}%</b></div>` : ''}
  <div class="kv"><span>Rates basis</span><b>2025/26</b></div>
  <div class="kv"><span>Records source</span><b>GPS trips and manual entries logged in Okkle</b></div>

  <h2>Self Assessment summary (SA103)</h2>
  <div class="kv"><span>Turnover (income)</span><b>${fmtGbp(pos.turnover)}</b></div>
  <div class="kv"><span>Allowable expenses</span><b>${fmtGbp(pos.expenses)}</b></div>
  <div class="kv"><span>Net profit</span><b class="total">${fmtGbp(pos.profit)}</b></div>
  <div class="kv"><span>Estimated Income Tax</span><b>${fmtGbp(pos.incomeTax)}</b></div>
  <div class="kv"><span>Estimated Class 4 NIC</span><b>${fmtGbp(pos.class4)}</b></div>
  <div class="kv"><span>Estimated total due</span><b class="total">${fmtGbp(pos.totalDue)}</b></div>
  ${pos.paymentOnAccount > 0 ? `<div class="kv"><span>Payment on account (×2)</span><b>${fmtGbp(pos.paymentOnAccount)} each</b></div>` : ''}

  <h2>Income by platform</h2>
  <table><thead><tr><th>Platform</th><th class="num">Amount</th></tr></thead><tbody>${platformRows || '<tr><td colspan="2" class="muted">None recorded.</td></tr>'}</tbody></table>

  <h2>Mileage log (${fmtMiles(bizMiles)} · ${trips.length} trips)</h2>
  <table>
    <thead><tr><th>Date</th><th>Vehicle</th><th>Purpose</th><th class="num">Miles</th><th class="num">Deduction £</th></tr></thead>
    <tbody>${mileageRows || '<tr><td colspan="5" class="muted">No trips recorded.</td></tr>'}</tbody>
  </table>

  <h2>Expenses</h2>
  ${expenseTable(cleanExpenses)}

  <h2>Items flagged for your review <span class="badge">needs review</span></h2>
  <p class="sub">These look like vehicle running costs. Under the simplified method they are covered by the mileage rate; under actual costs they may be claimable. Please advise.</p>
  ${expenseTable(reviewItems)}

  ${receiptGallery ? `<h2>Receipts</h2>${receiptGallery}` : ''}

  <div class="note">
    Prepared by Okkle from records kept on the client's device. Figures are estimates
    based on 2025/26 rates and the data logged; they are not tax advice and have not
    been independently verified. Please confirm all figures before submission.
  </div>

  </body></html>`;
}

export async function shareAccountantPack(): Promise<void> {
  const html = await buildAccountantPackHtml();
  const { uri } = await Print.printToFileAsync({ html });
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, { mimeType: 'application/pdf', dialogTitle: 'Accountant Pack' });
  }
}
