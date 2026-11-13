import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  erroHttp,
  irAteConferir,
  marca,
} from '../trazer/apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';

// #2897 — "Trazer minha lista" na conta que NÃO tem a carteira de seguros: a
// tela é a das listas, do começo ao fim. Não há a escolha de como trazer, a
// pergunta dos seguros não aparece e a peça da carteira
// (components/carteira/trazer/TrazerSeguros.vue) nem é baixada.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 13, 15);

const estado = vi.hoisted(() => ({ demo: 'fora-do-segmento' }));
// A conta aberta, como o servidor manda (fora da demonstração).
const conta = vi.hoisted(() => ({ carteira_seguros: false }));
// Quantas vezes a peça da carteira foi baixada.
const baixou = vi.hoisted(() => vi.fn());

const servidor = vi.hoisted(() => ({
  enviar: vi.fn(),
  leitura: vi.fn(),
  responder: vi.fn(),
  consertar: vi.fn(),
  deixarDeFora: vi.fn(),
  reabrir: vi.fn(),
  trocarColuna: vi.fn(),
  trazer: vi.fn(),
  listas: vi.fn(),
  andamento: vi.fn(),
  confirmar: vi.fn(),
}));

vi.mock('../../components/carteira/trazer/TrazerSeguros.vue', () => {
  baixou();
  return { default: { render: () => null } };
});

vi.mock('dashboard/api/relacionamentosTrazer', () => ({ default: servidor }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return { useAccount: () => ({ currentAccount: ref(conta) }) };
});

vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));

// A fonte de verdade, sem as esperas da demonstração.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerFonte: opcoes =>
      original.trazerFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      }),
  };
});

vi.setConfig({ testTimeout: 30000 });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'fora-do-segmento';
  conta.carteira_seguros = false;
  baixou.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

describe('conta sem a carteira de seguros', () => {
  it('a demonstração de outro segmento vai do enviar ao conferir sem a pergunta dos seguros', async () => {
    const w = await abrir();

    // A tela de entrada já é a de enviar, sem a escolha de como trazer.
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(marca(w, 'soltar-arquivo').exists()).toBe(true);

    // Das duas perguntas das listas direto para o Conferir delas.
    await irAteConferir(w);

    expect(w.get('h1').text()).toBe('Achei 203 pessoas.');
    expect(w.find('[data-carteira]').exists()).toBe(false);
    expect(baixou).not.toHaveBeenCalled();
    w.unmount();
  });

  it('fora da demonstração, a conta que o servidor diz que não tem a carteira não baixa a peça', async () => {
    estado.demo = null;
    const w = await abrir();
    await aparece(w, 'soltar-arquivo');

    expect(w.find('[data-carteira]').exists()).toBe(false);
    expect(baixou).not.toHaveBeenCalled();
    w.unmount();
  });

  it('a conta sem o payload da carteira também não', async () => {
    estado.demo = null;
    delete conta.carteira_seguros;
    const w = await abrir();
    await aparece(w, 'soltar-arquivo');

    expect(baixou).not.toHaveBeenCalled();
    w.unmount();
  });
});
