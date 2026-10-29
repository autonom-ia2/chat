import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import adaptador from '../comentariosFacebook';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: {
    facebookComments: vi.fn(),
    replyFacebookComment: vi.fn(),
    hideFacebookComment: vi.fn(),
    deleteFacebookComment: vi.fn(),
  },
}));

// Comentários do Facebook (#2197): o adaptador real fala com o servidor na forma combinada com a casca (#2196).
describe('comentariosFacebook', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lista e pede a página seguinte pelo cursor', async () => {
    const pagina = { status: 'ready', comments: [{ id: '1_2' }], total: 1 };
    CrmMetaAdsConnectionAPI.facebookComments.mockResolvedValue({
      data: { comments: pagina },
    });

    expect(await adaptador.listar('99')).toEqual(pagina);
    await adaptador.mais('99', 'CUR');

    expect(CrmMetaAdsConnectionAPI.facebookComments).toHaveBeenNthCalledWith(
      1,
      '99'
    );
    expect(CrmMetaAdsConnectionAPI.facebookComments).toHaveBeenNthCalledWith(
      2,
      '99',
      'CUR'
    );
  });

  it('responde, oculta e apaga sempre com o anúncio', async () => {
    CrmMetaAdsConnectionAPI.replyFacebookComment.mockResolvedValue({
      data: { id: '1_3' },
    });
    CrmMetaAdsConnectionAPI.hideFacebookComment.mockResolvedValue({
      data: { hidden: true },
    });
    CrmMetaAdsConnectionAPI.deleteFacebookComment.mockResolvedValue({
      data: { deleted: true },
    });

    expect(await adaptador.responder('99', '1_2', 'Oi')).toEqual({
      id: '1_3',
    });
    await adaptador.ocultar('99', '1_2', true);
    await adaptador.apagar('99', '1_2');

    expect(CrmMetaAdsConnectionAPI.replyFacebookComment).toHaveBeenCalledWith(
      '99',
      '1_2',
      'Oi'
    );
    expect(CrmMetaAdsConnectionAPI.hideFacebookComment).toHaveBeenCalledWith(
      '99',
      '1_2',
      true
    );
    expect(CrmMetaAdsConnectionAPI.deleteFacebookComment).toHaveBeenCalledWith(
      '99',
      '1_2'
    );
  });

  it('recusa do servidor sobe para a casca avisar', async () => {
    CrmMetaAdsConnectionAPI.deleteFacebookComment.mockRejectedValue(
      new Error('422')
    );

    await expect(adaptador.apagar('99', '1_2')).rejects.toThrow('422');
  });

  it('sem permissão leva à Conexão com o anúncio para voltar', () => {
    const assign = vi.fn();
    vi.stubGlobal('location', {
      pathname: '/app/accounts/1/campaigns/meta-ads',
      search: '?aba=resultado&anuncio=99',
      assign,
    });

    adaptador.entrar('needs_login', '99');

    expect(assign).toHaveBeenCalledWith(
      '/app/accounts/1/campaigns/meta-ads?aba=conexao&anuncio=99&volta=99'
    );
    vi.unstubAllGlobals();
  });

  // #2359: sem a caixa do Messenger da Página, o botão leva a conectar a Página como caixa.
  it('sem a caixa da Página leva a conectar o Messenger', () => {
    const assign = vi.fn();
    vi.stubGlobal('location', {
      pathname: '/app/accounts/1/campaigns/meta-ads',
      search: '?aba=resultado&anuncio=99',
      assign,
    });

    adaptador.entrar('no_inbox', '99');

    expect(assign).toHaveBeenCalledWith(
      '/app/accounts/1/settings/inboxes/new/facebook'
    );
    vi.unstubAllGlobals();
  });
});
