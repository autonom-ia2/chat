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
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';

// A página "Trazer minha lista" inteira (#2896, Fatia 3): o Desfazer de uma
// lista falando com o servidor de mentira. O servidor só marca a lista como
// "desfazendo" e responde na hora; a tela acompanha pelo histórico até ela
// virar "desfeito". O Desfazer aparece quando a fonte diz que tem
// (`temDesfazer`): as duas fontes dizem; a que não disser não o mostra.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 11, 15);
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;
// A primeira pergunta do histórico por uma lista em andamento (1,5 s) e a
// seguinte (mais 2,25 s): trazer/consultaComRecuo.js.
const PRIMEIRA_PERGUNTA_MS = 1500;
const SEGUNDA_PERGUNTA_MS = 2250;
const PROMESSA = 'Você pode desfazer quando quiser';
const NAO_PODE =
  'Esta lista ainda está sendo trazida. Quando terminar, você pode desfazer.';
const PAROU = 'O desfazer parou no meio.';
const SEM_ACESSO =
  'Você não pode trazer listas nesta conta. Peça a quem administra a conta.';

const estado = vi.hoisted(() => ({ demo: null, semDesfazer: false }));

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
  previaDoDesfazer: vi.fn(),
  desfazer: vi.fn(),
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

// A fonte de verdade, sem as esperas da demonstração. `semDesfazer` faz dela
// uma fonte que não tem o desfazer.
vi.mock('../../fonte/trazerFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerFonte: opcoes => {
      const fonte = original.trazerFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazer.js'),
        atraso: 0,
        atrasoDaLeitura: 0,
      });
      return estado.semDesfazer ? { ...fonte, temDesfazer: false } : fonte;
    },
  };
});

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

// Como o servidor: dá para desfazer a lista pronta (o resto, quem diz é o
// teste, em `extra`).
const doServidor = (situacao, extra = {}) => ({
  id: 700,
  arquivo: 'Clientes de setembro.xlsx',
  quando: '2026-11-08T14:03:00Z',
  quem: 'Marina Pavanelli',
  total: 195,
  situacao,
  porcentagem: 100,
  pode_tentar: false,
  pode_desfazer: situacao === 'pronto',
  ...extra,
});
const PREVIA = { tira: 162, ficam: 18, devolve: 15 };
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

const situacaoDaLinha = w => w.get('[data-lista] [data-situacao]').text();

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = null;
  estado.semDesfazer = false;
  alertar.mockClear();
  esquecerMemoriaDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockResolvedValue({ data: [doServidor('pronto')] });
  servidor.previaDoDesfazer.mockResolvedValue({ data: PREVIA });
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

