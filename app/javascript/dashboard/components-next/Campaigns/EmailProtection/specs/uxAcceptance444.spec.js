import fs from 'node:fs';
import path from 'node:path';
import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enProtection from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import enCrm from 'dashboard/i18n/locale/en/crm.json';
import Badge from '../EmailStatusBadge.vue';
import Filter from '../EmailStatusFilter.vue';
import Panel from '../EmailProtectionPanel.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FilterSelect from 'dashboard/components-next/filter/inputs/FilterSelect.vue';
import {
  RECIPIENT_STATUSES,
  PROBLEM_STATUSES,
  displayStatusLabel,
} from '../presentation';

const defaultPlugins = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaultPlugins;
});

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: false,
  messages: { en: { ...enCrm, ...enProtection } },
});
const global = { plugins: [i18n] };
const t = i18n.global.t;

describe('issue #444 UX acceptance', () => {
  it('uses Chatwoot dropdowns and never native selects in the campaign management surface', () => {
    const root = process.cwd();
    const files = [
      path.join(
        root,
        'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue'
      ),
      path.join(
        root,
        'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailStatusFilter.vue'
      ),
      path.join(
        root,
        'app/javascript/dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue'
      ),
    ];
    files.forEach(file => {
      expect(fs.readFileSync(file, 'utf8')).not.toMatch(/<select\b/);
    });

    const wrapper = mount(Filter, {
      props: { modelValue: '' },
      global,
    });
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('keeps the main recipient filter to five decisions and reveals detail only in problem context', async () => {
    expect(RECIPIENT_STATUSES).toHaveLength(5);
    expect(RECIPIENT_STATUSES).toEqual([
      '',
      'pending',
      'delivered',
      'attention',
      'unsubscribed',
    ]);
    expect(PROBLEM_STATUSES).toEqual([
      'attention',
      'temporary_bounced',
      'hard_bounced',
      'complained',
      'preflight_invalid',
      'preflight_review',
    ]);

    const wrapper = mount(Filter, {
      props: { modelValue: '', problem: false },
      global,
    });
    expect(wrapper.text()).not.toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.temporary')
    );

    await wrapper.setProps({ modelValue: 'attention', problem: true });
    expect(
      wrapper
        .findComponent(FilterSelect)
        .props('options')
        .map(option => option.label)
    ).toContain(t('EMAIL_CAMPAIGN_PROTECTION.STATUS.temporary'));
  });

  it('keeps compact failure labels semantically truthful', () => {
    const permanent = displayStatusLabel(t, 'permanent');
    const unknown = displayStatusLabel(t, 'bounce_unknown');

    expect(permanent).not.toContain('—');
    expect(unknown).not.toContain('—');
    expect(unknown.toLowerCase()).toContain('not delivered');
    expect(unknown.toLowerCase()).toContain('reason not provided');
  });

  it('distinguishes temporary, permanent and spam problems by both color and icon', () => {
    const mountBadge = record => mount(Badge, { props: { record }, global });
    const temporary = mountBadge({
      status: 'bounced',
      delivery_outcome: 'temporary',
    });
    const permanent = mountBadge({
      status: 'bounced',
      delivery_outcome: 'permanent',
    });
    const spam = mountBadge({ status: 'complained' });

    expect(temporary.classes()).toContain('bg-n-amber-3');
    expect(permanent.classes()).toContain('bg-n-ruby-3');
    expect(spam.classes()).toContain('bg-n-ruby-3');

    expect(temporary.findComponent(Icon).props('icon')).toBe(
      'i-lucide-refresh-cw'
    );
    expect(permanent.findComponent(Icon).props('icon')).toBe(
      'i-lucide-circle-x'
    );
    expect(spam.findComponent(Icon).props('icon')).toBe(
      'i-lucide-shield-alert'
    );
    expect(permanent.findComponent(Icon).props('icon')).not.toBe(
      spam.findComponent(Icon).props('icon')
    );
    expect(temporary.text()).not.toContain('—');
    expect(permanent.text()).not.toContain('—');
  });

  it('keeps the protection summary concise, avoids placeholders and hides analysis-only copy while paused', async () => {
    const wrapper = mount(Panel, {
      props: {
        campaign: {
          id: 1,
          status: 'paused',
          pause_reason: 'reputation',
        },
        protection: {
          state: 'paused',
          mode: 'shadow',
          reason_code: 'reputation',
          capabilities: { reevaluate: true },
          current: {
            sent: 1804,
            permanent_bounces: 124,
            temporary_bounces: 130,
            complaints: 3,
            hard_bounce_rate: 6.87,
            complaint_rate: 0.17,
            evaluated_at: '2026-09-18T07:40:00Z',
          },
          trigger: {
            at: '2026-09-15T17:30:00Z',
            reason_code: 'hard_bounce_rate',
            metrics: {},
          },
        },
      },
      global,
    });

    expect(wrapper.find('h3').text()).toBe(
      t('EMAIL_CAMPAIGN_PROTECTION.STATUS.paused_unknown')
    );
    expect(wrapper.text()).not.toContain(
      t('EMAIL_CAMPAIGN_PROTECTION.ANALYSIS_ONLY')
    );
    expect(wrapper.text()).not.toContain('—');
    expect(wrapper.text()).not.toMatch(/\bSES\b|Amazon|AWS/);
    expect(wrapper.text()).toContain('1,804');
    expect(wrapper.text()).toContain('124');
    expect(wrapper.text()).toContain('130');
    expect(wrapper.text()).toContain('3');

    const current = wrapper.find('[data-section="CURRENT"]');
    const trigger = wrapper.find('[data-section="TRIGGER"]');
    expect(current.isVisible()).toBe(false);
    expect(trigger.isVisible()).toBe(false);

    expect(
      wrapper
        .findAll('button')
        .some(
          button => button.text() === t('EMAIL_CAMPAIGN_PROTECTION.DETAILS')
        )
    ).toBe(true);
  });

  it('keeps provider implementation names out of customer-facing production components', () => {
    const root = process.cwd();
    const files = [
      'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailProtectionPanel.vue',
      'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailRecipients.vue',
      'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailStatusBadge.vue',
      'app/javascript/dashboard/components-next/Campaigns/EmailProtection/EmailStatusFilter.vue',
      'app/javascript/dashboard/routes/dashboard/crm/pages/CrmCampaignManagementPage.vue',
    ].map(file => path.join(root, file));
    files.forEach(file => {
      const source = fs.readFileSync(file, 'utf8');
      expect(source).not.toMatch(/>[^<]*\b(?:SES|Amazon|AWS)\b[^<]*</);
      expect(source).not.toContain('HARD_RATE');
      expect(source).not.toContain('OVER_SENT');
    });
  });
});
