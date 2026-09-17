import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  campaigns,
  recipients,
  preflight,
  responseFor,
  importPopulationCampaign,
  mixedReputationSummary,
} from './fixtures.mjs';

const origin = 'http://127.0.0.1:3437/api/v1/accounts/436/email_campaigns';

test('synthetic universe and preflight counters remain reconciled', () => {
  assert.equal(campaigns.length, 3);
  assert.equal(recipients.length, 120);
  assert.equal(
    recipients.every(row => row.email.endsWith('@example.org')),
    true
  );
  const { total, ...counts } = preflight.counts;
  assert.equal(
    Object.values(counts).reduce((sum, value) => sum + value, 0),
    total
  );
  const selected = responseFor(
    new URL(`${origin}/reports?campaign_id=4362`),
    'GET',
    {}
  );
  assert.equal(selected.json.payload.campaigns.length, 1);
  assert.equal(selected.json.payload.campaign_options.length, 3);
});

test('combined filters keep page 2 separate from full CSV export', () => {
  const query = 'q=qa-&status=hard_bounced&problem=true';
  const rows = responseFor(
    new URL(`${origin}/reports/4361/recipients?${query}&page=2`),
    'GET',
    {}
  ).json.payload;
  assert.equal(rows.meta.count, 10);
  assert.equal(rows.meta.current_page, 2);
  assert.equal(rows.recipients.length, 5);
  assert.equal(rows.recipients[0].id, 61);
  const csv = responseFor(
    new URL(`${origin}/reports/4361/export?${query}`),
    'GET',
    {}
  ).body;
  assert.equal(csv.trim().split('\n').length, 11);
});

test('existing report/recipient HTTP 500 and action HTTP 503 cases are preserved', () => {
  assert.equal(
    responseFor(new URL(`${origin}/reports`), 'GET', { reportError: true })
      .status,
    500
  );
  assert.equal(
    responseFor(new URL(`${origin}/reports/4361/recipients`), 'GET', {
      recipientError: true,
    }).status,
    500
  );
  for (const action of ['reevaluate', 'recheck', 'resume']) {
    assert.equal(
      responseFor(new URL(`${origin}/campaigns/4361/${action}`), 'POST', {})
        .status,
      503
    );
  }
  assert.equal(
    responseFor(new URL(`${origin}/reports/4361/import_issues`), 'GET', {}).json
      .payload.issues.length,
    4
  );
});

test('manual/provider conflict deliberately retains resume:true to challenge UI safety', () => {
  const payload = responseFor(
    new URL(`${origin}/reports?campaign_id=4363`),
    'GET',
    { scenario: 'provider' }
  ).json.payload;
  assert.equal(payload.campaigns[0].pause_reason, 'manual');
  assert.equal(payload.protection.provider.state, 'blocked');
  assert.equal(payload.protection.capabilities.resume, true);
  assert.equal(campaigns[2].protection.provider.state, 'healthy');
});

for (const [scenario, mode, confirmed, direct] of [
  [undefined, 'ses', 1150, 0],
  ['direct', 'direct_inbox', 0, 1150],
]) {
  test(`delivery provenance and count conservation: ${scenario || 'ses'}`, () => {
    const state = { scenario };
    const report = responseFor(
      new URL(`${origin}/reports?campaign_id=4361`),
      'GET',
      state
    ).json.payload;
    assert.equal(
      report.summary.delivery_evidence.provider_confirmed,
      confirmed
    );
    assert.equal(
      report.summary.delivery_evidence.direct_acceptance_only,
      direct
    );
    assert.equal(confirmed + direct, report.summary.delivered);
    assert.equal(report.campaigns[0].delivery_mode, mode);
    const timeline = responseFor(
      new URL(`${origin}/reports/4361/timeline`),
      'GET',
      state
    ).json.payload;
    assert.equal(timeline.delivery_mode, mode);
    assert.deepEqual(
      timeline.series.map(row => row.delivered),
      [120, 160, 200]
    );
    const rows = responseFor(
      new URL(`${origin}/reports/4361/recipients?status=delivered`),
      'GET',
      state
    ).json.payload;
    assert.equal(rows.meta.delivery_mode, mode);
    assert.equal(rows.meta.count, 10);
    assert(
      rows.recipients.every(
        row => row.status === 'delivered' && row.delivery_mode === mode
      )
    );
    const csv = responseFor(
      new URL(`${origin}/reports/4361/export?status=delivered`),
      'GET',
      state
    ).body;
    assert.equal(csv.trim().split('\n').length, 11);
    assert(
      csv
        .trim()
        .split('\n')
        .slice(1)
        .every(row => row.endsWith(',delivered'))
    );
  });
}

test('unknown report has no fabricated delivery evidence', () => {
  const report = responseFor(new URL(`${origin}/reports`), 'GET', {
    scenario: 'unknown',
  }).json.payload;
  assert.deepEqual(report.summary, {});
});

test('mixed fixture summary conserves both source counts across campaigns', () => {
  const payload = responseFor(new URL(`${origin}/reports`), 'GET', {
    scenario: 'mixed',
  }).json.payload;
  assert.equal(payload.summary.delivered, 3450);
  assert.deepEqual(payload.summary.delivery_evidence, {
    provider_confirmed: 2300,
    direct_acceptance_only: 1150,
    legacy_delivered_includes_acceptance: true,
  });
  assert.equal(
    payload.campaigns.reduce((sum, c) => sum + c.delivered, 0),
    payload.summary.delivered
  );
  assert.equal(payload.campaigns[1].delivery_mode, 'direct_inbox');
  const timeline = responseFor(
    new URL(`${origin}/reports/4362/timeline`),
    'GET',
    { scenario: 'mixed' }
  ).json.payload;
  assert.equal(timeline.delivery_mode, 'direct_inbox');
});

test('original import rows remain distinct from the current unsent population', () => {
  const payload = responseFor(
    new URL(`${origin}/reports?campaign_id=4361`),
    'GET',
    { scenario: 'import-populations' }
  ).json.payload;
  assert.deepEqual(
    payload.campaigns[0].recipient_import,
    importPopulationCampaign.recipient_import
  );
  assert.deepEqual(payload.preflight.counts, { total: 1, unchecked: 1 });
  assert.equal(Object.hasOwn(payload.preflight.counts, 'duplicate'), false);
  assert.equal(
    payload.campaigns[0].pause_reason,
    'hygiene_validation_required'
  );
});
test('mixed reputation fixture uses one SES acceptance rather than four total sends', () => {
  const payload = responseFor(new URL(`${origin}/reports`), 'GET', {
    scenario: 'mixed-denominator',
  }).json.payload;
  assert.equal(
    payload.campaigns.reduce((sum, c) => sum + c.sent, 0),
    4
  );
  assert.equal(payload.campaigns[0].delivery_mode, 'ses');
  assert.equal(payload.campaigns[1].delivery_mode, 'direct_inbox');
  Object.entries(mixedReputationSummary).forEach(([key, value]) => {
    assert.deepEqual(payload.summary[key], value);
  });
});
