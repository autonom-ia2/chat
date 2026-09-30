import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { defineComponent, nextTick } from 'vue';
import campaignEn from 'dashboard/i18n/locale/en/campaign.json';
import protectionEn from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import recoveryEn from 'dashboard/i18n/locale/en/emailCampaignImportRecovery.json';
import RecipientImportStatus from '../../Pages/CampaignPage/EmailCampaign/RecipientImportStatus.vue';

const defaultPlugins = config.global.plugins;

beforeAll(() => {
  config.global.plugins = [];
});

afterAll(() => {
  config.global.plugins = defaultPlugins;
});

describe('RecipientImportStatus', () => {
  const i18n = createI18n({
    legacy: false,
    locale: 'en',
    messages: { en: { ...campaignEn, ...protectionEn, ...recoveryEn } },
  });
  const options = { global: { plugins: [i18n] } };

  it('shows the known import failure instead of the generic action error', () => {
    const wrapper = mount(RecipientImportStatus, {
      ...options,
      props: {
        campaign: {
          recipient_import: {
            status: 'failed',
            error_code: 'typesafe_unavailable',
          },
        },
      },
    });

    expect(wrapper.text()).toContain(
      campaignEn.CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.FAILED
    );
    expect(wrapper.text()).not.toContain(
      protectionEn.EMAIL_CAMPAIGN_PROTECTION.ERROR
    );
  });

  it('keeps the existing header guidance for header errors', () => {
    const wrapper = mount(RecipientImportStatus, {
      ...options,
      props: {
        campaign: {
          recipient_import: {
            status: 'failed',
            error_code: 'missing_email_header',
          },
        },
      },
    });

    expect(wrapper.text()).toContain(
      campaignEn.CAMPAIGN.EMAIL_CAMPAIGN.IMPORT.ERRORS.HEADERS
    );
  });

  it('opens a failure once, allows reopening, and opens again after a failed retry', async () => {
    const open = vi.fn();
    const close = vi.fn();
    const wrapper = mount(RecipientImportStatus, {
      ...options,
      props: {
        canRecover: true,
        autoRecover: true,
        campaign: {
          id: 50,
          status: 'draft',
          recipient_import: {
            id: 28,
            status: 'failed',
            error_code: 'schema_not_resolved',
          },
        },
      },
      global: {
        ...options.global,
        stubs: {
          RecipientImportRecoveryDialog: defineComponent({
            setup(_, { expose }) {
              expose({ open, close });
              return () => null;
            },
          }),
        },
      },
    });
    await nextTick();
    expect(open).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ campaign: { ...wrapper.props('campaign') } });
    expect(open).toHaveBeenCalledTimes(1);
    await wrapper.get('button').trigger('click');
    expect(open).toHaveBeenCalledTimes(2);
    await wrapper.setProps({
      campaign: {
        ...wrapper.props('campaign'),
        recipient_import: { id: 28, status: 'processing' },
      },
    });
    expect(close).toHaveBeenCalled();
    await wrapper.setProps({
      campaign: {
        ...wrapper.props('campaign'),
        recipient_import: { id: 28, status: 'failed' },
      },
    });
    await nextTick();
    expect(open).toHaveBeenCalledTimes(3);
    wrapper.unmount();
  });

  it('does not offer recovery to a read-only user or for a non-draft campaign', () => {
    [
      [false, 'draft'],
      [true, 'sent'],
    ].forEach(([canRecover, status]) => {
      const wrapper = mount(RecipientImportStatus, {
        ...options,
        props: {
          canRecover,
          autoRecover: true,
          campaign: { status, recipient_import: { id: 28, status: 'failed' } },
        },
      });
      expect(wrapper.find('button').exists()).toBe(false);
      wrapper.unmount();
    });
  });
});
