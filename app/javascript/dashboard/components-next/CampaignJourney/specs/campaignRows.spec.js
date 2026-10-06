import {
  buildJourneyRows,
  filterChannels,
  filterJourneyRows,
} from '../campaignRows';

const data = {
  campaigns: [
    {
      id: 1,
      title: 'Renovação auto',
      campaign_type: 'one_off',
      campaign_status: 'active',
      scheduled_at: 1_800_000_000,
      inbox: { name: 'Oficial', channel_type: 'Channel::Whatsapp' },
    },
    {
      id: 2,
      title: 'Parcela',
      campaign_type: 'one_off',
      campaign_status: 'completed',
      scheduled_at: 1_700_000_000,
      inbox: {
        name: 'Twilio',
        channel_type: 'Channel::TwilioSms',
        medium: 'sms',
      },
    },
    {
      id: 3,
      title: 'Twilio WhatsApp',
      campaign_type: 'one_off',
      campaign_status: 'active',
      inbox: { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
    },
    {
      id: 4,
      title: 'Boas-vindas',
      campaign_type: 'ongoing',
      enabled: true,
      inbox: { name: 'Site', channel_type: 'Channel::WebWidget' },
    },
  ],
  whatsappApiCampaigns: [
    {
      id: 7,
      title: 'Vistoria',
      status: 'running',
      sent_count: 3,
      recipients_count: 10,
      scheduled_at: '2026-10-01T10:00:00Z',
      inbox: { name: 'API' },
    },
  ],
  emailCampaigns: [
    {
      id: 9,
      name: 'Novidades',
      status: 'draft',
      from_email: 'news@example.com',
    },
  ],
};

describe('Campanha list rows (PRD §6.1)', () => {
  it('aggregates every channel and keeps Twilio WhatsApp out of SMS (M4)', () => {
    const rows = buildJourneyRows(data);

    expect(rows.map(row => [row.channel, row.name, row.status])).toEqual([
      ['whatsapp_official', 'Renovação auto', 'scheduled'],
      ['whatsapp_api', 'Vistoria', 'sending'],
      ['sms', 'Parcela', 'completed'],
      ['live_chat', 'Boas-vindas', 'always_on'],
      ['email', 'Novidades', 'draft'],
    ]);
  });

  it('each row opens the Resultado of its campaign; Chat ao vivo opens its journey page (#1007, #1008)', () => {
    const routes = Object.fromEntries(
      buildJourneyRows(data).map(row => [row.channel, row.route])
    );
    const result = (channel, campaignId) => ({
      name: 'campaigns_journey_result',
      params: { channel, campaignId },
    });

    expect(routes.whatsapp_official).toEqual(result('whatsapp_official', 1));
    expect(routes.sms).toEqual(result('sms', 2));
    expect(routes.whatsapp_api).toEqual(result('whatsapp_api', 7));
    expect(routes.email).toEqual(result('email', 9));
    expect(routes.live_chat).toEqual({
      name: 'campaigns_journey_live_chat_edit',
      params: { campaignId: 4 },
    });
  });

  it('filters by channel, status and search', () => {
    const rows = buildJourneyRows(data);

    expect(
      filterJourneyRows(rows, { channel: 'sms' }).map(row => row.name)
    ).toEqual(['Parcela']);
    expect(
      filterJourneyRows(rows, { status: 'draft' }).map(row => row.name)
    ).toEqual(['Novidades']);
    expect(
      filterJourneyRows(rows, { search: 'news@' }).map(row => row.name)
    ).toEqual(['Novidades']);
    expect(filterJourneyRows(rows)).toHaveLength(rows.length);
  });

  it('SMS disconnected with an old campaign: the campaign stays listed and SMS stays a filter', () => {
    const rows = buildJourneyRows(data);
    const connectedWithoutSms = ['live_chat'];

    expect(filterJourneyRows(rows).map(row => row.channel)).toContain('sms');
    expect(filterChannels(rows, connectedWithoutSms)).toContain('sms');
  });

  it('filter chips: connected channels plus channels that still have campaigns, in display order', () => {
    expect(filterChannels([], ['sms', 'email'])).toEqual(['email', 'sms']);
    expect(
      filterChannels([{ channel: 'whatsapp_api' }], ['live_chat'])
    ).toEqual(['whatsapp_api', 'live_chat']);
    expect(filterChannels([], [])).toEqual([]);
  });
});