describe('Desfazer uma lista, com o servidor', () => {
  // Abre a página e o diálogo da lista pronta, já com a prévia.
  const abrirDialogoDaLista = async () => {
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    await marca(w, 'desfazer').trigger('click');
    await aparece(w, 'dialogo-desfazer');
    return w;
  };
  const comAPrevia = async () => {
    const w = await abrirDialogoDaLista();
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    return w;
  };

  it('a lista pronta tem o botão, e o diálogo mostra antes o que o servidor diz que sai', async () => {
    const w = await comAPrevia();
    expect(servidor.previaDoDesfazer).toHaveBeenCalledWith(700);
    expect(
      w
        .findAll('[data-relacionamentos="desfazer-previa"] [data-linha]')
        .map(item => [
          item.attributes('data-linha'),
          item.findAll('p')[0].text(),
        ])
    ).toEqual([
      ['saem', '162 pessoas saem'],
      ['ficam', '18 pessoas ficam'],
      ['voltam', '15 pessoas voltam a ser como eram'],
    ]);
    expect(servidor.desfazer).not.toHaveBeenCalled();
    w.unmount();
  });

  it('Desfazer: a linha vira "Desfazendo…", sem botão, e a tela acompanha até "Desfeito"', async () => {
    const w = await comAPrevia();
    servidor.desfazer.mockResolvedValue({
      data: { id: 700, situacao: 'desfazendo' },
    });
    servidor.listas
      .mockReset()
      .mockResolvedValueOnce({ data: [doServidor('desfazendo')] })
      .mockResolvedValueOnce({ data: [doServidor('desfazendo')] })
      .mockResolvedValue({ data: [doServidor('desfeito')] });
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    expect(servidor.desfazer).toHaveBeenCalledWith(700);
    await esperarPor(() => expect(situacaoDaLinha(w)).toBe('Desfazendo…'));
    expect(marca(w, 'desfazer').exists()).toBe(false);
    // O botão que a pessoa clicou sumiu: o foco vai para a linha da lista, em
    // vez de cair no começo da página.
    const linha = w.get('[data-lista="700"]').element;
    await esperarPor(() => expect(document.activeElement).toBe(linha));
    // A tela pergunta de novo sozinha, sem piscar o esqueleto.
    await vi.advanceTimersByTimeAsync(PRIMEIRA_PERGUNTA_MS);
    expect(situacaoDaLinha(w)).toBe('Desfazendo…');
    expect(marca(w, 'carregando').exists()).toBe(false);
    await vi.advanceTimersByTimeAsync(SEGUNDA_PERGUNTA_MS);
    await esperarPor(() => expect(situacaoDaLinha(w)).toBe('Desfeito'));
    expect(marca(w, 'desfazer').exists()).toBe(false);
    // Desfeita, não há mais o que acompanhar.
    const perguntas = servidor.listas.mock.calls.length;
    await vi.advanceTimersByTimeAsync(20000);
    expect(servidor.listas).toHaveBeenCalledTimes(perguntas);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  // O servidor só recusa a lista que está entrando. A tela chega aí quando a
  // lista que parou no meio volta a ser trazida por outra aba antes do clique.
  const PARADA = { pode_tentar: true, pode_desfazer: true };
  const TRAZENDO_DE_NOVO = { porcentagem: 40 };

  it('a lista que voltou a ser trazida (422): o diálogo diz isso num alerta, com o foco nele, e a linha mostra como ela está', async () => {
    servidor.listas.mockResolvedValue({
      data: [doServidor('falhou', PARADA)],
    });
    const w = await comAPrevia();
    servidor.desfazer.mockRejectedValue(
      erroHttp(422, { error: 'nao_pode_desfazer' })
    );
    servidor.listas
      .mockReset()
      .mockResolvedValue({ data: [doServidor('trazendo', TRAZENDO_DE_NOVO)] });
    await w.get('[data-dialog]').trigger('submit');
    await aparece(w, 'desfazer-nao-pode');
    const alerta = marca(w, 'desfazer-nao-pode');
    expect(alerta.text()).toBe(NAO_PODE);
    expect(alerta.attributes('role')).toBe('alert');
    await esperarPor(() => expect(document.activeElement).toBe(alerta.element));
    // Não é "tente de novo": sem toast, e sobra só o botão de sair.
    expect(alertar).not.toHaveBeenCalled();
    expect(marca(w, 'desfazer-confirmar').exists()).toBe(false);
    await botao(w, 'Cancelar').trigger('click');
    await some(w, 'dialogo-desfazer');
    expect(situacaoDaLinha(w)).toBe('Trazendo 40%');
    expect(w.findAll('[data-lista] button')).toHaveLength(0);
    w.unmount();
  });

  it('a recusa (422) que vem já na prévia: o mesmo alerta, sem "tentar de novo"', async () => {
    servidor.listas
      .mockResolvedValueOnce({ data: [doServidor('falhou', PARADA)] })
      .mockResolvedValue({ data: [doServidor('trazendo', TRAZENDO_DE_NOVO)] });
    servidor.previaDoDesfazer.mockRejectedValue(
      erroHttp(422, { error: 'nao_pode_desfazer' })
    );
    const w = await abrirDialogoDaLista();
    await aparece(w, 'desfazer-nao-pode');
    expect(marca(w, 'desfazer-nao-pode').text()).toBe(NAO_PODE);
    expect(marca(w, 'dialogo-desfazer').text()).not.toContain(
      'Não consegui ver o que sai.'
    );
    expect(marca(w, 'desfazer-confirmar').exists()).toBe(false);
    w.unmount();
  });

  // Quem perdeu a permissão com a tela aberta: "tentar de novo" não resolve.
  it.each([
    ['na prévia', 'previaDoDesfazer', abrirDialogoDaLista],
    [
      'ao desfazer',
      'desfazer',
      async () => {
        const w = await comAPrevia();
        await w.get('[data-dialog]').trigger('submit');
        return w;
      },
    ],
  ])(
    'sem acesso (401) %s: o diálogo fecha e fica só a frase de sem acesso',
    async (_, pedido, chegarLa) => {
      servidor[pedido].mockRejectedValue(erroHttp(401));
      const w = await chegarLa();
      await aparece(w, 'sem-acesso');
      expect(marca(w, 'sem-acesso').text()).toBe(SEM_ACESSO);
      expect(marca(w, 'sem-acesso').attributes('role')).toBe('alert');
      await some(w, 'dialogo-desfazer');
      expect(marca(w, 'historico').exists()).toBe(false);
      expect(botao(w, 'Tentar de novo')).toBeUndefined();
      expect(alertar).not.toHaveBeenCalled();
      w.unmount();
    }
  );

  // O job do desfazer quebrou antes de a tela ler o histórico de novo: a
  // linha volta a "Pronto", mas a tela diz que não deu.
  it('o desfazer que quebra logo depois do pedido: a linha volta a "Pronto" e a tela avisa', async () => {
    const w = await comAPrevia();
    servidor.desfazer.mockResolvedValue({
      data: { id: 700, situacao: 'desfazendo' },
    });
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(alertar).toHaveBeenCalledWith(
        'Não consegui desfazer. Tente de novo.'
      )
    );
    expect(situacaoDaLinha(w)).toBe('Pronto');
    expect(marca(w, 'desfazer').exists()).toBe(true);
    w.unmount();
  });

  // A lista que parou no meio depois de pôr gente na base: a pessoa escolhe
  // continuar ou desfazer.
  it('a lista que parou no meio tem "Tentar de novo" e "Desfazer"; desfazer a leva a "Desfazendo…" e "Desfeito"', async () => {
    const parada = { pode_tentar: true, pode_desfazer: true };
    servidor.listas.mockResolvedValue({
      data: [doServidor('falhou', parada)],
    });
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(situacaoDaLinha(w)).toBe('Não consegui trazer esta lista.');
    expect(marca(w, 'tentar-de-novo').exists()).toBe(true);
    await marca(w, 'desfazer').trigger('click');
    await aparece(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    servidor.desfazer.mockResolvedValue({
      data: { id: 700, situacao: 'desfazendo' },
    });
    servidor.listas
      .mockReset()
      .mockResolvedValueOnce({ data: [doServidor('desfazendo')] })
      .mockResolvedValue({ data: [doServidor('desfeito')] });
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    expect(servidor.desfazer).toHaveBeenCalledWith(700);
    expect(servidor.confirmar).not.toHaveBeenCalled();
    await esperarPor(() => expect(situacaoDaLinha(w)).toBe('Desfazendo…'));
    expect(w.findAll('[data-lista] button')).toHaveLength(0);
    await vi.advanceTimersByTimeAsync(PRIMEIRA_PERGUNTA_MS);
    await esperarPor(() => expect(situacaoDaLinha(w)).toBe('Desfeito'));
    expect(w.findAll('[data-lista] button')).toHaveLength(0);
    w.unmount();
  });

  // O desfazer travou no servidor: a linha diz que parou, sem o selo
  // "Desfazendo…", e tem o botão "Continuar"; o clique pede de novo (o servidor
  // põe na fila outra vez) e a linha volta a "Desfazendo…".
  it('a lista cujo desfazer travou diz que parou e tem "Continuar", e pedir de novo a leva a "Desfazendo…"', async () => {
    servidor.listas.mockResolvedValue({
      data: [doServidor('desfazendo', { pode_desfazer: true })],
    });
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(marca(w, 'desfazer-parou').text()).toBe(PAROU);
    // Não está acontecendo nada: a linha não diz "Desfazendo…".
    expect(situacaoDaLinha(w)).toBe(PAROU);
    expect(w.get('[data-lista]').text()).not.toContain('Desfazendo…');
    expect(marca(w, 'desfazer').text()).toBe('Continuar');
    expect(marca(w, 'desfazer').attributes('aria-label')).toBe(
      'Continuar a desfazer a lista Clientes de setembro.xlsx'
    );
    // Travado, não adianta ficar perguntando: quem resolve é o clique.
    await vi.advanceTimersByTimeAsync(20000);
    expect(servidor.listas).toHaveBeenCalledTimes(1);
    await marca(w, 'desfazer').trigger('click');
    await aparece(w, 'dialogo-desfazer');
    await esperarPor(() =>
      expect(
        marca(w, 'desfazer-confirmar').attributes('disabled')
      ).toBeUndefined()
    );
    servidor.desfazer.mockResolvedValue({
      data: { id: 700, situacao: 'desfazendo' },
    });
    servidor.listas
      .mockReset()
      .mockResolvedValue({ data: [doServidor('desfazendo')] });
    await w.get('[data-dialog]').trigger('submit');
    await some(w, 'dialogo-desfazer');
    expect(servidor.desfazer).toHaveBeenCalledWith(700);
    await esperarPor(() => expect(marca(w, 'desfazer').exists()).toBe(false));
    expect(situacaoDaLinha(w)).toBe('Desfazendo…');
    expect(marca(w, 'desfazer-parou').exists()).toBe(false);
    // De volta à fila, a tela volta a acompanhar.
    const perguntas = servidor.listas.mock.calls.length;
    await vi.advanceTimersByTimeAsync(PRIMEIRA_PERGUNTA_MS);
    expect(servidor.listas.mock.calls.length).toBeGreaterThan(perguntas);
    expect(alertar).not.toHaveBeenCalled();
    w.unmount();
  });

  it('a lista pronta que o servidor diz que não dá para desfazer não tem o botão', async () => {
    servidor.listas.mockResolvedValue({
      data: [doServidor('pronto', { pode_desfazer: false })],
    });
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(situacaoDaLinha(w)).toBe('Pronto');
    expect(marca(w, 'desfazer').exists()).toBe(false);
    w.unmount();
  });

  it('o servidor caiu ao desfazer: avisa por toast e o diálogo continua aberto', async () => {
    const w = await comAPrevia();
    servidor.desfazer.mockRejectedValue(erroHttp(500));
    await w.get('[data-dialog]').trigger('submit');
    await esperarPor(() =>
      expect(alertar).toHaveBeenCalledWith(
        'Não consegui desfazer. Tente de novo.'
      )
    );
    expect(marca(w, 'dialogo-desfazer').exists()).toBe(true);
    expect(marca(w, 'desfazer-nao-pode').exists()).toBe(false);
    expect(situacaoDaLinha(w)).toBe('Pronto');
    w.unmount();
  });
});

describe('o Conferir e o Pronto dizem que dá para desfazer', () => {
  const enviar = async w => {
    const entrada = w.get('input[type="file"]');
    Object.defineProperty(entrada.element, 'files', {
      value: [new File(['nome;celular'], 'Clientes 2025.csv')],
      configurable: true,
    });
    await entrada.trigger('change');
    await aparece(w, 'conferir');
  };

  it('com o servidor', async () => {
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
    const w = await abrir();
    expect(w.findComponent(DialogoDesfazer).exists()).toBe(true);
    await enviar(w);
    expect(marca(w, 'conferir-sossego').text()).toBe(
      'Você pode desfazer quando quiser.'
    );
    await marca(w, 'trazer-confirmar').trigger('click');
    await aparece(w, 'pronto');
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer quando quiser, aqui embaixo.'
    );
    await esperarPor(() => expect(marca(w, 'desfazer').exists()).toBe(true));
    w.unmount();
  });

  it('na demonstração', async () => {
    estado.demo = 'cheio';
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

describe('a fonte que não tem o desfazer', () => {
  it('a lista pronta não tem o botão, o diálogo não é montado e a tela não promete desfazer', async () => {
    estado.semDesfazer = true;
    const w = await abrir();
    await esperarPor(() => expect(w.findAll('[data-lista]')).toHaveLength(1));
    expect(situacaoDaLinha(w)).toBe('Pronto');
    expect(marca(w, 'desfazer').exists()).toBe(false);
    expect(botao(w, 'Desfazer')).toBeUndefined();
    expect(w.findComponent(DialogoDesfazer).exists()).toBe(false);
    expect(w.text()).not.toContain(PROMESSA);
    w.unmount();
  });
});
