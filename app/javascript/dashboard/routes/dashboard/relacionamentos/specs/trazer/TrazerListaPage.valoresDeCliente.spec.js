import { flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  continuar,
  erroHttp,
  escolher,
  esperarPor,
  marca,
} from './apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
// #2896, E3 — a página "Trazer minha lista" inteira com a pergunta "Quais
// destes querem dizer cliente?": em demonstração (a planilha de exemplo, com a
// coluna "Já é cliente?") e com o servidor de mentira (as duas recusas novas).
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 12, 15);

const estado = vi.hoisted(() => ({ demo: 'cheio' }));
const alertar = vi.hoisted(() => vi.fn());
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

vi.setConfig({ testTimeout: 30000 });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'cheio';
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Element.prototype.scrollIntoView = vi.fn();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockResolvedValue({ data: [] });
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

const naPergunta = (w, id) =>
  esperarPor(() =>
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe(id)
  );
const caixa = (w, resposta) =>
  w.get(`[role="checkbox"][data-resposta="${resposta}"]`);
const caixaDoValor = (w, valor) =>
  w
    .findAll('[role="checkbox"]')
    .find(item => item.find('[data-relacionamentos="valor"]').text() === valor);
// "Algumas", a coluna (pelo índice dela) e Continuar.
const dizerAlgumas = async (w, indice) => {
  await escolher(w, 'algumas');
  await w.get('[role="combobox"]').trigger('click');
  await flushPromises();
  await w.get(`[role="option"][data-value="${indice}"]`).trigger('click');
  await continuar(w);
};

describe('em demonstração: da planilha de exemplo ao Conferir', () => {
  const JA_E_CLIENTE = 7;

  it('quem diz "Algumas" marca os valores que querem dizer cliente, e o Conferir conta quantas entram assim', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    await dizerAlgumas(w, JA_E_CLIENTE);

    await naPergunta(w, 'valores_cliente');
    expect(w.get('h1').text()).toBe('Quais destes querem dizer cliente?');
    expect(marca(w, 'coluna-da-pergunta').text()).toBe(
      'Coluna “Já é cliente?”'
    );
    // Tela nova: o foco vai para o título dela.
    await esperarPor(() =>
      expect(document.activeElement).toBe(w.get('h1').element)
    );
    // Nada vem marcado, nem o valor que "parece" cliente.
    expect(w.findAll('[role="checkbox"][aria-checked="true"]')).toHaveLength(0);
    expect(caixaDoValor(w, 'Sim, desde 2019').text()).toContain('14 linhas');

    await continuar(w);
    expect(w.get('[role="alert"]').text()).toBe('Marque pelo menos um.');
    expect(document.activeElement).toBe(caixa(w, 'preenchidas').element);

    await caixaDoValor(w, 'Sim').trigger('click');
    await caixaDoValor(w, 'Sim, desde 2019').trigger('click');
    expect(w.findAll('[role="checkbox"][aria-checked="true"]')).toHaveLength(2);
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await continuar(w);

    await naPergunta(w, 'telefone');
    await escolher(w, 'da_pessoa');
    await continuar(w);
    await aparece(w, 'conferir');
    expect(marca(w, 'entram-como-clientes').text()).toBe(
      '110 entram como clientes.'
    );
    // Das três pessoas de exemplo, duas têm um valor marcado.
    expect(
      w.findAll('[data-ficha-de-exemplo] [data-selo="cliente"]')
    ).toHaveLength(2);
    w.unmount();
  });

  it('"Sim, todas" não mostra a pergunta dos valores', async () => {
    const w = await abrir();
    await marca(w, 'usar-exemplo').trigger('click');
    await aparece(w, 'pergunta');
    await escolher(w, 'sim_todas');
    await continuar(w);
    await naPergunta(w, 'telefone');
    await escolher(w, 'da_pessoa');
    await continuar(w);
    await aparece(w, 'conferir');
    expect(marca(w, 'entram-como-clientes').text()).toBe(
      '195 entram como clientes.'
    );
    w.unmount();
  });
});

