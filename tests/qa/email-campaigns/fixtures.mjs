export const importPopulationCampaign = {
  id: 4361,
  status: 'paused',
  pause_reason: 'hygiene_validation_required',
  recipient_import: {
    status: 'completed',
    result: { total: 3, imported: 1, duplicates: 1, invalid: 1, suppressed: 0 },
  },
  preflight: {
    status: 'analysing',
    mode: 'enforce',
    counts_basis: 'current_unsent_recipients',
    counts: { total: 1, unchecked: 1 },
    can_recheck: true,
  },
};
export const mixedReputationSummary = {
  open_rate: 0,
  click_rate: 0,
  unsubscribe_rate: 0,
  delivered: 3,
  opened: 0,
  clicked: 0,
  temporary_bounced: 0,
  unknown_bounced: 0,
  unsubscribed: 0,
  delivery_evidence: {
    provider_confirmed: 0,
    direct_acceptance_only: 3,
    legacy_delivered_includes_acceptance: true,
  },
  sent: 4,
  permanent_bounced: 1,
  complained: 0,
  hard_bounce_rate: 100,
  complaint_rate: 0,
  reputation_coverage: {
    sent: 1,
    excluded_direct_sent: 3,
    scope: 'selected_ses_campaigns',
    official_ses_ratio: false,
  },
  rate_metadata: {
    hard_bounce_rate: {
      value: 100,
      numerator: 1,
      denominator: 1,
      basis: 'ses_accepted_recipients',
    },
    complaint_rate: {
      value: 0,
      numerator: 0,
      denominator: 1,
      basis: 'ses_accepted_recipients',
    },
  },
};
export const mixedReputationCampaigns = [
  {
    ...mixedReputationSummary,
    id: 4361,
    name: 'QA verificado',
    status: 'sent',
    delivery_mode: 'ses',
    sent: 1,
    delivered: 0,
    delivery_evidence: {
      provider_confirmed: 0,
      direct_acceptance_only: 0,
      legacy_delivered_includes_acceptance: false,
    },
  },
  {
    ...mixedReputationSummary,
    id: 4362,
    name: 'QA direto',
    status: 'sent',
    delivery_mode: 'direct_inbox',
    sent: 3,
    permanent_bounced: 0,
    hard_bounce_rate: null,
    complaint_rate: null,
    rate_metadata: {
      hard_bounce_rate: {
        value: null,
        numerator: 0,
        denominator: 0,
        basis: 'ses_accepted_recipients',
      },
      complaint_rate: {
        value: null,
        numerator: 0,
        denominator: 0,
        basis: 'ses_accepted_recipients',
      },
    },
    reputation_coverage: {
      sent: 0,
      excluded_direct_sent: 3,
      scope: 'selected_ses_campaigns',
      official_ses_ratio: false,
    },
  },
];
export const current = {
  sent: 1200,
  permanent_bounces: 18,
  temporary_bounces: 9,
  unknown_bounces: 4,
  complaints: 2,
  hard_bounce_rate: 1.5,
  complaint_rate: 0.17,
  evaluated_at: '2026-09-16T12:30:00Z',
  window_start: '2026-09-15T12:30:00Z',
  window_end: '2026-09-16T12:30:00Z',
};
export const protection = {
  state: 'paused',
  reason_code: 'reputation_guardrail',
  mode: 'enforce',
  scope: 'account',
  current,
  trigger: {
    at: '2026-09-15T09:15:00Z',
    reason_code: 'hard_bounce_rate',
    metrics: {
      sent: 800,
      permanent_bounces: 64,
      temporary_bounces: 7,
      unknown_bounces: 3,
      complaints: 1,
      hard_bounce_rate: 8,
      complaint_rate: 0.125,
    },
  },
  provider: { state: 'healthy', observed_at: '2026-09-16T12:25:00Z' },
  capabilities: { reevaluate: true, resume: false, override: true },
  domains: ['example.org'],
};
export const preflight = {
  mode: 'enforce',
  status: 'blocked',
  counts: {
    total: 120,
    ready: 60,
    protected: 10,
    invalid: 20,
    review: 10,
    unknown: 10,
    unchecked: 5,
    duplicate: 5,
  },
  issues_count: 4,
  can_recheck: true,
};
export const campaigns = [
  {
    id: 4361,
    name: 'QA — Proteção de reputação',
    status: 'paused',
    pause_reason: 'reputation_guardrail',
    protection,
    preflight,
  },
  {
    id: 4362,
    name: 'QA — Envio concluído',
    status: 'sent',
    protection: {
      ...protection,
      state: 'healthy',
      trigger: null,
      reason_code: null,
      capabilities: { reevaluate: true, resume: false },
    },
    preflight: { ...preflight, status: 'review', mode: 'warning' },
  },
  {
    id: 4363,
    name: 'QA — Pausa manual',
    status: 'paused',
    pause_reason: 'manual',
    protection: {
      ...protection,
      state: 'attention',
      reason_code: 'manual',
      trigger: null,
      capabilities: { reevaluate: true, resume: true },
    },
    preflight: { ...preflight, status: 'unknown', counts: null },
  },
].map(c => ({
  ...c,
  delivery_mode: 'ses',
  delivery_evidence: {
    provider_confirmed: 1150,
    direct_acceptance_only: 0,
    legacy_delivered_includes_acceptance: false,
  },
  sent: 1200,
  delivered: 1150,
  opened: 650,
  clicked: 150,
  permanent_bounced: 18,
  temporary_bounced: 9,
  unknown_bounced: 4,
  complained: 2,
  unsubscribed: 8,
  open_rate: 56.52,
  click_rate: 13.04,
  hard_bounce_rate: 1.5,
  unsubscribe_rate: 0.7,
}));
const statuses = [
  'hard_bounced',
  'delivered',
  'temporary_bounced',
  'unknown_bounced',
  'bounced',
  'suppressed',
  'complained',
  'unsubscribed',
  'preflight_invalid',
  'preflight_review',
  'preflight_unknown',
  'pending',
];
export const recipients = Array.from({ length: 120 }, (_, index) => {
  const status = statuses[index % statuses.length];
  return {
    id: index + 1,
    name:
      index === 0
        ? 'Destinatário sintético com nome excepcionalmente longo para verificar quebra de linha e acesso a todos os controles '.repeat(
            3
          )
        : index === 1
          ? 'مريم 山田 Zoë García — destinataire international '.repeat(8)
          : `Pessoa QA ${String(index + 1).padStart(3, '0')}`,
    email:
      index === 0
        ? `${'qa-destinatario-muito-longo-'.repeat(4)}001@example.org`
        : `qa-${String(index + 1).padStart(3, '0')}@example.org`,
    status,
    delivery_outcome: status === 'bounced' ? 'permanent' : undefined,
    reason_code:
      status === 'bounced'
        ? 'mailbox_not_found'
        : status === 'hard_bounced'
          ? 'permanent_bounce'
          : 'unknown_reason_SYNTHETIC_PRIVATE_MARKER',
    suppression_reason: status === 'suppressed' ? 'unsubscribed' : undefined,
    preflight_status: status.startsWith('preflight') ? status : undefined,
    attempts: 2,
    opens: index % 4,
    clicks: index % 3,
    sent_at: '2026-09-14T13:05:00Z',
    last_event_at: '2026-09-16T11:20:00Z',
    last_error: 'SYNTHETIC_PRIVATE_MARKER { provider: raw diagnostic }',
  };
});
export const issues = [
  'invalid_email',
  'domain_nxdomain',
  'domain_typo',
  'invalid_recipient',
].map((reason_code, index) => ({
  id: index + 1,
  row_number: index + 2,
  email: `issue-${index + 1}@example.org`,
  classification:
    reason_code === 'domain_typo' ? 'preflight_review' : 'preflight_invalid',
  reason_code,
  suggestion:
    reason_code === 'domain_typo' ? 'corrected@example.org' : undefined,
}));
export function filterRecipients(params) {
  const query = (params.get('q') || '').toLowerCase();
  return recipients.filter(
    row =>
      (!query || `${row.name} ${row.email}`.toLowerCase().includes(query)) &&
      (!params.get('status') || row.status === params.get('status')) &&
      (params.get('problem') !== 'true' ||
        !['pending', 'delivered'].includes(row.status))
  );
}
export function responseFor(url, method, state) {
  const path = url.pathname;
  const params = url.searchParams;
  const deliveryMode =
    state.scenario === 'direct' ||
    (state.scenario === 'mixed' && path.includes('/4362/'))
      ? 'direct_inbox'
      : 'ses';
  const evidence =
    deliveryMode === 'direct_inbox'
      ? {
          provider_confirmed: 0,
          direct_acceptance_only: 1150,
          legacy_delivered_includes_acceptance: true,
        }
      : campaigns[0].delivery_evidence;
  const ok = payload => ({ status: 200, json: { payload } });
  const error = status => ({
    status,
    json: {
      error_code: 'unknown_provider_code',
      error: 'SYNTHETIC_PRIVATE_MARKER raw provider diagnostic',
    },
  });
  if (path.endsWith('/ctwa_tracked_links')) return ok([]);
  if (method === 'POST') return error(503);
  if (path.endsWith('/reports')) {
    if (state.reportError) return error(500);
    let selected = (
      state.scenario === 'mixed-denominator'
        ? mixedReputationCampaigns
        : campaigns
    ).filter(
      c =>
        !params.get('campaign_id') || String(c.id) === params.get('campaign_id')
    );
    if (params.get('campaign_status'))
      selected = selected.filter(c =>
        params.get('campaign_status') === 'attention'
          ? c.status === 'paused'
          : c.status === params.get('campaign_status')
      );
    selected = selected.map(c => {
      const direct =
        state.scenario === 'direct' ||
        (['mixed', 'mixed-denominator'].includes(state.scenario) &&
          c.id === 4362);
      return {
        ...c,
        delivery_mode: direct ? 'direct_inbox' : 'ses',
        delivery_evidence: direct
          ? {
              provider_confirmed: 0,
              direct_acceptance_only: c.delivered,
              legacy_delivered_includes_acceptance: true,
            }
          : c.delivery_evidence,
      };
    });
    if (state.scenario === 'import-populations') {
      selected = selected.map(c =>
        c.id === 4361
          ? {
              ...c,
              ...importPopulationCampaign,
              protection: { state: 'unknown' },
            }
          : c
      );
    }
    const summary = { ...campaigns[0], delivery_evidence: evidence };
    if (state.scenario === 'mixed-denominator') {
      Object.assign(
        summary,
        params.get('campaign_id') ? selected[0] : mixedReputationSummary
      );
      if (!params.get('campaign_id')) delete summary.delivery_mode;
    }
    if (state.scenario === 'mixed') {
      delete summary.delivery_mode;
      for (const key of [
        'sent',
        'delivered',
        'opened',
        'clicked',
        'permanent_bounced',
        'temporary_bounced',
        'unknown_bounced',
        'complained',
        'unsubscribed',
      ])
        summary[key] = selected.reduce((total, c) => total + c[key], 0);
      summary.delivery_evidence = {
        provider_confirmed: selected.reduce(
          (total, c) => total + c.delivery_evidence.provider_confirmed,
          0
        ),
        direct_acceptance_only: selected.reduce(
          (total, c) => total + c.delivery_evidence.direct_acceptance_only,
          0
        ),
        legacy_delivered_includes_acceptance: selected.some(
          c => c.delivery_mode === 'direct_inbox'
        ),
      };
    }
    const health = structuredClone(selected[0] || campaigns[0]);
    if (state.scenario === 'unknown') {
      health.protection = {
        state: 'healthy',
        reason_code: 'unknown_reason_SYNTHETIC_PRIVATE_MARKER',
        capabilities: { reevaluate: true, resume: false },
      };
      health.preflight = { status: 'unknown' };
    }
    if (state.scenario === 'provider') {
      health.protection.provider.state = 'blocked';
      health.protection.capabilities.resume = true;
    }
    if (state.scenario === 'unfresh') {
      health.protection.current = null;
      health.protection.capabilities.resume = false;
    }
    return ok({
      summary: state.scenario === 'unknown' ? {} : summary,
      campaigns: selected,
      campaign_options: campaigns.map(({ id, name }) => ({ id, name })),
      protection: health.protection,
      preflight: health.preflight,
      meta: { count: selected.length },
    });
  }
  if (path.endsWith('/timeline'))
    return ok({
      delivery_mode: deliveryMode,
      series: [0, 1, 2].map(i => ({
        bucket: `2026-09-${14 + i}T00:00:00Z`,
        delivered: 120 + i * 40,
        open: 65 + i * 20,
        click: 10 + i * 5,
      })),
    });
  if (path.endsWith('/clicks'))
    return ok({
      clicks: [
        {
          url: 'https://example.org/synthetic',
          total_clicks: 150,
          unique_clicks: 100,
        },
      ],
    });
  if (path.endsWith('/import_issues/export'))
    return {
      status: 200,
      contentType: 'text/csv',
      body: 'email,reason_code\nissue-1@example.org,invalid_email\n',
    };
  if (path.endsWith('/import_issues'))
    return ok({
      issues,
      meta: { count: 4, current_page: 1, total_pages: 1, per_page: 50 },
    });
  if (path.endsWith('/recipients')) {
    if (state.recipientError) return error(500);
    const filtered = filterRecipients(params);
    const page = Number(params.get('page') || 1);
    const perPage = 5;
    return ok({
      recipients: filtered
        .slice((page - 1) * perPage, page * perPage)
        .map(row => ({ ...row, delivery_mode: deliveryMode })),
      meta: {
        delivery_mode: deliveryMode,
        count: filtered.length,
        current_page: page,
        total_pages: Math.ceil(filtered.length / perPage),
        per_page: perPage,
      },
    });
  }
  if (path.endsWith('/export'))
    return {
      status: 200,
      contentType: 'text/csv',
      body: `email,status\n${filterRecipients(params)
        .map(r => `${r.email},${r.status}`)
        .join('\n')}\n`,
    };
  return { status: 404, json: { error: 'Unmatched synthetic fixture' } };
}
