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
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';

// A página "Trazer minha lista" (#2894) em demonstração: o Desfazer de uma
// lista, no Pronto e no histórico, com o texto real em pt_BR e relógio falso.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

// A demonstração leva DURACAO_DA_TRAZIDA_MS para trazer a lista; a folga cobre
// a consulta seguinte ao fim (a espera entre uma e outra chega a 5 s).
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;

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

// #2897 — a conta destes testes não tem a carteira de seguros: a tela é a das
// listas, sem a pergunta dos seguros.
vi.mock('../../carteira/useContaDeSeguros', async () => {
  const { ref } = await import('vue');
  return { useContaDeSeguros: () => ref(false) };
});

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
      '18 ficam aqui, porque já conversaram com você ou já receberam campanha.'
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
      '16 ficam aqui, porque já conversaram com você ou já receberam campanha.'
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
    expect(
      w.findAll('[data-lista] [data-situacao]').map(s => s.text())
    ).toEqual([
      'Pronto',
      'Desfeito',
      'Pronto',
      'Não consegui trazer esta lista.',
    ]);
    w.unmount();
  });

  it('Desfazer faz a linha virar "Desfeito" e some o botão', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(
        w.findAll('[data-lista] [data-situacao]').map(s => s.text())
      ).toEqual([
        'Desfeito',
        'Desfeito',
        'Pronto',
        'Não consegui trazer esta lista.',
      ])
    );
    expect(
      w
        .find(
          '[data-lista="trazida-antiga-1"] [data-relacionamentos="desfazer"]'
        )
        .exists()
    ).toBe(false);
    w.unmount();
  });

  it('erro ao desfazer avisa por toast e o diálogo continua aberto', async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    // Outra aba já desfez esta lista: a fonte recusa.
    const outraAba = trazerFonte({ demo: 'cheio' }).desfazer(
      'trazida-antiga-1'
    );
    await vi.advanceTimersByTimeAsync(0);
    await outraAba;
    await w.get('[data-dialog]').trigger('submit');
    await esperarPor(() =>
      expect(alertar).toHaveBeenCalledWith(
        'Não consegui desfazer. Tente de novo.'
      )
    );
    expect(marca(w, 'dialogo-desfazer').exists()).toBe(true);
    w.unmount();
  });
});
