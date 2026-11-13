import { withFullI18n } from 'test-i18n';
import {
  abrir,
  aparece,
  continuar,
  erroHttp,
  escolher,
  esperarPor,
  marca,
} from '../trazer/apoioDaPagina';
import { esquecerMemoriaDaDemo } from '../../fonte/trazerFonte';
import { esquecerOsSegurosDaDemo } from '../../fonte/trazerSegurosFonte';
import { DURACAO_DA_TRAZIDA_MS } from '../../demo/trazer';
import { daCarteira } from './apoio';

// #2897 — "Trazer minha lista" na conta que tem a carteira de seguros, com a
// página inteira (pages/TrazerListaPage.vue), o texto de verdade em pt_BR e a
// planilha de exemplo da demonstração: a escolha de como trazer, a pergunta
// "Esta planilha tem seguros?", o Conferir com seguros e pessoas contados e o
// fim, que leva à aba Seguros.
withFullI18n('pt_BR');

const AGORA = Date.UTC(2026, 10, 13, 15);
// A demonstração leva DURACAO_DA_TRAZIDA_MS para trazer a lista; a folga cobre
// a consulta seguinte ao fim (a espera entre uma e outra chega a 5 s).
const ATE_TRAZER_TUDO_MS = DURACAO_DA_TRAZIDA_MS + 5000;

// A planilha de exemplo: 195 linhas entram (as mesmas da tela das listas), e
// cada linha é um seguro. 46 seguros são de quem já tem outro na planilha:
// 149 pessoas, das quais 15 já estavam na conta (demo/trazerSeguros.js).
const SEGUROS = 195;
const PESSOAS = 149;
const PESSOAS_NOVAS = 134;

const estado = vi.hoisted(() => ({ demo: 'cheio' }));
const empurrar = vi.hoisted(() => vi.fn());
// A conta aberta, como o servidor manda (fora da demonstração).
const conta = vi.hoisted(() => ({ carteira_seguros: true }));

// O servidor de mentira (fora da demonstração a tela fala com ele).
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

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return { useAccount: () => ({ currentAccount: ref(conta) }) };
});

vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: () => estado.demo,
}));

// As fontes de verdade, sem as esperas da demonstração.
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

vi.mock('../../fonte/trazerSegurosFonte', async importOriginal => {
  const original = await importOriginal();
  return {
    ...original,
    trazerSegurosFonte: opcoes =>
      original.trazerSegurosFonte({
        ...opcoes,
        carregarDemo: () => import('../../demo/trazerSeguros.js'),
      }),
  };
});

// Telas inteiras montam devagar numa máquina carregada (a CI também): o limite
// de 5 s por teste é de relógio, não de lógica.
vi.setConfig({ testTimeout: 30000 });

// A página baixa as telas da carteira e a demonstração por import() dinâmico,
// que leva tempo de verdade: carregadas antes, cada teste fica só por conta do
// relógio falso.
beforeAll(async () => {
  await import('../../components/carteira/trazer/TrazerSeguros.vue');
  await import('../../demo/trazer.js');
  await import('../../demo/trazerSeguros.js');
}, 60000);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout', 'Date'] });
  vi.setSystemTime(AGORA);
  estado.demo = 'cheio';
  conta.carteira_seguros = true;
  empurrar.mockClear();
  esquecerMemoriaDaDemo();
  esquecerOsSegurosDaDemo();
  Object.values(servidor).forEach(pedido => pedido.mockReset());
  servidor.listas.mockRejectedValue(erroHttp(500));
});

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

const peca = (w, nome) => w.find(daCarteira(nome));
const apareceDaCarteira = (w, nome) =>
  esperarPor(() => expect(peca(w, nome).exists()).toBe(true));

const escolherPlanilha = async w => {
  await apareceDaCarteira(w, 'origem');
  await peca(w, 'origem').trigger('click');
  await aparece(w, 'soltar-arquivo');
};

