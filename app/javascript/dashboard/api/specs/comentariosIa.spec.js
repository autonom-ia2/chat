import comentariosIa from '../comentariosIa';

// #2212: the comment care of a post (B1, with ?perfil=) or an ad (B2, no
// perfil). Contract: docs/audit/2026-10-30-2212-contrato-api.md.
describe('#ComentariosIaAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    put: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };
  const post = { kind: 'post', id: '1790/1', perfil: 'instagram-7' };
  const ad = { kind: 'ad', id: '120', perfil: 'ignored' };
  const postBase = '/api/v1/accounts/85/seus_posts/posts/1790%2F1';
  const adBase = '/api/v1/accounts/85/crm/meta_ads_connection/ads/120';

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/seus-posts/1');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('reads the post care with the profile', () => {
    comentariosIa.getCuidado(post);

    expect(axiosMock.get).toHaveBeenCalledWith(`${postBase}/cuidado`, {
      params: { perfil: 'instagram-7' },
    });
  });

  it('saves the message, para_quem, phrases and status', () => {
    comentariosIa.saveCuidado(post, {
      message: 'Oi! O catálogo: loja.com',
      paraQuem: 'Quem pedir o link',
      phrases: ['Te mandei no privado!'],
      status: 'on',
    });

    expect(axiosMock.put).toHaveBeenCalledWith(
      `${postBase}/cuidado`,
      {
        message: 'Oi! O catálogo: loja.com',
        para_quem: 'Quem pedir o link',
        phrases: ['Te mandei no privado!'],
        status: 'on',
      },
      { params: { perfil: 'instagram-7' } }
    );
  });

  it('asks the preview with para_quem', () => {
    comentariosIa.previa(post, { paraQuem: 'Quem perguntar o preço' });

    expect(axiosMock.post).toHaveBeenCalledWith(
      `${postBase}/cuidado/previa`,
      { para_quem: 'Quem perguntar o preço' },
      { params: { perfil: 'instagram-7' } }
    );
  });

  it('queues reading the older comments', () => {
    comentariosIa.lerAntigos(post);

    expect(axiosMock.post).toHaveBeenCalledWith(
      `${postBase}/cuidado/ler_antigos`,
      null,
      { params: { perfil: 'instagram-7' } }
    );
  });

  it('reads the summary of the comments', () => {
    comentariosIa.getResumo(post);

    expect(axiosMock.get).toHaveBeenCalledWith(`${postBase}/resumo`, {
      params: { perfil: 'instagram-7' },
    });
  });

  it('uses the ad target without a profile', () => {
    comentariosIa.getCuidado(ad);
    comentariosIa.getResumo(ad);
    comentariosIa.lerAntigos(ad);

    expect(axiosMock.get).toHaveBeenCalledWith(`${adBase}/cuidado`, {
      params: {},
    });
    expect(axiosMock.get).toHaveBeenCalledWith(`${adBase}/resumo`, {
      params: {},
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      `${adBase}/cuidado/ler_antigos`,
      null,
      { params: {} }
    );
  });

  it('reads the care state of every ad', () => {
    comentariosIa.getCuidadosDosAnuncios();

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/meta_ads_connection/cuidados'
    );
  });

  it('lists the cares of a profile and changes all of them', () => {
    comentariosIa.getCuidados('instagram-7');
    comentariosIa.mudarTodos('instagram-7', 'paused');

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/seus_posts/cuidados',
      { params: { perfil: 'instagram-7' } }
    );
    expect(axiosMock.put).toHaveBeenCalledWith(
      '/api/v1/accounts/85/seus_posts/cuidados',
      { status: 'paused' },
      { params: { perfil: 'instagram-7' } }
    );
  });

  it('refuses an unknown target', () => {
    expect(() => comentariosIa.getCuidado({ kind: 'story', id: '1' })).toThrow(
      'unknown target'
    );
  });
});
