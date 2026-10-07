import EmailCampaignAiAPI from '../emailCampaignAi';

describe('Email campaign AI API', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    vi.useFakeTimers();
    window.history.pushState({}, '', '/app/accounts/85/email_campaigns');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('keeps generate and status requests synchronous', () => {
    EmailCampaignAiAPI.generate({
      campaignId: 7,
      brief: 'Novidades',
      placeholders: ['name'],
      assets: [],
      baseMjml: '<mjml />',
    });
    EmailCampaignAiAPI.status(7);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/email_campaigns/ai/generate',
      {
        campaign_id: 7,
        brief: 'Novidades',
        placeholders: ['name'],
        assets: [],
        base_mjml: '<mjml />',
      }
    );
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/email_campaigns/ai/campaigns/7/status'
    );
  });

  it('discards the AI adjustment of a campaign (#1095)', () => {
    EmailCampaignAiAPI.discardAdjustment(7);

    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/85/email_campaigns/ai/campaigns/7/adjustment'
    );
  });

  it('posts rewrite through the async request wrapper', async () => {
    axiosMock.post.mockResolvedValueOnce({
      status: 202,
      data: {
        poll_url: '/api/v1/accounts/85/ai_requests/rewrite-1',
      },
    });
    axiosMock.get.mockResolvedValueOnce({
      data: { status: 'done', result: { text: 'Olá, {{name}}' } },
    });

    const request = EmailCampaignAiAPI.rewrite({
      text: 'Oi',
      instruction: 'Deixe mais claro',
    });

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/email_campaigns/ai/rewrite',
      { text: 'Oi', instruction: 'Deixe mais claro' }
    );

    await vi.advanceTimersByTimeAsync(1000);
    await expect(request).resolves.toEqual({
      status: 200,
      data: { text: 'Olá, {{name}}' },
    });
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/ai_requests/rewrite-1'
    );
  });
});
