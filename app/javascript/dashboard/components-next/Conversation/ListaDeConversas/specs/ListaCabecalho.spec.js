import { mount } from '@vue/test-utils';
import ListaCabecalho from '../ListaCabecalho.vue';
import ChipDoStatus from '../ChipDoStatus.vue';
import { criarI18n } from './apoio';

const dispatch = vi.fn();
const updateUISettings = vi.fn();
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ uiSettings: { value: {} }, updateUISettings }),
}));

const i18n = criarI18n({
  CHAT_LIST: {
    SORT_ORDER_ITEMS: { priority_desc: { TEXT: 'Prioridade: Altas primeiro' } },
  },
});

const montar = (props = {}) =>
  mount(ListaCabecalho, {
    props: {
      pageTitle: 'Conversas',
      activeStatus: 'open',
      activeSortBy: 'last_activity_at_desc',
      ...props,
    },
    global: { plugins: [i18n] },
    attachTo: document.body,
  });

const escolher = async (wrapper, seletor, texto) => {
  await wrapper.find(`${seletor} button`).trigger('click');
  const opcao = wrapper
    .findAll(`${seletor} li[role="option"]`)
    .find(li => li.text() === texto);
  await opcao.trigger('click');
};

describe('ListaCabecalho (#2202)', () => {
  beforeAll(() => {
    Element.prototype.scrollIntoView = vi.fn();
  });
  beforeEach(() => {
    dispatch.mockClear();
    updateUISettings.mockClear();
  });

  it('dois botões com palavra: "Recentes" e "Filtrar", sem <select>', () => {
    const wrapper = montar();
    expect(wrapper.find('[data-botao-ordem] button').text()).toBe('Recentes');
    expect(wrapper.find('[data-botao-filtrar] button').text()).toBe('Filtrar');
    expect(wrapper.find('select').exists()).toBe(false);
    wrapper.unmount();
  });

  it('"Filtrar" > "Adiadas" manda status=snoozed num toque', async () => {
    const wrapper = montar();
    await escolher(wrapper, '[data-botao-filtrar]', 'Adiadas');
    expect(wrapper.emitted('basicFilterChange')).toEqual([
      ['snoozed', 'status'],
    ]);
    expect(dispatch).toHaveBeenCalledWith('setChatStatusFilter', 'snoozed');
    wrapper.unmount();
  });

  it('"Mais filtros…" abre o filtro avançado e não muda o status', async () => {
    const wrapper = montar();
    await escolher(wrapper, '[data-botao-filtrar]', 'Mais filtros…');
    expect(wrapper.emitted('filtersModal')).toHaveLength(1);
    expect(wrapper.emitted('basicFilterChange')).toBeUndefined();
    wrapper.unmount();
  });

  it('"Quem espera há mais tempo" troca a ordem e mostra a linha de ajuda', async () => {
    const wrapper = montar();
    await escolher(wrapper, '[data-botao-ordem]', 'Quem espera há mais tempo');
    expect(wrapper.emitted('basicFilterChange')).toEqual([
      ['waiting_since_asc', 'sort'],
    ]);
    await wrapper.setProps({ activeSortBy: 'waiting_since_asc' });
    expect(wrapper.find('[data-botao-ordem] button').text()).toBe(
      'Quem espera'
    );
    expect(wrapper.find('[data-ajuda-da-ordem]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('quem tinha outra ordem guardada continua nela, com o nome dela', () => {
    const wrapper = montar({ activeSortBy: 'priority_desc' });
    expect(wrapper.find('[data-botao-ordem] button').text()).toBe(
      'Prioridade: Altas primeiro'
    );
    wrapper.unmount();
  });

  it('o ✕ do chip volta para as abertas', async () => {
    const wrapper = montar({ activeStatus: 'snoozed' });
    wrapper.vm.voltarParaAbertas();
    expect(wrapper.emitted('basicFilterChange')).toEqual([['open', 'status']]);
    wrapper.unmount();
  });
});

describe('ChipDoStatus (#2202)', () => {
  it('"Adiadas ✕" e "Resolvidas ✕"; o ✕ pede para voltar às abertas', async () => {
    const chip = status =>
      mount(ChipDoStatus, { props: { status }, global: { plugins: [i18n] } });
    expect(chip('snoozed').text()).toBe('Adiadas');
    expect(chip('resolved').text()).toBe('Resolvidas');
    const adiadas = chip('snoozed');
    await adiadas.find('button').trigger('click');
    expect(adiadas.emitted('limpar')).toHaveLength(1);
  });

  it('"Pendentes ✕" e "Todos os status ✕": todo status fora das abertas tem nome', () => {
    const chip = status =>
      mount(ChipDoStatus, { props: { status }, global: { plugins: [i18n] } });
    expect(chip('pending').text()).toBe('Pendentes');
    expect(chip('all').text()).toBe('Todos os status');
  });
});
