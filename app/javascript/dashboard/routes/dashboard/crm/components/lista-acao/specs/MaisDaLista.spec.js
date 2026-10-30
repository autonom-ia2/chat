import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import crmEn from 'dashboard/i18n/locale/en/crm.json';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ListaAcao from '../ListaAcao.vue';
import BarraDaLista from '../BarraDaLista.vue';
import MenuDeAcoes from '../MenuDeAcoes.vue';

// #2379 — "Mais" da Lista nova: Organizar por, Escolher o que aparece e Listas
// guardadas, com a lista de verdade montada (API simulada).
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getCards: vi.fn(),
    cardsGroupSummary: vi.fn(),
    exportCards: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ subscribeAction: () => () => {}, dispatch: vi.fn() }),
  useMapGetter: () => ref(false),
}));

const EU = 2;
const cards = [
  {
    id: 11,
    title: 'Plano anual',
    contact: { name: 'Juliana Castro' },
    stage_id: 100,
    stage: { id: 100, name: 'Proposta', color: '#2563eb' },
    owner_id: EU,
    current_responsible: { type: 'agent', id: EU, name: 'Bruna' },
    value_cents: 64000,
    currency: 'BRL',
    priority: 'high',
    status: 'open',
    action_group: 'demais',
  },
  {
    id: 12,
    title: 'Plano empresarial',
    contact: { name: 'Paulo Henrique' },
    stage_id: 101,
    stage: { id: 101, name: 'Fechamento', color: '#0891b2' },
    owner_id: null,
    current_responsible: { type: 'bot', id: 9, name: 'Assistente Bia' },
    value_cents: 150000,
    currency: 'BRL',
    status: 'open',
    action_group: 'demais',
  },
];
const resumos = {
  acao: { groups: [{ key: 'demais', count: 2 }] },
  stage: {
    groups: [
      { key: 100, count: 5, sum_cents: 320000, currency: 'BRL' },
      { key: 101, count: 1, sum_cents: 150000, currency: 'BRL' },
    ],
  },
  quem_cuida: {
    groups: [
      { key: `agent:${EU}`, count: 3, sum_cents: 64000, label: 'Bruna' },
      { key: 'bot:9', count: 7, sum_cents: 150000, label: 'Assistente Bia' },
    ],
  },
};

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en: crmEn } });

const montar = (props = {}) =>
  mount(ListaAcao, {
    attachTo: document.body,
    props: {
      pipelineId: 7,
      filtros: {},
      meuId: EU,
      meuNome: 'Bruna',
      fuso: 'America/Sao_Paulo',
      podeVerValor: true,
      podeMexer: true,
      ...props,
    },
    global: { plugins: [i18n()] },
  });

const ultimoPedido = () => CrmKanbanAPI.getCards.mock.calls.at(-1)[0];
const pediuResumo = groupBy =>
  CrmKanbanAPI.cardsGroupSummary.mock.calls.some(
    ([params]) => params.group_by === groupBy
  );
const cabecalhos = wrapper =>
  wrapper.findAll('[data-cab-grupo] h2').map(h2 => h2.text());
const escolherNoMais = async (wrapper, chave) => {
  wrapper.findComponent(BarraDaLista).vm.$emit('mais', chave);
  await flushPromises();
};

