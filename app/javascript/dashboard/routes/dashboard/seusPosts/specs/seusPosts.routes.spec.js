import {
  routes,
  ensureSeusPostsEnabled,
  ensureSeusPostsComentariosEnabled,
  ensureCuidarEnabled,
} from '../seusPosts.routes';
import store from 'dashboard/store';

// Seus posts (#2304): a rota só abre com a flag seus_posts; desligada (link direto ou F5), vai para home.
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

const comConta = (conta, ligada, comentarios = false) => {
  store.getters['accounts/getAccount'] = () => conta;
  store.getters['accounts/isFeatureEnabledonAccount'] = (_id, flag) =>
    (ligada && flag === 'seus_posts') ||
    (comentarios && flag === 'seus_posts_comentarios');
};
const para = { params: { accountId: '9' } };

describe('seusPosts.routes', () => {
  beforeEach(() => vi.clearAllMocks());

  it('a rota passa pelo guarda da flag', () => {
    expect(routes[0].beforeEnter).toBe(ensureSeusPostsEnabled);
  });

  it('flag ligada: abre', async () => {
    comConta({ id: 9 }, true);
    const next = vi.fn();
    await ensureSeusPostsEnabled(para, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('flag desligada: vai para home', async () => {
    comConta({ id: 9 }, false);
    const next = vi.fn();
    await ensureSeusPostsEnabled(para, {}, next);
    expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
  });

  it('conta ainda não carregada (F5): carrega antes de decidir', async () => {
    comConta(null, true);
    store.dispatch.mockImplementation(async () => {
      store.getters['accounts/getAccount'] = () => ({ id: 9 });
    });
    const next = vi.fn();
    await ensureSeusPostsEnabled(para, {}, next);
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  // F2 (#2305): o post aqui dentro pede as duas flags.
  it('o post passa pelo guarda das duas flags', () => {
    const post = routes.find(rota => rota.name === 'seus_posts_post');
    expect(post.beforeEnter).toBe(ensureSeusPostsComentariosEnabled);
  });

  it('post com as duas flags: abre', async () => {
    comConta({ id: 9 }, true, true);
    const next = vi.fn();
    await ensureSeusPostsComentariosEnabled(para, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it('post sem a flag dos comentários: vai para home', async () => {
    comConta({ id: 9 }, true, false);
    const next = vi.fn();
    await ensureSeusPostsComentariosEnabled(para, {}, next);
    expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
  });

  // #2212 (B1): cuidar dos comentários pede as três flags e as permissões do post.
  describe('cuidar dos comentários', () => {
    const comFlags = ligadas => {
      store.getters['accounts/getAccount'] = () => ({ id: 9 });
      store.getters['accounts/isFeatureEnabledonAccount'] = (_id, flag) =>
        ligadas.includes(flag);
    };
    // #2520: a régua do motor: a tela, o cuidado e os comentários da rede do perfil; sem seus_posts_comentarios.
    const TODAS = ['seus_posts', 'meta_ads_comentarios_ia'];
    const REDES = [
      'meta_ads_comentarios_instagram',
      'meta_ads_comentarios_facebook',
    ];

    it('a rota fica no endereço do post, com o guarda e as permissões do post', () => {
      const cuidar = routes.find(rota => rota.name === 'seus_posts_cuidar');
      const post = routes.find(rota => rota.name === 'seus_posts_post');
      expect(cuidar.path).toBe(
        '/app/accounts/:accountId/seus-posts/:postId/cuidar'
      );
      expect(cuidar.beforeEnter).toBe(ensureCuidarEnabled);
      expect(cuidar.meta.featureFlag).toBe('meta_ads_comentarios_ia');
      expect(cuidar.meta.permissions).toEqual(post.meta.permissions);
    });

    // #2520: a flag da rede do perfil (?perfil=), a mesma que o servidor confere.
    const doPerfil = perfil => ({ ...para, query: { perfil } });
    const IG = doPerfil('instagram-1');
    const FB = doPerfil('facebook-2');

    it.each([
      [IG, REDES[0]],
      [FB, REDES[1]],
    ])('com as duas flags e a da rede do perfil: abre', async (rota, rede) => {
      comFlags([...TODAS, rede]);
      const next = vi.fn();
      await ensureCuidarEnabled(rota, {}, next);
      expect(next).toHaveBeenCalledWith();
    });

    it('só com a flag da outra rede: vai para home (o servidor daria 404)', async () => {
      comFlags([...TODAS, REDES[1]]);
      const next = vi.fn();
      await ensureCuidarEnabled(IG, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: IG.params });
    });

    it('sem o perfil no endereço: vai para home', async () => {
      comFlags([...TODAS, ...REDES]);
      const next = vi.fn();
      await ensureCuidarEnabled(para, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
    });

    it.each(TODAS)('sem %s: vai para home', async flag => {
      comFlags([...TODAS, ...REDES].filter(ligada => ligada !== flag));
      const next = vi.fn();
      await ensureCuidarEnabled(IG, {}, next);
      expect(next).toHaveBeenCalledWith({ name: 'home', params: IG.params });
    });
  });
});
