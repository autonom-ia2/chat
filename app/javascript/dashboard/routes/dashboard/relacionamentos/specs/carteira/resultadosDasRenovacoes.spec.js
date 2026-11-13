import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ResultadosDasRenovacoesPage from '../../pages/ResultadosDasRenovacoesPage.vue';
import { usarDemo } from '../../fonte/modoDemo';
import { assentar, carregarDemonstracao, daCarteira, erroHttp } from './apoio';

// "Resultados das renovações" (#2898) com o texto de verdade em pt_BR: quantos
// seguros a corretora renovou no período, por que perdeu os outros e quem
// renovou mais. Fora da demonstração os números vêm do servidor (o cliente de
// API é de mentira). Conta sem a carteira de seguros não chama rota nenhuma.
// Todos os dados são inventados.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { resultados: vi.fn() },
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(),
}));
// A conta aberta, como o servidor manda: `carteira_seguros` liga a carteira.
const conta = vi.hoisted(() => ({ carteira_seguros: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: conta } }),
}));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const roteador = useRouter();

const SEM_NINGUEM = {
  venceram: 0,
  renovou: 0,
  naoRenovou: 0,
  motivos: [],
  recortes: { tipo: [], seguradora: [], cuida: [] },
};
// O que o servidor manda em `GET seguros/resultados`.
const NUMEROS = {
  periodos: [
    {
      dias: 30,
      venceram: 9,
      renovou: 6,
      naoRenovou: 3,
      motivos: [
        { motivo: 'achou_caro', quantos: 1 },
        { motivo: 'outra_corretora', quantos: 0 },
        { motivo: 'vendeu_o_bem', quantos: 0 },
        { motivo: 'nao_respondeu', quantos: 0 },
        { motivo: 'cancelou', quantos: 0 },
        { motivo: 'outro', quantos: 1 },
        { motivo: 'sem_motivo', quantos: 1 },
      ],
      recortes: {
        tipo: [
          { tipo: 'auto', venceram: 6, renovou: 5 },
          { tipo: 'vida', venceram: 3, renovou: 1 },
          { tipo: 'residencial', venceram: 0, renovou: 0 },
        ],
        seguradora: [{ nome: 'Seguradora Atlântica', venceram: 9, renovou: 6 }],
        cuida: [],
      },
    },
    {
      dias: 90,
      venceram: 1,
      renovou: 1,
      naoRenovou: 0,
      motivos: [],
      recortes: {
        tipo: [{ tipo: 'auto', venceram: 1, renovou: 1 }],
        seguradora: [],
        cuida: [],
      },
    },
    { dias: 365, ...SEM_NINGUEM },
  ],
  vencem30: 4,
};
const servidorResponde = (numeros = NUMEROS) =>
  SegurosAPI.resultados.mockResolvedValue({ data: numeros });

