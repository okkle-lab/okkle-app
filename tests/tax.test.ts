import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { calcDeduction, mileageRate } from '../src/db/tax';
import { class4Nic, compareMethods, incomeTax, taxPosition } from '../src/db/taxcalc';

function closeTo(actual: number, expected: number, precision = 0.01) {
  assert.ok(
    Math.abs(actual - expected) <= precision,
    `expected ${actual} to be within ${precision} of ${expected}`,
  );
}

describe('HMRC mileage deductions', () => {
  it('uses the pre-2026 car rate for historical records', () => {
    closeTo(calcDeduction(100, 'car', 0, new Date('2026-04-05T12:00:00Z')), 45);
  });

  it('uses the 2026/27 car and van first-10,000-mile rate', () => {
    closeTo(calcDeduction(100, 'car', 0, new Date('2026-04-06T12:00:00Z')), 55);
    closeTo(calcDeduction(100, 'van', 0, new Date('2026-04-06T12:00:00Z')), 55);
  });

  it('splits a car deduction across the 10,000-mile threshold', () => {
    closeTo(calcDeduction(100, 'car', 9950, new Date('2026-04-06T12:00:00Z')), 40);
    closeTo(mileageRate('car', 10000, new Date('2026-04-06T12:00:00Z')), 0.25);
  });

  it('keeps motorbike mileage flat across the threshold', () => {
    closeTo(calcDeduction(100, 'motorbike', 12000, new Date('2026-04-06T12:00:00Z')), 24);
  });
});

describe('UK self-employment tax estimates', () => {
  it('calculates rUK income tax bands and personal allowance', () => {
    closeTo(incomeTax(12570, 'ruk'), 0);
    closeTo(incomeTax(50270, 'ruk'), 7540);
    closeTo(incomeTax(60000, 'ruk'), 11432);
  });

  it('calculates Scottish 2026/27 bands', () => {
    closeTo(incomeTax(50000, 'scotland'), 8982.05);
  });

  it('calculates Class 4 NIC at main and upper rates', () => {
    closeTo(class4Nic(12570), 0);
    closeTo(class4Nic(50270), 2262);
    closeTo(class4Nic(60000), 2456.6);
  });

  it('uses the trading allowance when it beats expenses', () => {
    const pos = taxPosition(3000, 200, 'ruk');

    assert.equal(pos.usesTradingAllowance, true);
    closeTo(pos.expenses, 1000);
    closeTo(pos.profit, 2000);
    closeTo(pos.totalDue, 0);
  });

  it('taxes courier profit on top of PAYE income and forecasts payments on account', () => {
    const pos = taxPosition(10000, 0, 'ruk', 30000);

    closeTo(pos.profit, 9000);
    closeTo(pos.incomeTax, 1800);
    closeTo(pos.totalDue, 1800);
    closeTo(pos.paymentOnAccount, 900);
  });

  it('suppresses payments on account when PAYE covers at least 80% of the liability', () => {
    const pos = taxPosition(5000, 0, 'ruk', 100000);

    closeTo(pos.incomeTax, 2400);
    closeTo(pos.totalDue, 2400);
    closeTo(pos.paymentOnAccount, 0);
  });

  it('compares simplified mileage with actual-cost vehicle deductions', () => {
    const result = compareMethods({
      businessMiles: 6000,
      personalMiles: 2000,
      runningCosts: 3000,
      vehicleValue: 10000,
      simplifiedDeduction: 2700,
    });

    closeTo(result.businessUsePct, 0.75);
    closeTo(result.capitalAllowance, 1350);
    closeTo(result.actual, 3600);
    assert.equal(result.recommended, 'actual');
    closeTo(result.difference, 900);
  });
});
