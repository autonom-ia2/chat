import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import pt from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import {
  statusKey,
  canResumeCampaign,
  reasonKey,
  deliveryKey,
  RECIPIENT_STATUSES,
} from '../presentation';

describe.each(['en', 'pt_BR'])('email presentation (%s)', locale => {
  const { t } = createI18n({
    legacy: false,
    locale,
    messages: { en, pt_BR: pt },
  }).global;
  it('distinguishes permanent, nonexistent, temporary and unknown failures', () => {
    expect(
      statusKey({ status: 'bounced', delivery_outcome: 'permanent' })
    ).toBe('permanent');
    expect(
      statusKey({
        status: 'bounced',
        delivery_outcome: 'permanent',
        reason_code: 'mailbox_not_found',
      })
    ).toBe('nonexistent');
    expect(statusKey({ status: 'temporary_bounced' })).toBe('temporary');
    expect(statusKey({ status: 'bounced' })).toBe('bounce_unknown');
    expect(statusKey({ status: 'new_provider_value' })).toBe('unknown');
    expect(statusKey({ status: 'paused', pause_reason: 'manual' }, true)).toBe(
      'manual'
    );
    expect(
      statusKey({ status: 'paused', pause_reason: 'reputation' }, true)
    ).toBe('paused');
    expect(
      t(
        `EMAIL_CAMPAIGN_PROTECTION.STATUS.${statusKey({ status: 'complained' })}`
      )
    ).toBe(locale === 'pt_BR' ? 'Marcado como spam' : 'Marked as spam');
    expect(
      t(`EMAIL_CAMPAIGN_PROTECTION.REASON.${reasonKey('unsubscribed')}`)
    ).not.toContain('EMAIL_CAMPAIGN');
    expect(reasonKey('provider message with token')).toBe('unknown');
  });
});

describe('resume eligibility', () => {
  const protection = {
    state: 'paused',
    release_eligible: true,
    provider: { state: 'healthy' },
    capabilities: { resume: true },
  };
  it.each([undefined, null, {}, { capabilities: { resume: true } }])(
    'fails closed with missing or incomplete DTO %j, including manual pauses',
    dto => {
      expect(
        canResumeCampaign({
          status: 'paused',
          pause_reason: 'manual',
          protection: dto,
        })
      ).toBe(false);
    }
  );
  it('allows deliberate release without mutating the sticky pause', () => {
    const campaign = { status: 'paused', protection };
    const before = structuredClone(campaign);
    expect(canResumeCampaign(campaign)).toBe(true);
    expect(campaign).toEqual(before);
  });
  it.each([undefined, null, false, 'true', 1])(
    'requires explicit boolean release proof for a paused tenant (%j)',
    releaseEligible => {
      expect(
        canResumeCampaign({
          status: 'paused',
          protection: { ...protection, release_eligible: releaseEligible },
        })
      ).toBe(false);
    }
  );
  it.each([undefined, false, 'true', 1])(
    'requires explicit boolean resume capability (%j)',
    resume => {
      expect(
        canResumeCampaign({
          status: 'paused',
          protection: { ...protection, capabilities: { resume } },
        })
      ).toBe(false);
    }
  );
  it.each(['blocked', 'paused', 'disabled'])(
    'provider %s always wins over eligibility, override and manual pause',
    state => {
      ['paused', 'healthy', 'unknown'].forEach(accountState => {
        expect(
          canResumeCampaign({
            status: 'paused',
            pause_reason: 'manual',
            protection: {
              ...protection,
              state: accountState,
              provider: { state },
              capabilities: { resume: true, override: true },
            },
          })
        ).toBe(false);
      });
    }
  );
  it.each(['unknown', 'not_applicable', 'healthy'])(
    'accepts server-authorized manual resume with provider %s without SES release evidence',
    state => {
      expect(
        canResumeCampaign({
          status: 'paused',
          pause_reason: 'manual',
          protection: {
            ...protection,
            state: 'unknown',
            release_eligible: false,
            provider: { state },
          },
        })
      ).toBe(true);
    }
  );
  it.each(['sending', 'sent', 'draft', undefined])(
    'never resumes a campaign with status %s',
    status => expect(canResumeCampaign({ status, protection })).toBe(false)
  );
});

describe('real backend reason codes', () => {
  it.each([
    ['unsubscribe', 'unsubscribed'],
    ['temporary_failure', 'temporary'],
    ['mailbox_full', 'temporary'],
    ['permanent_failure', 'permanent'],
    ['provider_suppression', 'provider'],
    ['provider_manual_block', 'provider'],
    ['provider_telemetry_unknown', 'provider'],
    ['reputation_paused', 'reputation'],
    ['hygiene_validation_required', 'review'],
    ['invalid_email', 'invalid'],
    ['nxdomain', 'invalid'],
    ['null_mx', 'invalid'],
    ['no_mail_route', 'invalid'],
    ['invalid_recipient', 'review'],
    ['provider_typo', 'review'],
    ['dns_timeout', 'unknown'],
    ['undetermined_bounce', 'unknown'],
  ])(
    'maps %s to a localized explanation without reclassifying the mailbox',
    (code, expected) => {
      expect(reasonKey(code)).toBe(expected);
    }
  );
  it('presents valid preflight as completed analysis, not proof of a ready send', () => {
    expect(statusKey({ status: 'valid' })).toBe('completed');
    expect(statusKey({ status: 'pending', preflight_status: 'invalid' })).toBe(
      'pending'
    );
  });
});

describe('delivery provenance', () => {
  it.each([
    ['ses', 'delivered'],
    ['direct_inbox', 'accepted_service'],
    [undefined, 'acceptance_recorded'],
    [null, 'acceptance_recorded'],
    ['future_provider', 'acceptance_recorded'],
  ])('uses only explicit recipient source %s', (mode, expected) => {
    expect(statusKey({ status: 'delivered', delivery_mode: mode })).toBe(
      expected
    );
    // An unrelated delivery event does not change the current status.
    expect(statusKey({ status: 'sent', delivery_mode: mode })).toBe('sent');
    expect(statusKey({ status: 'opened', delivery_mode: mode })).toBe('opened');
  });
  it.each([
    [10, 0, false, 'delivered'],
    [0, 10, true, 'accepted_service'],
    [7, 3, true, 'acceptance_recorded'],
    [10, undefined, false, 'acceptance_recorded'],
    [10, 0, true, 'acceptance_recorded'],
    [10, 0, undefined, 'acceptance_recorded'],
    [7, 1, false, 'acceptance_recorded'],
  ])(
    'preserves aggregate counts and requires complete proof (%s, %s)',
    (confirmed, direct, includes, expected) => {
      const record = {
        delivered: 10,
        open_rate: 70,
        delivery_evidence: {
          provider_confirmed: confirmed,
          direct_acceptance_only: direct,
          legacy_delivered_includes_acceptance: includes,
        },
      };
      const before = structuredClone(record);
      expect(deliveryKey(record)).toBe(expected);
      expect(record).toEqual(before);
    }
  );
  it('retains API enum and conservatively labels absent evidence', () => {
    expect(deliveryKey({})).toBe('acceptance_recorded');
    expect(deliveryKey({ delivered: 10 })).toBe('acceptance_recorded');
    expect(RECIPIENT_STATUSES).toContain('delivered');
    expect(RECIPIENT_STATUSES).not.toContain('accepted_service');
    expect(RECIPIENT_STATUSES).not.toContain('acceptance_recorded');
  });
});
