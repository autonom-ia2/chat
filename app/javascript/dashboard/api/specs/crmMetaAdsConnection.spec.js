import crmMetaAdsConnection from '../crmMetaAdsConnection';

// #2327: the reply text goes as `content`, which the Rails log filters.
// `text` would reach CloudWatch in clear.
describe('#CrmMetaAdsConnectionAPI Instagram comments', () => {
  const originalAxios = window.axios;
  const axiosMock = { post: vi.fn(() => Promise.resolve()) };
  const base =
    '/api/v1/accounts/85/crm/meta_ads_connection/ads/120/instagram_comments/180';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/campaigns/meta-ads');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('sends the public reply as content', () => {
    crmMetaAdsConnection.replyInstagramComment('120', '180', 'Oi');

    expect(axiosMock.post).toHaveBeenCalledWith(`${base}/reply`, {
      content: 'Oi',
    });
  });

  it('sends the private reply as content', () => {
    crmMetaAdsConnection.privateReplyInstagramComment('120', '180', 'Oi');

    expect(axiosMock.post).toHaveBeenCalledWith(`${base}/private_reply`, {
      content: 'Oi',
    });
  });
});