// Da escolha de como trazer até "Esta planilha tem seguros?".
const irAteAPerguntaDosSeguros = async w => {
  await escolherPlanilha(w);
  await marca(w, 'usar-exemplo').trigger('click');
  await aparece(w, 'pergunta');
  await escolher(w, 'sim_todas');
  await continuar(w);
  await esperarPor(() =>
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('telefone')
  );
  await escolher(w, 'da_pessoa');
  await continuar(w);
  await apareceDaCarteira(w, 'pergunta-de-seguros');
};

const responderDosSeguros = (w, resposta) =>
  w
    .get(`${daCarteira('resposta-dos-seguros')}[data-resposta="${resposta}"]`)
    .trigger('click');

const irAteConferirSeguros = async w => {
  await irAteAPerguntaDosSeguros(w);
  await responderDosSeguros(w, 'sim');
  await apareceDaCarteira(w, 'conferir-seguros');
};

describe('como trazer', () => {
  it('a conta de seguros escolhe primeiro como trazer, e só há o cartão Planilha', async () => {
    const w = await abrir();
    await apareceDaCarteira(w, 'origem');

    expect(w.get('h1').text()).toBe(
      'Como você quer trazer as pessoas e os seguros?'
    );
    expect(w.findAll(daCarteira('origem'))).toHaveLength(1);
    expect(peca(w, 'origem').attributes('data-origem')).toBe('planilha');
    expect(peca(w, 'origem').text()).toContain('Planilha');
    // O cartão nasce ligado.
    expect(peca(w, 'como-trazer').findAll('button[disabled]')).toHaveLength(0);
    // Antes da escolha não há onde soltar o arquivo.
    expect(marca(w, 'soltar-arquivo').exists()).toBe(false);
    w.unmount();
  });

  it('Planilha leva à tela de enviar, a mesma das listas', async () => {
    const w = await abrir();
    await escolherPlanilha(w);

    expect(peca(w, 'origem').exists()).toBe(false);
    expect(w.get('h1').text()).toBe('Traga sua lista. A gente organiza.');
    expect(marca(w, 'usar-exemplo').exists()).toBe(true);
    w.unmount();
  });

  it('fora da demonstração, quem diz que a conta tem a carteira é o servidor', async () => {
    estado.demo = null;
    const w = await abrir();
    await escolherPlanilha(w);

    expect(marca(w, 'usar-exemplo').exists()).toBe(false);
    w.unmount();
  });
});

describe('a pergunta dos seguros', () => {
  it('vem depois das outras perguntas, com as duas respostas ligadas', async () => {
    const w = await abrir();
    await irAteAPerguntaDosSeguros(w);

    expect(w.get('h1').text()).toBe('Esta planilha tem seguros?');
    const respostas = w.findAll(daCarteira('resposta-dos-seguros'));
    expect(respostas.map(resposta => resposta.text())).toEqual([
      'Sim, tem os seguros',
      'Não, só as pessoas',
    ]);
    respostas.forEach(resposta =>
      expect(resposta.attributes('disabled')).toBeUndefined()
    );
    // A pergunta das listas não aparece junto.
    expect(marca(w, 'pergunta').exists()).toBe(false);
    w.unmount();
  });

  it('"Não, só as pessoas" leva ao Conferir das listas, sem nada de seguro', async () => {
    const w = await abrir();
    await irAteAPerguntaDosSeguros(w);
    await responderDosSeguros(w, 'nao');
    await aparece(w, 'conferir');

    expect(peca(w, 'conferir-seguros').exists()).toBe(false);
    expect(marca(w, 'trazer-confirmar').text()).toBe(
      `Trazer ${SEGUROS} pessoas`
    );
    w.unmount();
  });
});