let aberta;
const abrir = async ({ demo = null } = {}) => {
  usarDemo.mockReturnValue(demo);
  aberta = mount(ResultadosDasRenovacoesPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const escolherPeriodo = async (w, dias) => {
  w.getComponent(ChoiceSelect).vm.$emit('update:modelValue', dias);
  await assentar();
};
const heroi = w => w.get('[data-heroi-frase]').text();
// Cada barra: o nome e o que vai escrito ao lado.
const barras = (w, cartao) =>
  w
    .findAll(`${daCarteira(cartao)} ${daCarteira('barra-de-resultado')}`)
    .map(barra => barra.findAll('span').map(pedaco => pedaco.text()))
    .map(([nome, valor]) => [nome, valor]);
const larguras = (w, cartao) =>
  w
    .findAll(`${daCarteira(cartao)} [data-largura]`)
    .map(barra => barra.attributes('data-largura'));
const pilulas = w =>
  w
    .findAll(`${daCarteira('recorte')} [data-grupo]`)
    .map(pilula => pilula.attributes('data-grupo'));

beforeAll(async () => {
  await carregarDemonstracao();
  await import('../../demo/carteiraAjustes.js');
  await import('../../demo/carteiraResultados.js');
}, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  Element.prototype.scrollIntoView = vi.fn();
  conta.carteira_seguros = true;
  SegurosAPI.resultados.mockReset();
  roteador.push.mockClear();
  roteador.replace.mockClear();
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
});

describe('conta sem a carteira de seguros', () => {
  it('não chama rota nenhuma e volta para a lista', async () => {
    conta.carteira_seguros = false;

    const w = await abrir();

    expect(SegurosAPI.resultados).not.toHaveBeenCalled();
    expect(roteador.replace).toHaveBeenCalledWith({
      name: 'relationships_home',
    });
    expect(w.find('main').exists()).toBe(false);
  });
});

describe('os números do período', () => {
  it('abre nos últimos 30 dias: a frase do topo diz quantos renovou', async () => {
    servidorResponde();

    const w = await abrir();

    expect(SegurosAPI.resultados).toHaveBeenCalledTimes(1);
    expect(w.get('[data-titulo-da-tela]').text()).toBe(
      'Resultados das renovações'
    );
    expect(heroi(w)).toBe('Nos últimos 30 dias, você renovou 6 de 9 seguros.');
    expect(w.getComponent(ChoiceSelect).props('modelValue')).toBe(30);
    expect(
      w
        .getComponent(ChoiceSelect)
        .props('options')
        .map(o => o.label)
    ).toEqual(['Últimos 30 dias', 'Últimos 90 dias', 'Últimos 12 meses']);
  });

  it('a ação principal leva aos seguros que não renovaram no período', async () => {
    servidorResponde();
    const w = await abrir();
    const botao = w.get(daCarteira('ver-nao-renovaram'));

    expect(botao.text()).toBe('Ver os 3 que não renovaram');

    await clicar(w, daCarteira('ver-nao-renovaram'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', grupo: 'nao_renovaram_30' },
    });
  });

  it('"Por que não renovou": só o motivo que alguém escolheu, e quem ficou sem motivo', async () => {
    servidorResponde();

    const w = await abrir();

    expect(w.get(`${daCarteira('motivos')} h2`).text()).toBe(
      'Por que não renovou'
    );
    expect(barras(w, 'motivos')).toEqual([
      ['Achou caro', '1'],
      ['Outro motivo', '1'],
      ['Sem motivo', '1'],
    ]);
    expect(larguras(w, 'motivos')).toEqual(['33', '33', '33']);
  });

  it('o seguro cancelado com a renovação aberta e o motivo que a tela não conhece têm nome', async () => {
    const [de30, ...resto] = NUMEROS.periodos;
    servidorResponde({
      ...NUMEROS,
      periodos: [
        {
          ...de30,
          venceram: 12,
          naoRenovou: 6,
          motivos: [
            { motivo: 'achou_caro', quantos: 1 },
            { motivo: 'cancelou', quantos: 2 },
            { motivo: 'motivo_de_amanha', quantos: 3 },
            { motivo: 'sem_motivo', quantos: 0 },
          ],
        },
        ...resto,
      ],
    });

    const w = await abrir();

    expect(barras(w, 'motivos')).toEqual([
      ['Outro motivo', '3'],
      ['O seguro foi cancelado', '2'],
      ['Achou caro', '1'],
    ]);
    expect(w.get(daCarteira('motivos')).text()).not.toContain('MOTIVO');
    expect(w.get(daCarteira('motivos')).text()).not.toContain('Sem motivo');
  });

  it('"Quem renovou mais": só o recorte e a linha que têm número', async () => {
    servidorResponde();

    const w = await abrir();

    expect(pilulas(w)).toEqual(['tipo', 'seguradora']);
    expect(barras(w, 'recorte')).toEqual([
      ['Auto', '5 de 6 renovaram'],
      ['Vida', '1 de 3 renovou'],
    ]);
    expect(larguras(w, 'recorte')).toEqual(['83', '33']);
  });

  it('trocar o recorte mostra as linhas dele', async () => {
    servidorResponde();
    const w = await abrir();

    await clicar(w, `${daCarteira('recorte')} [data-grupo="seguradora"]`);

    expect(barras(w, 'recorte')).toEqual([
      ['Seguradora Atlântica', '6 de 9 renovaram'],
    ]);
    expect(
      w
        .get(`${daCarteira('recorte')} [data-grupo="seguradora"]`)
        .attributes('aria-pressed')
    ).toBe('true');
  });

  it('diz quantos vencem nos próximos 30 dias e leva até eles', async () => {
    servidorResponde();
    const w = await abrir();

    expect(w.get(daCarteira('vencem-30')).text()).toContain(
      'Vencem nos próximos 30 dias: 4 seguros.'
    );
    expect(w.get(daCarteira('ver-quais')).text()).toBe('Ver quem vence');

    await clicar(w, daCarteira('ver-quais'));

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros', grupo: 'vence_30_dias' },
    });
  });
});

