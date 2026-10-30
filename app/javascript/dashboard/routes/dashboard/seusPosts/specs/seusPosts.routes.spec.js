import {
  routes,
  ensureSeusPostsEnabled,
  ensureSeusPostsComentariosEnabled,
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
});
