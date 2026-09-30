import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import campaignEn from 'dashboard/i18n/locale/en/campaign.json';
import protectionEn from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
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
    messages: { en: { ...campaignEn, ...protectionEn } },
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
});