describe('com o servidor: a pergunta dos valores e as recusas', () => {
  const SITUACAO = 6;
  const DOS_VALORES = {
    id: 'valores_cliente',
    coluna: 'Situação',
    indice: SITUACAO,
    preenchidas: 8,
    valores: [
      { chave: '9f2c', valor: 'Sim', linhas: 5 },
      { chave: 'a01b', valor: 'Não', linhas: 3 },
    ],
    outros: null,
  };
  const ALGUMAS = { clientes: 'algumas', coluna_cliente: SITUACAO };
  const MARCADAS = { modo: 'valores', chaves: ['9f2c'] };
  const leitura = (extra = {}) => ({
    id: 812,
    situacao: 'pronta',
    arquivo: 'Clientes 2025.csv',
    valores: 'inteiros',
    colunas: [
      { indice: 0, nome: 'Nome', destino: 'nome' },
      { indice: 1, nome: 'Cel', destino: 'telefone' },
      {
        indice: SITUACAO,
        nome: 'Situação',
        destino: 'informacao',
        campo: { nome: 'Situação', para_que_serve: '' },
      },
    ],
    perguntas: [{ id: 'clientes' }],
    respostas: {},
    resumo: {
      total: 8,
      novas: 6,
      completadas: 2,
      comProblema: 0,
      juntadas: 0,
      entram: 8,
      clientes: 0,
    },
    exemplos: [],
    problemas: [],
    problemas_total: 0,
    pagina: 1,
    por_pagina: 200,
    ...extra,
  });
  const COM_A_PERGUNTA = leitura({
    perguntas: [{ id: 'clientes' }, DOS_VALORES],
    respostas: ALGUMAS,
  });
  const RESPONDIDA = leitura({
    perguntas: [{ id: 'clientes' }, DOS_VALORES],
    respostas: { ...ALGUMAS, valores_cliente: MARCADAS },
    resumo: { ...leitura().resumo, clientes: 5 },
  });

  beforeEach(() => {
    estado.demo = null;
    servidor.enviar.mockResolvedValue({ data: { id: 812, situacao: 'lendo' } });
    servidor.leitura.mockResolvedValue({ data: leitura() });
  });

  // Da planilha enviada até a pergunta dos valores: "Algumas" é gravada na
  // hora, o servidor lê a planilha de novo e a leitura volta com a pergunta.
  const ateAPerguntaDosValores = async () => {
    const w = await abrir();
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;cel'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'pergunta');
    servidor.responder.mockResolvedValueOnce({
      data: { id: 812, situacao: 'lendo' },
    });
    servidor.leitura.mockResolvedValue({ data: COM_A_PERGUNTA });
    await dizerAlgumas(w, SITUACAO);
    await naPergunta(w, 'valores_cliente');
    return w;
  };
  const ateConferir = async () => {
    const w = await ateAPerguntaDosValores();
    servidor.responder.mockResolvedValueOnce({ data: RESPONDIDA });
    await caixa(w, '9f2c').trigger('click');
    await continuar(w);
    await aparece(w, 'conferir');
    return w;
  };

  it('"Algumas" vai ao servidor na hora; os valores marcados vão pela chave', async () => {
    const w = await ateConferir();
    expect(servidor.responder).toHaveBeenNthCalledWith(1, 812, ALGUMAS);
    expect(servidor.responder).toHaveBeenNthCalledWith(2, 812, {
      ...ALGUMAS,
      valores_cliente: MARCADAS,
    });
    expect(marca(w, 'entram-como-clientes').text()).toBe(
      '5 entram como clientes.'
    );
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('o servidor recusa os valores (422 `resposta_desconhecida`): a tela lê de novo, diz que a lista mudou e a pergunta volta sem nada marcado', async () => {
    const w = await ateAPerguntaDosValores();
    servidor.responder.mockRejectedValueOnce(
      erroHttp(422, { error: 'resposta_desconhecida' })
    );
    const outrosValores = {
      ...DOS_VALORES,
      valores: [{ chave: 'c3d4', valor: 'Cliente', linhas: 8 }],
    };
    servidor.leitura.mockResolvedValue({
      data: leitura({
        perguntas: [{ id: 'clientes' }, outrosValores],
        respostas: ALGUMAS,
      }),
    });
    await caixa(w, '9f2c').trigger('click');
    await continuar(w);
    await aparece(w, 'lista-mudou');
    expect(marca(w, 'lista-mudou').attributes('role')).toBe('alert');
    expect(marca(w, 'lista-mudou').text()).toBe(
      'Esta lista mudou enquanto você conferia. Mostrei como está agora.'
    );
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe(
      'valores_cliente'
    );
    expect(w.find('[data-resposta="9f2c"]').exists()).toBe(false);
    expect(w.findAll('[role="checkbox"][aria-checked="true"]')).toHaveLength(0);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('o servidor recusa o trazer (422 `falta_valores_cliente`): a pessoa vai à pergunta, que diz o que falta', async () => {
    const w = await ateConferir();
    servidor.trazer.mockRejectedValueOnce(
      erroHttp(422, { error: 'falta_valores_cliente' })
    );
    servidor.leitura.mockResolvedValue({ data: COM_A_PERGUNTA });
    await marca(w, 'trazer-confirmar').trigger('click');
    await naPergunta(w, 'valores_cliente');
    expect(marca(w, 'erro-da-pergunta').attributes('role')).toBe('alert');
    expect(marca(w, 'erro-da-pergunta').text()).toBe(
      'Antes de trazer, diga quem é cliente.'
    );
    // Como em toda recusa de pergunta: o foco vai para a primeira opção, que
    // aponta para a frase.
    await esperarPor(() =>
      expect(document.activeElement).toBe(caixa(w, 'preenchidas').element)
    );
    expect(caixa(w, 'preenchidas').attributes('aria-describedby')).toBe(
      marca(w, 'erro-da-pergunta').attributes('id')
    );
    expect(marca(w, 'lista-mudou').exists()).toBe(false);
    expect(alertar).not.toHaveBeenCalled();

    // Marcou e continuou: grava e volta ao Conferir, pronto para trazer.
    servidor.responder.mockResolvedValueOnce({ data: RESPONDIDA });
    await caixa(w, 'preenchidas').trigger('click');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await continuar(w);
    await aparece(w, 'conferir');
    expect(servidor.responder).toHaveBeenLastCalledWith(812, {
      ...ALGUMAS,
      valores_cliente: { modo: 'preenchidas' },
    });
    w.unmount();
  });
});
