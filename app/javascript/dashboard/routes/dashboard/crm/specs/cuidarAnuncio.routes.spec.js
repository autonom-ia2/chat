import { routes, ensureCuidarAnuncio } from '../crm.routes';
import store from 'dashboard/store';

// #2212 (B2): cuidar dos comentários do anúncio só abre com o CRM e as flags do anúncio por dentro, da gestão e do
// cuidado; senão (link direto ou F5), vai para home.
vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

const TODAS = ['meta_ads_hub', 'meta_ads_gestao', 'meta_ads_comentarios_ia'];
const comFlags = ligadas => {
  store.getters['accounts/getAccount'] = () => ({ id: 9 });
  store.getters['accounts/isFeatureEnabledonAccount'] = (_id, flag) =>
    ligadas.includes(flag);
};
const para = { params: { accountId: '9', adId: '120' } };

describe('crm.routes: cuidar dos comentários do anúncio', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
  });

  it('a rota tem o endereço, as permissões de ver o anúncio e o guarda', () => {
    const rota = routes.find(item => item.name === 'campaigns_meta_ads_cuidar');
    expect(rota.path).toBe(
      '/app/accounts/:accountId/campaigns/meta-ads/anuncios/:adId/cuidar'
    );
    expect(rota.meta.permissions).toEqual([
      'administrator',
      'meta_ads_view',
      'meta_ads_manage',
    ]);
    expect(rota.beforeEnter).toBe(ensureCuidarAnuncio);
  });

  it('com as três flags: abre', async () => {
    comFlags(TODAS);
    const next = vi.fn();
    await ensureCuidarAnuncio(para, {}, next);
    expect(next).toHaveBeenCalledWith();
  });

  it.each(TODAS)('sem %s: vai para home', async flag => {
    comFlags(TODAS.filter(item => item !== flag));
    const next = vi.fn();
    await ensureCuidarAnuncio(para, {}, next);
    expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
  });

  it('sem o CRM: vai para home', async () => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'false' };
    comFlags(TODAS);
    const next = vi.fn();
    await ensureCuidarAnuncio(para, {}, next);
    expect(next).toHaveBeenCalledWith({ name: 'home', params: para.params });
  });
});