describe('trocar o período', () => {
  it('muda tudo junto, sem ir de novo ao servidor', async () => {
    servidorResponde();
    const w = await abrir();

    await escolherPeriodo(w, 90);

    expect(heroi(w)).toBe('Nos últimos 90 dias, você renovou 1 de 1 seguro.');
    expect(SegurosAPI.resultados).toHaveBeenCalledTimes(1);
    expect(barras(w, 'recorte')).toEqual([['Auto', '1 de 1 renovou']]);
  });

  it('período em que todos renovaram: sem botão de quem não renovou e sem motivos', async () => {
    servidorResponde();
    const w = await abrir();

    await escolherPeriodo(w, 90);

    expect(w.find(daCarteira('ver-nao-renovaram')).exists()).toBe(false);
    expect(w.find(daCarteira('motivos')).exists()).toBe(false);
    expect(w.findAll('button[disabled]')).toHaveLength(0);
  });

  it('com um recorte só, não há o que escolher: as pílulas somem', async () => {
    servidorResponde();
    const w = await abrir();

    await escolherPeriodo(w, 90);

    expect(pilulas(w)).toEqual([]);
    expect(w.find(daCarteira('recorte')).exists()).toBe(true);
  });

  it('o recorte escolhido que não existe no período novo cede a vez ao primeiro que existe', async () => {
    servidorResponde();
    const w = await abrir();
    await clicar(w, `${daCarteira('recorte')} [data-grupo="seguradora"]`);

    await escolherPeriodo(w, 90);

    expect(barras(w, 'recorte')).toEqual([['Auto', '1 de 1 renovou']]);
  });

  it('período sem nenhum seguro vencido: diz isso e não desenha nada vazio', async () => {
    servidorResponde();
    const w = await abrir();

    await escolherPeriodo(w, 365);

    expect(w.get(daCarteira('resultados-vazio')).text()).toBe(
      'Nenhum seguro venceu neste período.'
    );
    expect(w.find(daCarteira('resultados-heroi')).exists()).toBe(false);
    expect(w.find(daCarteira('motivos')).exists()).toBe(false);
    expect(w.find(daCarteira('recorte')).exists()).toBe(false);
    expect(w.find(daCarteira('barra-de-resultado')).exists()).toBe(false);
    expect(w.find(daCarteira('vencem-30')).exists()).toBe(true);
  });
});

describe('frases com um seguro só', () => {
  const UM_SO = {
    periodos: [
      {
        dias: 30,
        venceram: 1,
        renovou: 0,
        naoRenovou: 1,
        motivos: [{ motivo: 'nao_respondeu', quantos: 1 }],
        recortes: {
          tipo: [],
          seguradora: [],
          cuida: [{ nome: null, venceram: 1, renovou: 0 }],
        },
      },
      { dias: 90, ...SEM_NINGUEM },
      { dias: 365, ...SEM_NINGUEM },
    ],
    vencem30: 1,
  };

  it('o topo, o botão e a linha de baixo ficam no singular', async () => {
    servidorResponde(UM_SO);

    const w = await abrir();

    expect(heroi(w)).toBe('Nos últimos 30 dias, você renovou 0 de 1 seguro.');
    expect(w.get(daCarteira('ver-nao-renovaram')).text()).toBe(
      'Ver o que não renovou'
    );
    expect(w.get(daCarteira('vencem-30')).text()).toContain(
      'Vence nos próximos 30 dias: 1 seguro.'
    );
    expect(barras(w, 'motivos')).toEqual([['Não respondeu', '1']]);
  });

  it('seguro sem ninguém cuidando aparece como "Não informado"', async () => {
    servidorResponde(UM_SO);

    const w = await abrir();

    expect(barras(w, 'recorte')).toEqual([
      ['Não informado', '0 de 1 renovaram'],
    ]);
  });

  it('sem nenhum seguro vencendo nos próximos 30 dias, a linha de baixo some', async () => {
    servidorResponde({ ...UM_SO, vencem30: 0 });

    const w = await abrir();

    expect(w.find(daCarteira('vencem-30')).exists()).toBe(false);
  });
});

describe('carregando, erro e demonstração', () => {
  it('no erro, diz a frase e tentar de novo carrega a tela', async () => {
    SegurosAPI.resultados.mockRejectedValueOnce(erroHttp(500));
    const w = await abrir();

    expect(w.get(daCarteira('erro')).text()).toContain(
      'Não consegui mostrar os resultados. Tente de novo.'
    );

    servidorResponde();
    await clicar(w, `${daCarteira('erro')} button`);

    expect(w.find(daCarteira('erro')).exists()).toBe(false);
    expect(heroi(w)).toBe('Nos últimos 30 dias, você renovou 6 de 9 seguros.');
  });

  it('enquanto a resposta não chega, mostra o esqueleto', async () => {
    SegurosAPI.resultados.mockReturnValue(new Promise(() => {}));

    const w = await abrir();

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('resultados-heroi')).exists()).toBe(false);
  });

  it('"Seguros" volta para a aba Seguros', async () => {
    servidorResponde();
    const w = await abrir();

    await clicar(w, '[data-relacionamentos="voltar"]');

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros' },
    });
  });

  it('na demonstração lê a conta fictícia, sem ir ao servidor', async () => {
    const w = await abrir({ demo: 'cheio' });
    await assentar();

    expect(SegurosAPI.resultados).not.toHaveBeenCalled();
    expect(w.find(daCarteira('resultados-heroi')).exists()).toBe(true);
    expect(heroi(w)).toContain('Nos últimos 30 dias, você renovou 14 de ');
  });
});
