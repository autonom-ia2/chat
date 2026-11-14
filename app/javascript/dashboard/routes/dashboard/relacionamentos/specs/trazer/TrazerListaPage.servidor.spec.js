import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  botao,
  erroHttp,
  esperarPor,
  marca,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
// A página "Trazer minha lista" inteira falando com o servidor de mentira
// (#2896): a falta de acesso, as listas que ele devolve, a lista que parou no
// meio e o caminho da planilha ao Pronto.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);

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

// #2896 — fora da demonstração a tela fala com o servidor.
describe('com o servidor', () => {
  const SEM_ACESSO =
    'Você não pode trazer listas nesta conta. Peça a quem administra a conta.';
  const doServidor = (id, situacao, extra = {}) => ({
    id,
    arquivo: `lista-${id}.xlsx`,
    quando: '2026-11-08T14:03:00Z',
    quem: 'Marina Pavanelli',
    total: 195,
    situacao,
    porcentagem: 100,
    pode_tentar: false,
    ...extra,
  });

  beforeEach(() => {
    estado.demo = null;
  });

  it.each([401, 403])(
    'recusa %s: só a frase de sem acesso, com role="alert" e sem "Tentar de novo"',
    async status => {
      servidor.listas.mockRejectedValue(erroHttp(status));
      const w = await abrir();
      await aparece(w, 'sem-acesso');
      expect(marca(w, 'sem-acesso').text()).toBe(SEM_ACESSO);
      expect(marca(w, 'sem-acesso').attributes('role')).toBe('alert');
      expect(marca(w, 'erro').exists()).toBe(false);
      expect(marca(w, 'soltar-arquivo').exists()).toBe(false);
      expect(marca(w, 'historico').exists()).toBe(false);
      expect(botao(w, 'Tentar de novo')).toBeUndefined();
      w.unmount();
    }
  );

  it('mostra as listas que o servidor devolve, com o dia e a situação', async () => {
    servidor.listas.mockResolvedValue({
      data: [doServidor(812, 'pronto'), doServidor(700, 'desfazendo')],
    });
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(2));
    const [primeira, segunda] = w.findAll('[data-lista]');
    expect(primeira.text()).toContain('lista-812.xlsx');
    expect(primeira.text()).toContain('em 08/11');
    expect(primeira.get('[data-situacao]').text()).toBe('Pronto');
    expect(segunda.get('[data-situacao]').text()).toBe('Desfazendo…');
    w.unmount();
  });

  it('lista que falhou: "Tentar de novo" confirma no servidor e a lista volta a ser trazida', async () => {
    servidor.listas
      .mockResolvedValueOnce({
        data: [doServidor(812, 'falhou', { pode_tentar: true })],
      })
      .mockResolvedValue({
        data: [doServidor(812, 'trazendo', { porcentagem: 40 })],
      });
    servidor.confirmar.mockResolvedValue({ data: { id: 812 } });
    const w = await abrir();
    await aparece(w, 'tentar-de-novo');
    expect(w.get('[data-situacao="falhou"]').text()).toBe(
      'Não consegui trazer esta lista.'
    );
    await marca(w, 'tentar-de-novo').trigger('click');
    await esperarPor(() =>
      expect(w.get('[data-lista] [data-situacao]').text()).toBe('Trazendo 40%')
    );
    expect(servidor.confirmar).toHaveBeenCalledWith(812);
    expect(marca(w, 'tentar-de-novo').exists()).toBe(false);
    w.unmount();
  });

  it('da planilha ao Pronto sem perguntas: Enviar → Conferir → Trazer → Pronto', async () => {
    servidor.listas.mockResolvedValue({ data: [] });
    servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
    servidor.leitura.mockResolvedValue({
      data: {
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
      },
    });
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
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;celular'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'conferir');
    expect(marca(w, 'pergunta').exists()).toBe(false);
    expect(marca(w, 'conferir').text()).toContain('+55 11 98765-0001');
    await botao(w, 'Trazer 2 pessoas').trigger('click');
    await aparece(w, 'pronto');
    expect(servidor.trazer).toHaveBeenCalledWith(812);
    expect(servidor.confirmar).not.toHaveBeenCalled();
    expect(servidor.andamento).toHaveBeenCalledWith(812);
    expect(marca(w, 'pronto').text()).toContain('1 pessoa chegou');
    w.unmount();
  });

  it('.xls não é enviado: a tela diz a frase do tipo, que não promete .xls', async () => {
    servidor.listas.mockResolvedValue({ data: [] });
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['x'], 'clientes.xls')],
      configurable: true,
    });
    await entrada.trigger('change');
    const frase = marca(w, 'erro-da-planilha').text();
    expect(frase).toBe('Este arquivo não é uma planilha. Use Excel ou CSV.');
    expect(frase).not.toContain('xls');
    expect(servidor.enviar).not.toHaveBeenCalled();
    w.unmount();
  });
});
