import { buildJourneyRows, WHEN_KINDS } from '../campaignRows';

// Date column of the Campanha list (#990): the most meaningful date for each status.
const CREATED = '2026-09-01T09:00:00Z';
const SCHEDULED = '2026-10-20T12:00:00Z';
const STARTED = '2026-09-15T13:30:00Z';
const FINISHED = '2026-09-16T08:00:00Z';
const time = value => new Date(value).getTime();

const emailRow = campaign =>
  buildJourneyRows({
    emailCampaigns: [
      { id: 1, name: 'HUB ACADEM.IA v3', created_at: CREATED, ...campaign },
    ],
  })[0];
const whatsappApiRow = campaign =>
  buildJourneyRows({
    whatsappApiCampaigns: [
      { id: 2, title: 'Vistoria', created_at: CREATED, ...campaign },
    ],
  })[0];
const officialRow = campaign =>
  buildJourneyRows({
    campaigns: [
      {
        id: 3,
        title: 'Renovação',
        campaign_type: 'one_off',
        inbox: { channel_type: 'Channel::Whatsapp' },
        created_at: CREATED,
        ...campaign,
      },
    ],
  })[0];
const smsRow = campaign =>
  buildJourneyRows({
    campaigns: [
      {
        id: 4,
        title: 'Parcela',
        campaign_type: 'one_off',
        inbox: { channel_type: 'Channel::Sms' },
        created_at: CREATED,
        ...campaign,
      },
    ],
  })[0];
const dateOf = row => [row.status, row.whenKind, row.when];

describe('Campanha list dates (#990)', () => {
  describe('e-mail', () => {
    it('paused after sending right away: when the first e-mail went out, not "Sem data"', () => {
      const row = emailRow({
        status: 'paused',
        scheduled_at: null,
        sent_at: null,
        started_at: STARTED,
        sent_count: 1804,
        recipients_count: 9265,
      });

      expect(dateOf(row)).toEqual([
        'paused',
        WHEN_KINDS.STARTED,
        time(STARTED),
      ]);
    });

    it('sending: when the first e-mail went out', () => {
      expect(
        dateOf(emailRow({ status: 'sending', started_at: STARTED }))
      ).toEqual(['sending', WHEN_KINDS.STARTED, time(STARTED)]);
    });

    it('sent: dated by the start of the send, falling back to its end', () => {
      expect(
        dateOf(
          emailRow({ status: 'sent', started_at: STARTED, sent_at: FINISHED })
        )
      ).toEqual(['completed', WHEN_KINDS.SENT, time(STARTED)]);
      expect(dateOf(emailRow({ status: 'sent', sent_at: FINISHED }))).toEqual([
        'completed',
        WHEN_KINDS.SENT,
        time(FINISHED),
      ]);
    });

    it('scheduled: the scheduled date', () => {
      expect(
        dateOf(emailRow({ status: 'scheduled', scheduled_at: SCHEDULED }))
      ).toEqual(['scheduled', WHEN_KINDS.SCHEDULED, time(SCHEDULED)]);
    });

    it('draft: the creation date', () => {
      expect(dateOf(emailRow({ status: 'draft' }))).toEqual([
        'draft',
        WHEN_KINDS.CREATED,
        time(CREATED),
      ]);
    });

    it('cancelled before any e-mail: the creation date; failed after some: the start', () => {
      expect(dateOf(emailRow({ status: 'canceled' }))).toEqual([
        'cancelled',
        WHEN_KINDS.CREATED,
        time(CREATED),
      ]);
      expect(
        dateOf(emailRow({ status: 'failed', started_at: STARTED }))
      ).toEqual(['failed', WHEN_KINDS.STARTED, time(STARTED)]);
    });
  });

  describe('WhatsApp API', () => {
    it('running and paused: started_at; completed: started_at, else completed_at', () => {
      expect(
        dateOf(whatsappApiRow({ status: 'running', started_at: STARTED }))
      ).toEqual(['sending', WHEN_KINDS.STARTED, time(STARTED)]);
      expect(
        dateOf(whatsappApiRow({ status: 'paused', started_at: STARTED }))
      ).toEqual(['paused', WHEN_KINDS.STARTED, time(STARTED)]);
      expect(
        dateOf(whatsappApiRow({ status: 'completed', completed_at: FINISHED }))
      ).toEqual(['completed', WHEN_KINDS.SENT, time(FINISHED)]);
    });

    it('scheduled: the scheduled date', () => {
      expect(
        dateOf(whatsappApiRow({ status: 'scheduled', scheduled_at: SCHEDULED }))
      ).toEqual(['scheduled', WHEN_KINDS.SCHEDULED, time(SCHEDULED)]);
    });
  });

  describe('WhatsApp Oficial and SMS (Chatwoot campaigns, unix seconds)', () => {
    const seconds = value => time(value) / 1000;

    it('scheduled: the scheduled date; an empty one (0) is no date', () => {
      expect(
        dateOf(
          officialRow({
            campaign_status: 'active',
            scheduled_at: seconds(SCHEDULED),
          })
        )
      ).toEqual(['scheduled', WHEN_KINDS.SCHEDULED, time(SCHEDULED)]);
      expect(
        dateOf(officialRow({ campaign_status: 'active', scheduled_at: 0 }))
      ).toEqual(['scheduled', null, null]);
    });

    it('sending: started_at; completed: started_at, else completed_at', () => {
      expect(
        dateOf(
          smsRow({
            campaign_status: 'active',
            scheduled_at: seconds(SCHEDULED),
            started_at: seconds(STARTED),
          })
        )
      ).toEqual(['sending', WHEN_KINDS.STARTED, time(STARTED)]);
      expect(
        dateOf(
          smsRow({
            campaign_status: 'completed',
            completed_at: seconds(FINISHED),
          })
        )
      ).toEqual(['completed', WHEN_KINDS.SENT, time(FINISHED)]);
    });
  });

  it('sorts by the date shown, newest first', () => {
    const rows = buildJourneyRows({
      emailCampaigns: [
        {
          id: 1,
          name: 'Antiga',
          status: 'sent',
          sent_at: '2026-01-01T00:00:00Z',
        },
        { id: 2, name: 'Pausada', status: 'paused', started_at: STARTED },
      ],
    });

    expect(rows.map(row => row.name)).toEqual(['Pausada', 'Antiga']);
  });
});
