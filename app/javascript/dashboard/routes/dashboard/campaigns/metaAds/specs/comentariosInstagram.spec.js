import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import instagramClient from 'dashboard/api/channel/instagramClient';
import comentarios from '../components/comentarios/comentariosInstagram';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    instagramComments: vi.fn(),
    replyInstagramComment: vi.fn(),
    hideInstagramComment: vi.fn(),
    deleteInstagramComment: vi.fn(),
    privateReplyInstagramComment: vi.fn(),
  },
}));
vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: { generateAuthorization: vi.fn() },
}));

// Comentários do anúncio no Instagram (#2196): o adaptador real fala com o servidor sempre com o anúncio primeiro e,
// sem a permissão, pede o login da caixa de novo com o purpose dos comentários, voltando ao anúncio.
describe('comentariosInstagram (#2196)', () => {
  const assign = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubGlobal('location', {
      pathname: '/app/accounts/18/campaigns/meta-ads',
      assign,
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('lists and pages the comments of the ad', async () => {
    CrmMetaAdsConnectionAPI.instagramComments.mockResolvedValue({
      data: { status: 'ready', comments: [{ id: '1' }], next_cursor: 'C2' },
    });

    const first = await comentarios.listar('120', { locale: 'en' });
    await comentarios.mais('120', 'C2');

    expect(first.comments).toEqual([{ id: '1' }]);
    expect(CrmMetaAdsConnectionAPI.instagramComments).toHaveBeenCalledWith(
      '120'
    );
    expect(CrmMetaAdsConnectionAPI.instagramComments).toHaveBeenCalledWith(
      '120',
      'C2'
    );
  });

  it('acts on the comment of the ad and rejects when the server refuses', async () => {
    CrmMetaAdsConnectionAPI.replyInstagramComment.mockResolvedValue({
      data: { id: '9' },
    });
    CrmMetaAdsConnectionAPI.deleteInstagramComment.mockResolvedValue({
      data: { id: '1' },
    });
    CrmMetaAdsConnectionAPI.privateReplyInstagramComment.mockResolvedValue({
      data: { conversation_path: '/app/accounts/18/conversations/7' },
    });
    CrmMetaAdsConnectionAPI.hideInstagramComment.mockRejectedValue(
      new Error('meta_refused')
    );

    expect(await comentarios.responder('120', '1', 'Oi')).toEqual({ id: '9' });
    await expect(comentarios.ocultar('120', '1', true)).rejects.toThrow();
    await comentarios.apagar('120', '1');
    await comentarios.privado('120', '1', 'Oi');

    expect(CrmMetaAdsConnectionAPI.replyInstagramComment).toHaveBeenCalledWith(
      '120',
      '1',
      'Oi'
    );
    expect(CrmMetaAdsConnectionAPI.deleteInstagramComment).toHaveBeenCalledWith(
      '120',
      '1'
    );
    expect(
      CrmMetaAdsConnectionAPI.privateReplyInstagramComment
    ).toHaveBeenCalledWith('120', '1', 'Oi');
  });

  it('without permission, logs the inbox in again asking for the comments and back to the ad', async () => {
    CrmMetaAdsConnectionAPI.instagramComments.mockResolvedValue({
      data: { status: 'needs_login', inbox_id: 55, comments: [] },
    });
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: 'https://www.instagram.com/oauth/authorize?x=1' },
    });

    await comentarios.listar('120');
    await comentarios.entrar('needs_login', '120');

    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
      inbox_id: 55,
      return_to: 'meta_ads',
      purpose: 'meta_ads_comentarios_instagram',
      ad_id: '120',
    });
    expect(assign).toHaveBeenCalledWith(
      'https://www.instagram.com/oauth/authorize?x=1'
    );
  });

  it('without the Instagram connected, opens the screen to connect it', async () => {
    CrmMetaAdsConnectionAPI.instagramComments.mockResolvedValue({
      data: { status: 'not_connected', comments: [] },
    });

    await comentarios.listar('121');
    await comentarios.entrar('not_connected', '121');

    expect(instagramClient.generateAuthorization).not.toHaveBeenCalled();
    expect(assign).toHaveBeenCalledWith(
      '/app/accounts/18/settings/inboxes/new/instagram'
    );
  });
});
