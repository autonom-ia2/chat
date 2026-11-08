import DraftsAPI from 'dashboard/api/campaignJourneyDrafts';
import {
  acharPronta,
  guardarPronta,
  listarProntas,
} from '../prontasParaDisparar';

vi.mock('dashboard/api/campaignJourneyDrafts', () => ({
  default: { get: vi.fn(), show: vi.fn(), create: vi.fn(), update: vi.fn() },
}));

// #1898: a campaign left ready to send lives on the server (campaign_journey/drafts).
const serverDraft = {
  id: 7,
  title: 'Liquidação',
  channel: 'sms',
  payload: { audienceId: 3, message: 'Oi' },
  email_campaign_id: null,
  author: { id: 2, name: 'Carla' },
  created_at: '2026-10-19T10:00:00Z',
  updated_at: '2026-10-19T11:00:00Z',
};

describe('prontasParaDisparar (#1898)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists the server drafts as the journey draft and who left it', async () => {
    DraftsAPI.get.mockResolvedValue({ data: { payload: [serverDraft] } });

    expect(await listarProntas()).toEqual([
      {
        id: 7,
        title: 'Liquidação',
        channel: 'sms',
        draft: { audienceId: 3, message: 'Oi', emailCampaignId: undefined },
        autor: 'Carla',
        updatedAt: '2026-10-19T11:00:00Z',
      },
    ]);
  });

  it('reads the e-mail campaign from the draft link', async () => {
    DraftsAPI.show.mockResolvedValue({
      data: {
        payload: {
          ...serverDraft,
          channel: 'email',
          payload: {},
          email_campaign_id: 9,
          author: null,
        },
      },
    });

    const pronta = await acharPronta('7');

    expect(DraftsAPI.show).toHaveBeenCalledWith('7');
    expect(pronta.draft.emailCampaignId).toBe(9);
    expect(pronta.autor).toBe('');
  });

  it('creates a new draft with the whole journey as payload', async () => {
    DraftsAPI.create.mockResolvedValue({ data: { payload: serverDraft } });
    const draft = { audienceId: 3, message: 'Oi' };

    await guardarPronta({ title: 'Liquidação', channel: 'sms', draft });

    expect(DraftsAPI.create).toHaveBeenCalledWith({
      draft: {
        title: 'Liquidação',
        channel: 'sms',
        email_campaign_id: null,
        payload: draft,
      },
    });
    expect(DraftsAPI.update).not.toHaveBeenCalled();
  });

  it('replaces the whole payload of a draft already saved', async () => {
    DraftsAPI.update.mockResolvedValue({ data: { payload: serverDraft } });
    const draft = { channel: 'email', emailCampaignId: 9 };

    await guardarPronta({ id: 7, title: 'News', channel: 'email', draft });

    expect(DraftsAPI.update).toHaveBeenCalledWith(7, {
      draft: {
        title: 'News',
        channel: 'email',
        email_campaign_id: 9,
        payload: draft,
      },
    });
  });
});
