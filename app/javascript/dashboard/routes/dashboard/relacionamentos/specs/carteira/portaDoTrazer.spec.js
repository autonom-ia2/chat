import { flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { aparece, erroHttp, marca } from '../trazer/apoioDaPagina';
import { daCarteira } from './apoio';
import { abrirAPorta } from './apoioDaPorta';

// #2897 — a porta de "Trazer minha lista" (pages/TrazerPage.vue) na conta que
// tem a carteira de seguros, quando o que os seguros pedem não chega (a rede
// caiu, o painel foi atualizado): a pessoa vê o erro com "Tentar de novo", e
// não uma tela em branco.
withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const conta = vi.hoisted(() => ({ carteira_seguros: true }));
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
  usarDemo: () => null,
}));

let osSeguros;
beforeAll(async () => {
  osSeguros = await import('../../carteira/trazerComSeguros.js');
}, 60000);

beforeEach(() => {
  conta.carteira_seguros = true;
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('a porta de "Trazer minha lista" na conta de seguros', () => {
  it('se o que os seguros pedem não chega, diz o erro e oferece tentar de novo', async () => {
    const baixarSeguros = vi.fn().mockRejectedValue(new Error('sem rede'));
    const w = await abrirAPorta({ baixarSeguros });

    const erro = w.get(`${daCarteira('nao-baixou')} [data-erro]`);
    expect(erro.attributes('role')).toBe('alert');
    expect(erro.get('button').text()).toBe('Tentar de novo');
    expect(erro.get('button').attributes('disabled')).toBeUndefined();
    // A tela das listas não abre pela metade.
    expect(marca(w, 'soltar-arquivo').exists()).toBe(false);
    w.unmount();
  });

  it('"Tentar de novo" baixa outra vez e abre a tela', async () => {
    const baixarSeguros = vi
      .fn()
      .mockRejectedValueOnce(new Error('sem rede'))
      .mockResolvedValueOnce(osSeguros);
    const w = await abrirAPorta({ baixarSeguros });

    await w.get(`${daCarteira('nao-baixou')} button`).trigger('click');
    await flushPromises();
    await aparece(w, 'soltar-arquivo');

    expect(baixarSeguros).toHaveBeenCalledTimes(2);
    expect(w.find(daCarteira('nao-baixou')).exists()).toBe(false);
    w.unmount();
  });

  it('enquanto baixa, a tela diz que está ocupada e não mostra erro', async () => {
    const baixarSeguros = vi.fn(() => new Promise(() => {}));
    const w = await abrirAPorta({ baixarSeguros });

    expect(
      w.get('[data-relacionamentos="trazer"]').attributes('aria-busy')
    ).toBe('true');
    expect(w.find(daCarteira('nao-baixou')).exists()).toBe(false);
    w.unmount();
  });

  it('na conta sem a carteira, nada é baixado', async () => {
    conta.carteira_seguros = false;
    const baixarSeguros = vi.fn();
    const w = await abrirAPorta({ baixarSeguros });
    await aparece(w, 'soltar-arquivo');

    expect(baixarSeguros).not.toHaveBeenCalled();
    w.unmount();
  });
});