describe('Mais da Lista nova (#2379)', () => {
  beforeEach(() => {
    window.localStorage.clear();
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
    CrmKanbanAPI.getCards.mockResolvedValue({
      data: { payload: cards, meta: { count: 2 } },
    });
    CrmKanbanAPI.cardsGroupSummary.mockImplementation(async params => ({
      data: { payload: resumos[params.group_by] },
    }));
  });
  afterEach(() => {
    vi.clearAllMocks();
    document.body.innerHTML = '';
  });

  it('mostra os três itens no "Mais", na ordem do mockup', () => {
    const wrapper = mount(BarraDaLista, {
      props: {
        quem: 'todos',
        aba: 'aberto',
        rotulosDasAbas: {},
        podeBaixar: true,
        podeMarcar: true,
      },
      global: { plugins: [i18n()] },
    });
    expect(
      wrapper
        .findComponent(MenuDeAcoes)
        .props('itens')
        .map(item => item.rotulo)
    ).toEqual([
      'Download spreadsheet',
      'Sort by',
      'Choose what shows',
      'Saved lists',
      'Select several',
    ]);
  });

  it('organiza por quem cuida: pede a ordem e mostra cada grupo com número e soma', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(ultimoPedido()).toMatchObject({ sort: 'acao' });

    await escolherNoMais(wrapper, 'organizar');
    const opcoes = document.querySelectorAll('[data-organizar]');
    expect([...opcoes].map(opcao => opcao.textContent.trim())).toEqual([
      'What to do first (default)',
      'Stage',
      'Who takes care',
      'Nearest follow-up',
      'Highest value',
      'Idle the longest',
      'Name',
    ]);
    document.querySelector('[data-organizar="quem_cuida"]').click();
    await flushPromises();

    expect(ultimoPedido()).toMatchObject({ sort: 'quem_cuida' });
    expect(pediuResumo('quem_cuida')).toBe(true);
    const textos = cabecalhos(wrapper);
    expect(textos[0]).toContain('You');
    expect(textos[0]).toContain('3 clients');
    expect(textos[0]).toContain('640.00');
    expect(textos[1]).toContain('Assistente Bia');
    expect(textos[1]).toContain('7 clients');
    // O cabeçalho já diz quem cuida: a linha não repete.
    expect(wrapper.find('[data-campo-linha="quem_cuida"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });

  it('organiza por nome em lista única, sem cabeçalho de grupo', async () => {
    const wrapper = montar();
    await flushPromises();
    await escolherNoMais(wrapper, 'organizar');
    document.querySelector('[data-organizar="nome"]').click();
    await flushPromises();
    expect(ultimoPedido()).toMatchObject({ sort: 'nome' });
    expect(cabecalhos(wrapper)).toEqual([]);
    expect(wrapper.findAll('[data-lista-acao-linha]')).toHaveLength(2);
    wrapper.unmount();
  });

  it('esconde "Maior valor" e a soma de quem não vê o valor de venda', async () => {
    const wrapper = montar({ podeVerValor: false });
    await flushPromises();
    await escolherNoMais(wrapper, 'organizar');
    expect(document.querySelector('[data-organizar="valor"]')).toBeNull();
    document.querySelector('[data-organizar="etapa"]').click();
    await flushPromises();
    expect(wrapper.find('[data-lista-acao-soma]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('escolhe o que aparece: desliga o valor, liga a prioridade e lembra no navegador', async () => {
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findAll('[data-campo-linha="valor"]')).toHaveLength(2);

    await escolherNoMais(wrapper, 'escolher');
    const linha = chave =>
      document.querySelector(
        `[data-lista-acao-campos] [data-campo="${chave}"]`
      );
    linha('valor').querySelector('input').click();
    linha('prioridade').querySelector('input').click();
    await flushPromises();

    expect(wrapper.find('[data-campo-linha="valor"]').exists()).toBe(false);
    expect(wrapper.find('[data-campo-linha="prioridade"]').text()).toBe(
      'Priority: High'
    );
    linha('prioridade').querySelector('[data-subir]').click();
    await flushPromises();
    const ordem = [
      ...document.querySelectorAll('[data-lista-acao-campos] [data-campo]'),
    ].map(item => item.dataset.campo);
    expect(ordem.indexOf('prioridade')).toBe(ordem.indexOf('novidade') - 1);
    wrapper.unmount();

    const denovo = montar();
    await flushPromises();
    expect(denovo.find('[data-campo-linha="valor"]').exists()).toBe(false);
    expect(denovo.find('[data-campo-linha="prioridade"]').exists()).toBe(true);
    denovo.unmount();
  });

  it('abre uma visualização salva antiga da Lista de sempre', async () => {
    const antiga = {
      id: 31,
      name: 'Por etapa',
      user_id: 99,
      visibility: 'account',
      config: {
        filters: { ownerId: EU, result: 'open' },
        sort: null,
        group_by: 'stage',
        columns: {
          columnOrder: ['select', 'title', 'stage', 'priority', 'value'],
          columnVisibility: { stage: true, priority: true, value: false },
        },
        density: 'compact',
      },
    };
    const wrapper = montar({ listas: [antiga] });
    await flushPromises();
    await escolherNoMais(wrapper, 'listas');

    const item = document.querySelector('[data-lista-guardada="31"]');
    expect(item.textContent).toContain('Por etapa');
    // Lista de outra pessoa: só abre (mudar quem vê e apagar são de quem criou).
    expect(item.querySelector('[data-lista-apagar]')).toBeNull();
    item.querySelector('[data-lista-abrir]').click();
    await flushPromises();

    expect(wrapper.emitted('abrirLista')[0][0]).toEqual(antiga);
    expect(ultimoPedido()).toMatchObject({ sort: 'etapa' });
    expect(pediuResumo('stage')).toBe(true);
    const textos = cabecalhos(wrapper);
    expect(textos[0]).toContain('Proposta');
    expect(textos[0]).toContain('5 clients');
    expect(textos[0]).toContain('3,200.00');
    expect(wrapper.find('[data-campo-linha="valor"]').exists()).toBe(false);
    expect(wrapper.find('[data-campo-linha="prioridade"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('guarda a lista como está agora, no formato que a Lista de sempre também abre', async () => {
    const wrapper = montar({
      configAtual: { filters: { ownerId: EU }, columns: {}, density: 'x' },
    });
    await flushPromises();
    await escolherNoMais(wrapper, 'organizar');
    document.querySelector('[data-organizar="etapa"]').click();
    await flushPromises();
    await escolherNoMais(wrapper, 'listas');

    const campo = document.querySelector('[data-lista-acao-guardar] input');
    campo.value = 'Meus por etapa';
    campo.dispatchEvent(new Event('input'));
    document.querySelector('[data-lista-guardar]').click();
    await flushPromises();

    const [enviado] = wrapper.emitted('guardarLista')[0];
    expect(enviado).toMatchObject({
      name: 'Meus por etapa',
      visibility: 'private_view',
      pipeline_id: 7,
      config: {
        filters: { ownerId: EU },
        group_by: 'stage',
        sort: null,
        lista_acao: { versao: 1, organizar: 'etapa' },
      },
    });
    wrapper.unmount();
  });

  it('mostra a ficha da lista antiga com a nota da IA e deixa tirar', async () => {
    const wrapper = montar({ filtros: { scoreMin: '70' } });
    await flushPromises();
    const ficha = wrapper.find('[data-lista-acao-ficha-nota]');
    expect(ficha.text()).toContain('Old list: only the hottest');
    await ficha.find('button').trigger('click');
    expect(wrapper.emitted('tirarNota')).toHaveLength(1);
    wrapper.unmount();
  });
});
