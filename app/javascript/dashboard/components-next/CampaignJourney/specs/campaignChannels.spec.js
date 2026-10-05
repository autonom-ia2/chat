import fs from 'node:fs';
import path from 'node:path';
import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import CampaignChannelChooser from '../CampaignChannelChooser.vue';
import {
  CAMPAIGN_CHANNELS,
  CHANNEL_ORDER,
  connectedCampaignChannels,
} from '../campaignChannels';

const ALL_FEATURES = {
  emailCampaigns: true,
  whatsappCampaigns: true,
  whatsappApiCampaigns: true,
};

const INBOXES = {
  email: { channel_type: 'Channel::Email' },
  whatsappCloud: {
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  },
  whatsapp360: { channel_type: 'Channel::Whatsapp', provider: 'default' },
  whatsappApi: {
    channel_type: 'Channel::Api',
    additional_attributes: { campaign_channel_type: 'whatsapp_api' },
  },
  plainApi: { channel_type: 'Channel::Api', additional_attributes: {} },
  sms: { channel_type: 'Channel::Sms' },
  twilioSms: { channel_type: 'Channel::TwilioSms', medium: 'sms' },
  twilioWhatsapp: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
  website: { channel_type: 'Channel::WebWidget' },
};

describe('connectedCampaignChannels (PRD §8.10, M1–M2)', () => {
  it('shows nothing for an account without campaign inboxes', () => {
    expect(
      connectedCampaignChannels({ inboxes: [], features: ALL_FEATURES })
    ).toEqual([]);
  });

  it('lists every connected channel in display order', () => {
    expect(
      connectedCampaignChannels({
        inboxes: [
          INBOXES.website,
          INBOXES.sms,
          INBOXES.whatsappApi,
          INBOXES.whatsappCloud,
          INBOXES.email,
        ],
        features: ALL_FEATURES,
      })
    ).toEqual(CHANNEL_ORDER);
  });

  it('M1: SMS only with an SMS inbox (Channel::Sms or Twilio SMS), never Twilio WhatsApp', () => {
    const smsOf = inboxes =>
      connectedCampaignChannels({ inboxes, features: ALL_FEATURES }).includes(
        CAMPAIGN_CHANNELS.SMS
      );
    expect(smsOf([INBOXES.sms])).toBe(true);
    expect(smsOf([INBOXES.twilioSms])).toBe(true);
    expect(smsOf([INBOXES.twilioWhatsapp])).toBe(false);
    expect(smsOf([INBOXES.website])).toBe(false);
  });

  it('M2: WhatsApp Oficial needs the account feature and a WhatsApp Cloud inbox', () => {
    const official = (inboxes, features = ALL_FEATURES) =>
      connectedCampaignChannels({ inboxes, features }).includes(
        CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL
      );
    expect(official([INBOXES.whatsappCloud])).toBe(true);
    expect(official([INBOXES.whatsapp360])).toBe(false);
    expect(
      official([INBOXES.whatsappCloud], {
        ...ALL_FEATURES,
        whatsappCampaigns: false,
      })
    ).toBe(false);
  });

  it('M2: WhatsApp API needs the flag and an API inbox marked for campaigns', () => {
    const api = (inboxes, features = ALL_FEATURES) =>
      connectedCampaignChannels({ inboxes, features }).includes(
        CAMPAIGN_CHANNELS.WHATSAPP_API
      );
    expect(api([INBOXES.whatsappApi])).toBe(true);
    expect(api([INBOXES.plainApi])).toBe(false);
    expect(
      api([INBOXES.whatsappApi], {
        ...ALL_FEATURES,
        whatsappApiCampaigns: false,
      })
    ).toBe(false);
  });

  it('M2: e-mail needs the feature and a verified domain or an e-mail inbox', () => {
    const email = ({ inboxes = [], senderIdentities = [], features }) =>
      connectedCampaignChannels({
        inboxes,
        senderIdentities,
        features: features || ALL_FEATURES,
      }).includes(CAMPAIGN_CHANNELS.EMAIL);
    expect(email({ inboxes: [INBOXES.email] })).toBe(true);
    expect(email({ senderIdentities: [{ status: 'verified' }] })).toBe(true);
    expect(email({ senderIdentities: [{ status: 'pending' }] })).toBe(false);
    expect(
      email({
        inboxes: [INBOXES.email],
        features: { ...ALL_FEATURES, emailCampaigns: false },
      })
    ).toBe(false);
  });

  it('M2: Chat ao vivo only with a website inbox', () => {
    expect(
      connectedCampaignChannels({
        inboxes: [INBOXES.website],
        features: {},
      })
    ).toEqual([CAMPAIGN_CHANNELS.LIVE_CHAT]);
  });
});

describe('CampaignChannelChooser', () => {
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
    messages: { en: enJourney },
  });
  const mountChooser = channels =>
    mount(CampaignChannelChooser, {
      props: { channels },
      attachTo: document.body,
      global: { plugins: [i18n], stubs: { 'router-link': true } },
    });

  it('renders only the connected channels it receives', () => {
    const wrapper = mountChooser([
      CAMPAIGN_CHANNELS.WHATSAPP_OFFICIAL,
      CAMPAIGN_CHANNELS.SMS,
    ]);
    const buttons = wrapper.findAll('[data-channel]');

    expect(buttons.map(button => button.attributes('data-channel'))).toEqual([
      'whatsapp_official',
      'sms',
    ]);
    expect(wrapper.text()).toContain('WhatsApp Official');
    expect(wrapper.text()).not.toContain('Email');
    expect(wrapper.text()).not.toContain('Live chat');
    wrapper.unmount();
  });

  it('focuses the first channel, emits the choice and closes on Escape', async () => {
    const wrapper = mountChooser([CAMPAIGN_CHANNELS.EMAIL]);
    const button = wrapper.find('[data-channel="email"]');

    expect(document.activeElement).toBe(button.element);
    await button.trigger('click');
    expect(wrapper.emitted('choose')).toEqual([['email']]);
    await wrapper.find('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });

  it('without connected channels, points to connecting one instead of listing dead options', () => {
    const wrapper = mountChooser([]);

    expect(wrapper.findAll('[data-channel]')).toHaveLength(0);
    expect(wrapper.text()).toContain(
      'No campaign channel is connected to this account yet.'
    );
    wrapper.unmount();
  });
});

describe('G2: no native <select> in the journey screens', () => {
  it('keeps the new files free of native selects', () => {
    const root = path.join(process.cwd(), 'app/javascript/dashboard');
    const dirs = [
      path.join(root, 'components-next/CampaignJourney'),
      path.join(root, 'routes/dashboard/campaigns/journey'),
    ];
    const vueFiles = dirs.flatMap(dir =>
      fs
        .readdirSync(dir)
        .filter(file => file.endsWith('.vue'))
        .map(file => path.join(dir, file))
    );

    expect(vueFiles.length).toBeGreaterThan(0);
    vueFiles.forEach(file => {
      expect(fs.readFileSync(file, 'utf8').includes('<select')).toBe(false);
    });
  });
});