describe('Conferir com seguros', () => {
  it('"Sim" mostra os seguros e as pessoas contados, com a palavra de cada número', async () => {
    const w = await abrir();
    await irAteConferirSeguros(w);

    expect(peca(w, 'conferir-seguros').attributes('data-conferidos')).toBe(
      'sim'
    );
    expect(w.get('h1').text()).toBe(
      `Achei ${SEGUROS} seguros de ${PESSOAS} pessoas.`
    );
    expect(peca(w, 'trazer-seguros').text()).toBe(
      `Trazer ${SEGUROS} seguros de ${PESSOAS} pessoas`
    );
    expect(peca(w, 'trazer-seguros').attributes('disabled')).toBeUndefined();
    // O Conferir das listas não aparece junto.
    expect(marca(w, 'conferir').exists()).toBe(false);
    w.unmount();
  });

  it('o tipo de cada seguro já vem pronto: os seguros por tipo e os das fichas de exemplo', async () => {
    const w = await abrir();
    await irAteConferirSeguros(w);

    const porTipo = peca(w, 'seguros-por-tipo').findAll('li');
    expect(porTipo.map(item => item.attributes('data-tipo'))).toEqual([
      'auto',
      'residencial',
      'vida',
      'empresarial',
      'outro',
    ]);
    porTipo.forEach(item => expect(item.text()).toContain('seguros'));
    expect(w.findAll(daCarteira('seguros-do-exemplo'))).toHaveLength(3);
    // O ramo que não coube em nenhum tipo diz como estava na planilha.
    expect(peca(w, 'exemplos-com-seguros').text()).toContain(
      'na planilha: Fiança locatícia'
    );
    w.unmount();
  });

  it('as linhas com problema no seguro ficam na mesma lista das outras', async () => {
    const w = await abrir();
    await irAteConferirSeguros(w);

    const doSeguro = w.findAll(daCarteira('problema-do-seguro'));
    expect(doSeguro.map(linha => linha.attributes('data-problema'))).toEqual([
      'falta_termina',
      'numero',
      'duplicado',
    ]);
    // A linha da pessoa com problema continua na lista, com o cartão dela.
    const daPessoa = marca(w, 'precisam-de-voce').get('[data-linha="62"]');
    expect(daPessoa.attributes('data-carteira')).toBeUndefined();
    // A que não se conserta aqui diz onde consertar; a repetida pede a escolha.
    expect(doSeguro[0].find(daCarteira('conserto-na-planilha')).exists()).toBe(
      true
    );
    expect(doSeguro[2].findAll('[data-opcao]')).toHaveLength(2);
    w.unmount();
  });
});

describe('o fim', () => {
  const trazerTudo = async w => {
    await irAteConferirSeguros(w);
    await peca(w, 'trazer-seguros').trigger('click');
    await aparece(w, 'andamento');
    await vi.advanceTimersByTimeAsync(ATE_TRAZER_TUDO_MS);
    await apareceDaCarteira(w, 'pronto-de-seguros');
  };

  it('diz quantos seguros chegaram e de quantas pessoas, e leva à aba Seguros', async () => {
    const w = await abrir();
    await trazerTudo(w);

    const pronto = peca(w, 'pronto-de-seguros');
    expect(pronto.text()).toContain(
      `${SEGUROS} seguros chegaram, de ${PESSOAS} pessoas.`
    );
    expect(peca(w, 'pessoas-novas').text()).toBe(
      `${PESSOAS_NOVAS} pessoas são novas aqui.`
    );
    expect(peca(w, 'ver-os-seguros').text()).toBe('Ver os seguros');

    await peca(w, 'ver-os-seguros').trigger('click');

    expect(empurrar).toHaveBeenLastCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros' },
    });
    w.unmount();
  });

  it('"Trazer outra lista" volta à escolha de como trazer', async () => {
    const w = await abrir();
    await trazerTudo(w);

    await peca(w, 'trazer-outra').trigger('click');
    await apareceDaCarteira(w, 'origem');

    expect(peca(w, 'pronto-de-seguros').exists()).toBe(false);
    w.unmount();
  });
});
