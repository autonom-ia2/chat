import { defineComponent, h, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentesListaEntrada from '../entrada/AgentesListaEntrada.vue';

// O seletor da rota autonomia_agents_index (DECISOES.md item 1): flag desligada = a lista antiga,
// sem carregar o pedaço novo e sem chamada nova de API; ligada = a lista nova. Decide uma vez só.
const store = vi.hoisted(() => ({ getters: {} }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const api = vi.hoisted(() => ({ semana: vi.fn(), canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));

const carregouNova = vi.hoisted(() => vi.fn());
vi.mock('../pages/AgentesListaPage.vue', async () => {
  carregouNova();
  const { defineComponent: definir, h: hh } = await import('vue');
  return {
    __esModule: true,
    default: definir({
      name: 'AgentesListaPage',
      setup: () => () => hh('div', { 'data-nova': '' }),
    }),
  };
});
vi.mock('../../pages/AgentsHubPage.vue', async () => {
  const { defineComponent: definir, h: hh } = await import('vue');
  return {
    default: definir({
      name: 'AgentsHubPage',
      inheritAttrs: false,
      setup: () => () => hh('div', { 'data-antiga': '' }),
    }),
  };
});

const conta = {
  id: 3,
  autonomia_agents_enabled: true,
  features: { autonomia_agents_journey: false },
};

const comConta = dados => {
  store.getters = {
    getCurrentAccountId: 3,
    'accounts/getAccount': () => dados,
  };
};

describe('AgentesListaEntrada', () => {
  it('keeps the old list with the flag off, without loading the new one nor calling the API', async () => {
    comConta({ ...conta });
    const wrapper = mount(AgentesListaEntrada);
    await flushPromises();

    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
    expect(carregouNova).not.toHaveBeenCalled();
    expect(api.semana).not.toHaveBeenCalled();
    expect(api.canaisOcupados).not.toHaveBeenCalled();
  });

  it('keeps the old list when the Agents module is off on the account', async () => {
    comConta({
      ...conta,
      autonomia_agents_enabled: false,
      features: { autonomia_agents_journey: true },
    });
    const wrapper = mount(AgentesListaEntrada);
    await flushPromises();
    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
  });

  it('shows the new list with the flag on', async () => {
    comConta({ ...conta, features: { autonomia_agents_journey: true } });
    const wrapper = mount(AgentesListaEntrada);
    await flushPromises();

    expect(wrapper.find('[data-nova]').exists()).toBe(true);
    expect(wrapper.find('[data-antiga]').exists()).toBe(false);
  });

  it('does not swap the page when the account changes in the store', async () => {
    const atual = { ...conta, features: { autonomia_agents_journey: false } };
    comConta(atual);
    const Casca = defineComponent({
      setup: () => () => h(AgentesListaEntrada),
    });
    const wrapper = mount(Casca);
    await flushPromises();

    atual.features = { autonomia_agents_journey: true };
    comConta({ ...atual });
    await nextTick();
    await flushPromises();

    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
  });
});
