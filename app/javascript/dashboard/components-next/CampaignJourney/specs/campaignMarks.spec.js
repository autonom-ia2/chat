import { flushPromises, mount } from '@vue/test-utils';
import CrmKanbanCard from 'dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue';
import { useCrmOrigin } from 'dashboard/routes/dashboard/crm/composables/useCrmOrigin';
import CampaignJourneyAPI from 'dashboard/api/campaignJourney';
import CrmOriginList from 'dashboard/routes/dashboard/crm/components/CrmOriginList.vue';
import ContactOriginsPanel from '../ContactOriginsPanel.vue';
import CampaignMessageLabel from '../CampaignMessageLabel.vue';
import ConversationCampaignMark from '../ConversationCampaignMark.vue';
import { resetCampaignNamesCache } from '../useCampaignNames';

// #1002 — campaign marks: card "+N" and order (K3), filter option labels (K6), contact panel
// "Origem e campanhas" (P1) and the campaign label of a campaign message (P2).
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: { value: 'en' },
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: [] }),
}));
vi.mock('dashboard/api/campaignJourney', () => ({
  default: { getContactOrigins: vi.fn(), getCampaignNames: vi.fn() },
}));

const LINK = {
  source: 'tracked_link',
  source_id: 'link:ABC234',
  headline: 'Feira 2026',
  touched_at: '2026-10-01T10:00:00Z',
};
const EMAIL = {
  source: 'campaign_email',
  source_id: 'campaign:email:3',
  headline: 'Novidades de outubro',
  touched_at: '2026-10-02T10:00:00Z',
};
const WHATSAPP = {
  source: 'campaign_whatsapp',
  source_id: 'campaign:whatsapp:7',
  headline: 'Renovação auto — outubro',
  touched_at: '2026-10-03T10:00:00Z',
};
const EXPECTED_SEQUENCE = [
  'CRM_KANBAN.ORIGIN.TRACKED_LINK: Feira 2026',
  'CRM_KANBAN.ORIGIN.CAMPAIGN_EMAIL: Novidades de outubro',
  'CRM_KANBAN.ORIGIN.CAMPAIGN_WHATSAPP: Renovação auto — outubro',
];

// Every touch in CrmOriginList (#1037), first to last; each row carries its label.
const sequenceTexts = wrapper =>
  wrapper.findAll('[data-crm-origin-touch]').map(item => item.text());

const expectSequence = (wrapper, expected) => {
  const rows = sequenceTexts(wrapper);
  expect(rows).toHaveLength(expected.length);
  expected.forEach((label, index) => expect(rows[index]).toContain(label));
};

describe('K3 — card with a link and two campaigns', () => {
  it('shows the first mark with +2 on the card', () => {
    const wrapper = mount(CrmKanbanCard, {
      props: {
        card: {
          id: 5,
          title: 'Ana',
          last_message_at: 1700000000,
          campaigns: [LINK, EMAIL, WHATSAPP],
        },
        stageColor: '#2563eb',
      },
      global: {
        stubs: {
          Avatar: true,
          ChannelIcon: true,
          CardPriorityIcon: true,
          CardLabels: true,
          SLACardLabel: true,
        },
      },
    });

    expect(wrapper.text()).toContain(EXPECTED_SEQUENCE[0]);
    expect(wrapper.text()).toContain('+2');
  });

  it('lists the three marks in order (drawer origin list)', () => {
    const { originFromCampaigns } = useCrmOrigin();
    const origin = originFromCampaigns([LINK, EMAIL, WHATSAPP]);

    const wrapper = mount(CrmOriginList, {
      props: { campaigns: [LINK, EMAIL, WHATSAPP] },
    });

    expect(origin.extraCount).toBe(2);
    expectSequence(wrapper, EXPECTED_SEQUENCE);
  });
});

describe('K6 — campaign filter options', () => {
  it('names campaign marks by channel and keeps other options as they were', () => {
    const { campaignOptionLabel } = useCrmOrigin();

    expect(campaignOptionLabel(WHATSAPP)).toBe(EXPECTED_SEQUENCE[2]);
    expect(campaignOptionLabel(EMAIL)).toBe(EXPECTED_SEQUENCE[1]);
    expect(campaignOptionLabel(LINK)).toBe('Feira 2026');
    // #993: live chat campaign of the website.
    expect(
      campaignOptionLabel({
        source: 'campaign_live_chat',
        source_id: 'campaign:live_chat:4',
        headline: 'Boas-vindas',
      })
    ).toBe('CRM_KANBAN.ORIGIN.CAMPAIGN_LIVE_CHAT: Boas-vindas');
    expect(campaignOptionLabel({ source: 'meta_ctwa', source_id: '123' })).toBe(
      '123'
    );
  });

  // #1004: a reply to an SMS campaign is its own origin, "Campanha SMS: <nome>".
  it('names SMS campaign marks and gives them their own icon', () => {
    const { campaignOptionLabel, originFromCampaign } = useCrmOrigin();
    const sms = {
      source: 'campaign_sms',
      source_id: 'campaign:sms:12',
      headline: 'Parcela outubro',
    };

    expect(campaignOptionLabel(sms)).toBe(
      'CRM_KANBAN.ORIGIN.CAMPAIGN_SMS: Parcela outubro'
    );
    expect(originFromCampaign(sms)).toMatchObject({
      source: 'campaign_sms',
      icon: 'i-lucide-message-square-text',
      labelKey: 'CRM_KANBAN.ORIGIN.CAMPAIGN_SMS',
    });
  });
});

