// Prospecção › Configurações (#1618): o guarda era síncrono e decidia antes de a
// conta estar na store. Com F5 ou link direto, mandava para Conversas mesmo com a
// Prospecção ligada. Agora espera a conta, como as outras rotas da Prospecção.
import prospectingRoutes from '../prospecting.routes';

const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/store', () => ({ default: store }));
vi.mock('../../../../../store', () => ({ default: store }));

const [rota] = prospectingRoutes.routes;
const entrar = async () => {
  const next = vi.fn();
  await rota.beforeEnter({ params: { accountId: '9' } }, {}, next);
  return next;
};

const contaCarregaDepois = conta => {
  let carregada = null;
  store.getters['accounts/getAccount'] = () => carregada;
  store.dispatch.mockImplementation(async () => {
    carregada = conta;
  });
};

describe('Prospecção › Configurações com link direto', () => {
  beforeEach(() => store.dispatch.mockReset());

  it('espera a conta e entra', async () => {
    contaCarregaDepois({ id: 9, autonomia_prospecting_enabled: true });
    const next = await entrar();
    expect(store.dispatch).toHaveBeenCalledWith('accounts/get');
    expect(next).toHaveBeenCalledWith();
  });

  it('Prospecção desligada na conta continua indo para home', async () => {
    contaCarregaDepois({ id: 9, autonomia_prospecting_enabled: false });
    const next = await entrar();
    expect(next).toHaveBeenCalledWith({
      name: 'home',
      params: { accountId: '9' },
    });
  });
});
