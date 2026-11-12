import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  botao,
  erroHttp,
  esperarPor,
  irAteConferir,
  marca,
  some,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo, trazerFonte } from '../../fonte/trazerFonte';
import {
  DURACAO_DA_TRAZIDA_MS,
  DURACAO_DO_DESFAZER_MS,
} from '../../demo/trazer';

// A página "Trazer minha lista" (#2894) em demonstração: o Desfazer de uma
// lista, no Pronto e no histórico, com o texto real em pt_BR e relógio falso.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

// A demonstração leva DURACAO_DA_TRAZIDA_MS para trazer a lista; a folga cobre
// a consulta seguinte ao fim (a espera entre uma e outra chega a 5 s).
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;
// O mesmo para o desfazer: a demonstração leva DURACAO_DO_DESFAZER_MS.
const ATE_DESFAZER_TUDO_MS = DURACAO_DO_DESFAZER_MS + 5000;
const situacoes = w =>
  w.findAll('[data-lista] [data-situacao]').map(s => s.text());

const estado = vi.hoisted(() => ({ demo: 'cheio' }));

const empurrar = vi.hoisted(() => vi.fn());

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
  useRouter: () => ({ push: empurrar, replace: vi.fn() }),
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
  empurrar.mockClear();
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

describe('Desfazer a lista recém-trazida, ali mesmo no Pronto', () => {
  it('abre o mesmo diálogo, com a prévia da planilha de exemplo', async () => {
    const w = await abrir();
    await irAteConferir(w);
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'andamento');
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
    await aparece(w, 'pronto');
    // A lista recém-trazida entra no topo do histórico.
    await esperarPor(() =>
      expect(w.get('[data-lista]:first-child').text()).toContain(
        'Clientes 2025.xlsx'
      )
    );
    await w
      .get('[data-lista]:first-child [data-relacionamentos="desfazer"]')
      .trigger('click');
    await aparece(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira as 162 pessoas'
      )
    );
    expect(marca(w, 'dialogo-desfazer').text()).toContain(
      '18 ficam aqui: alguém já cuidou delas (conversa, card, etiqueta ou campanha) ou elas vieram também em outra lista.'
    );
    w.unmount();
  });
});

describe('Desfazer', () => {
  const abrirDialogoDaLista = async () => {
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(4));
    await w
      .get('[data-lista] [data-relacionamentos="desfazer"]')
      .trigger('click');
    await aparece(w, 'dialogo-desfazer');
    return w;
  };

  it('mostra antes o que sai, quem fica aqui e o que volta', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira as 104 pessoas'
      )
    );
    const texto = marca(w, 'dialogo-desfazer').text();
    expect(texto).toContain(
      'As 12 que já estavam aqui voltam a ser como eram.'
    );
    expect(texto).toContain(
      '16 ficam aqui: alguém já cuidou delas (conversa, card, etiqueta ou campanha) ou elas vieram também em outra lista.'
    );
    expect(texto).not.toContain('As conversas que já aconteceram ficam.');
    expect(
      w.get('[data-dialog] [data-relacionamentos="titulo-do-dialogo"]').text()
    ).toBe('Desfazer “Clientes de setembro.xlsx”?');
    w.unmount();
  });

  it('Cancelar fecha sem desfazer', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await botao(w, 'Cancelar').trigger('click');
    await some(w, 'dialogo-desfazer');
    expect(situacoes(w)).toEqual([
      'Pronto',
      'Desfeito',
      'Pronto',
      'Não consegui trazer esta lista.',
    ]);
    w.unmount();
  });

  const botaoDaPrimeira = w =>
    w.find('[data-lista="trazida-antiga-1"] [data-relacionamentos="desfazer"]');

  it('Desfazer faz a linha virar "Desfazendo…", sem o botão, e depois "Desfeito"', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(situacoes(w)).toEqual([
        'Desfazendo…',
        'Desfeito',
        'Pronto',
        'Não consegui trazer esta lista.',
      ])
    );
    expect(botaoDaPrimeira(w).exists()).toBe(false);
    // A tela acompanha sozinha até o servidor terminar.
    await vi.advanceTimersByTimeAsync(ATE_DESFAZER_TUDO_MS);
    await esperarPor(() =>
      expect(situacoes(w)).toEqual([
        'Desfeito',
        'Desfeito',
        'Pronto',
        'Não consegui trazer esta lista.',
      ])
    );
    expect(botaoDaPrimeira(w).exists()).toBe(false);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  // A lista que parou no meio (a última do exemplo): continuar ou desfazer.
  it('a lista que parou no meio tem "Tentar de novo" e "Desfazer", e desfazer a leva a "Desfeito"', async () => {
    const PARADA = '[data-lista="trazida-antiga-4"]';
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(4));
    expect(w.findAll(`${PARADA} button`).map(b => b.text())).toEqual([
      'Tentar de novo',
      'Desfazer',
    ]);
    await w.get(`${PARADA} [data-relacionamentos="desfazer"]`).trigger('click');
    await aparece(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(marca(w, 'dialogo-desfazer').text()).toContain(
        'Isto tira as 63 pessoas'
      )
    );
    expect(
      w.get('[data-dialog] [data-relacionamentos="titulo-do-dialogo"]').text()
    ).toBe('Desfazer “Indicações de agosto.csv”?');
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() => expect(situacoes(w)[3]).toBe('Desfazendo…'));
    expect(w.findAll(`${PARADA} button`)).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(ATE_DESFAZER_TUDO_MS);
    await esperarPor(() => expect(situacoes(w)[3]).toBe('Desfeito'));
    expect(w.findAll(`${PARADA} button`)).toHaveLength(0);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('a lista que outra aba já mandou desfazer: o pedido não é erro, e a linha mostra como ela está', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    const outraAba = trazerFonte({ demo: 'cheio' }).desfazer(
      'trazida-antiga-1'
    );
    await vi.advanceTimersByTimeAsync(0);
    await outraAba;
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() => expect(situacoes(w)[0]).toBe('Desfazendo…'));
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });
});