describe('P1 — Origem e campanhas in the contact panel', () => {
  it('shows every mark of the contact in order and its audiences', async () => {
    CampaignJourneyAPI.getContactOrigins.mockResolvedValue({
      data: {
        payload: {
          marks: [LINK, EMAIL, WHATSAPP],
          audiences: [{ id: 1, name: 'Clientes auto' }],
        },
      },
    });

    const wrapper = mount(ContactOriginsPanel, {
      props: {
        contactId: 12,
        conversationAttributes: { campaign: LINK },
      },
    });
    await flushPromises();

    expect(CampaignJourneyAPI.getContactOrigins).toHaveBeenCalledWith(12);
    expect(wrapper.text()).toContain('CRM_KANBAN.ORIGIN_JOURNEY.TITLE');
    expectSequence(wrapper, EXPECTED_SEQUENCE);
    expect(wrapper.find('[data-test-id="contact-audiences"]').text()).toBe(
      'Clientes auto'
    );
  });

  it('keeps the marks of the open conversation when the request fails', async () => {
    CampaignJourneyAPI.getContactOrigins.mockRejectedValue(new Error('404'));

    const wrapper = mount(ContactOriginsPanel, {
      props: {
        contactId: 12,
        conversationAttributes: {
          campaign: LINK,
          campaign_touches: [LINK, EMAIL],
        },
      },
    });
    await flushPromises();

    expectSequence(wrapper, EXPECTED_SEQUENCE.slice(0, 2));
  });
});

describe('P2 — campaign message label', () => {
  beforeEach(() => resetCampaignNamesCache());

  it('shows the campaign name on a message sent by a campaign', async () => {
    CampaignJourneyAPI.getCampaignNames.mockResolvedValue({
      data: {
        payload: {
          campaigns: {},
          whatsapp_api_campaigns: { 4: 'Campanha WAHA' },
        },
      },
    });

    const wrapper = mount(CampaignMessageLabel, {
      props: { additionalAttributes: { whatsappApiCampaignId: 4 } },
    });
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await flushPromises();

    expect(CampaignJourneyAPI.getCampaignNames).toHaveBeenCalledWith({
      campaignIds: [],
      whatsappApiCampaignIds: ['4'],
    });
    expect(wrapper.text()).toBe(
      'CRM_KANBAN.ORIGIN_JOURNEY.CAMPAIGN_MESSAGE:{"name":"Campanha WAHA"}'
    );
  });

  it('renders nothing for a message without a campaign', () => {
    const wrapper = mount(CampaignMessageLabel, {
      props: { additionalAttributes: {} },
    });

    expect(
      wrapper.find('[data-test-id="campaign-message-label"]').exists()
    ).toBe(false);
  });
});

describe('P2 — WhatsApp Oficial campaign message', () => {
  beforeEach(() => resetCampaignNamesCache());

  it('shows the campaign and the template names', async () => {
    CampaignJourneyAPI.getCampaignNames.mockResolvedValue({
      data: {
        payload: {
          campaigns: { 7: 'Renovação auto — outubro' },
          whatsapp_api_campaigns: {},
        },
      },
    });

    const wrapper = mount(CampaignMessageLabel, {
      props: {
        additionalAttributes: {
          campaignId: 7,
          campaignTemplateName: 'renovacao',
        },
      },
    });
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    await flushPromises();

    expect(wrapper.text()).toBe(
      'CRM_KANBAN.ORIGIN_JOURNEY.CAMPAIGN_MESSAGE_TEMPLATE:{"name":"Renovação auto — outubro","template":"renovacao"}'
    );
  });
});

describe('D20 — campaign mark at the top of the conversation', () => {
  const markText = attributes =>
    mount(ConversationCampaignMark, { props: { attributes } })
      .find('[data-test-id="conversation-campaign-mark"]')
      .text();

  it('shows the first campaign mark of the conversation', () => {
    expect(
      markText({ campaign: LINK, campaign_touches: [LINK, EMAIL, WHATSAPP] })
    ).toContain(EXPECTED_SEQUENCE[1]);
  });

  it('shows the origin when the conversation has no campaign mark', () => {
    expect(markText({ campaign: LINK, campaign_touches: [LINK] })).toContain(
      EXPECTED_SEQUENCE[0]
    );
  });

  it('renders nothing for a conversation without marks', () => {
    const wrapper = mount(ConversationCampaignMark, {
      props: { attributes: {} },
    });

    expect(
      wrapper.find('[data-test-id="conversation-campaign-mark"]').exists()
    ).toBe(false);
  });
});
