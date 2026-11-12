import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  botao,
  erroHttp,
  esperarPor,
  irAteConferir,
  marca,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';

// A página "Trazer minha lista" inteira (#2896, Fatia 2): o Desfazer só aparece
// quando a fonte tem (`temDesfazer`). Fora da demonstração ele ainda não
// existe: a tela não mostra o botão, não monta o diálogo e não promete desfazer.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;
const PROMESSA = 'Você pode desfazer quando quiser';

const estado = vi.hoisted(() => ({ demo: 'cheio' }));

const alertar = vi.hoisted(() => vi.fn());

// O servidor de mentira (fora da demonstração a tela fala com ele, #2896).
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

vi.mock('dashboard/composables', () => ({ useAlert: alertar }));

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

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'cheio';
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

describe('fora da demonstração, a conta ainda não tem o Desfazer', () => {
  const PRONTA = {
    id: 700,
    arquivo: 'Clientes de setembro.xlsx',
    quando: '2026-11-08T14:03:00Z',
    quem: 'Marina Pavanelli',
    total: 195,
    situacao: 'pronto',
    porcentagem: 100,
    pode_tentar: false,
  };
  const LEITURA = {
    id: 812,
    situacao: 'pronta',
    arquivo: 'Clientes 2025.csv',
    valores: 'inteiros',
    colunas: [
      { indice: 0, nome: 'Nome', destino: 'nome' },
      { indice: 1, nome: 'Celular', destino: 'telefone' },
    ],
    perguntas: [],
    respostas: {},
    resumo: {
      total: 2,
      novas: 1,
      completadas: 1,
      comProblema: 0,
      juntadas: 0,
      entram: 2,
    },
    exemplos: [
      { nome: 'Ana Albuquerino', telefone: '+5511987650001', email: '' },
    ],
    problemas: [],
    problemas_total: 0,
    pagina: 1,
    por_pagina: 200,
  };

  beforeEach(() => {
    estado.demo = null;
    servidor.listas.mockResolvedValue({ data: [PRONTA] });
    servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
    servidor.leitura.mockResolvedValue({ data: LEITURA });
    servidor.trazer.mockResolvedValue({ data: { trazidaId: 812 } });
    servidor.andamento.mockResolvedValue({
      data: {
        porcentagem: 100,
        situacao: 'pronto',
        total: 2,
        novas: 1,
        completadas: 1,
      },
    });
  });

  const enviar = async w => {
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;celular'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'conferir');
  };

  it('a lista pronta do histórico não tem o botão "Desfazer", e o diálogo não é montado', async () => {
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(w.get('[data-lista] [data-situacao]').text()).toBe('Pronto');
    expect(marca(w, 'desfazer').exists()).toBe(false);
    expect(botao(w, 'Desfazer')).toBeUndefined();
    expect(w.findComponent(DialogoDesfazer).exists()).toBe(false);
    w.unmount();
  });

  it('o Conferir e o Pronto não prometem desfazer', async () => {
    const w = await abrir();
    await enviar(w);
    expect(marca(w, 'trazer-confirmar').text()).toBe('Trazer 2 pessoas');
    expect(marca(w, 'conferir').text()).not.toContain(PROMESSA);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'pronto');
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(marca(w, 'pronto-sossego').exists()).toBe(false);
    expect(w.text()).not.toContain(PROMESSA);
    // O histórico continua logo abaixo, com o título dele e sem o botão.
    expect(marca(w, 'historico').get('h2').text()).toBe(
      'Listas que você já trouxe'
    );
    expect(marca(w, 'desfazer').exists()).toBe(false);
    w.unmount();
  });
});

describe('na demonstração, o Desfazer continua na tela', () => {
  it('o histórico tem o botão, o diálogo existe e o Conferir e o Pronto dizem que dá para desfazer', async () => {
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(4));
    expect(marca(w, 'desfazer').text()).toBe('Desfazer');
    expect(w.findComponent(DialogoDesfazer).exists()).toBe(true);
    await irAteConferir(w);
    expect(marca(w, 'conferir').text()).toContain(
      'Você pode desfazer quando quiser.'
    );
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
    await aparece(w, 'pronto');
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer quando quiser, aqui embaixo.'
    );
    w.unmount();
  });
});
