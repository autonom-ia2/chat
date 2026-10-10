import { defineComponent, h, nextTick, reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentePaginaEntrada from '../../entrada/AgentePaginaEntrada.vue';

// Seletor da rota autonomia_agent_panel (DECISOES.md item 1): flag desligada = AgentPanelPage com
// os mesmos {agentId, tab}, sem carregar a página nova e sem chamada nova de API; ligada = a página
// nova, com o :tab antigo traduzido para a gaveta. Decide uma vez só.
const store = vi.hoisted(() => ({ getters: {} }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const rota = vi.hoisted(() => ({ atual: null }));
vi.mock('vue-router', () => ({ useRoute: () => rota.atual }));

const api = vi.hoisted(() => ({ semana: vi.fn(), canaisOcupados: vi.fn() }));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: api }));
const agentesApi = vi.hoisted(() => ({ show: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: agentesApi }));

const carregouNova = vi.hoisted(() => vi.fn());
const montagensNova = vi.hoisted(() => ({ n: 0 }));
vi.mock('../../pages/AgentePage.vue', async () => {
  carregouNova();
  const { defineComponent: definir, h: hh } = await import('vue');
  return {
    __esModule: true,
    default: definir({
      name: 'AgentePage',
      props: { agentId: [String, Number], gaveta: String },
      setup: props => {
        montagensNova.n += 1;
        return () =>
          hh('div', {
            'data-nova': '',
            'data-agente': props.agentId,
            'data-gaveta': props.gaveta || '',
          });
      },
    }),
  };
});

const montagensAntiga = vi.hoisted(() => ({ n: 0 }));
vi.mock('../../../pages/AgentPanelPage.vue', async () => {
  const {
    defineComponent: definir,
    h: hh,
    onMounted: aoMontar,
  } = await import('vue');
  return {
    default: definir({
      name: 'AgentPanelPage',
      props: { agentId: [String, Number], tab: String },
      setup: (props, { attrs }) => {
        aoMontar(() => {
          montagensAntiga.n += 1;
        });
        return () =>
          hh('div', {
            'data-antiga': '',
            'data-props': JSON.stringify({ ...props }),
            'data-attrs': Object.keys(attrs).join(','),
          });
      },
    }),
  };
});

const conta = ligada => ({
  id: 3,
  autonomia_agents_enabled: true,
  features: { autonomia_agents_journey: ligada },
});

const comConta = dados => {
  store.getters = {
    getCurrentAccountId: 3,
    'accounts/getAccount': () => dados,
  };
};

const montar = (props, params = { agentId: '7' }) => {
  rota.atual = reactive({ params });
  return mount(AgentePaginaEntrada, { props });
};

describe('AgentePaginaEntrada', () => {
  beforeEach(() => {
    carregouNova.mockClear();
    montagensAntiga.n = 0;
  });

  describe('flag desligada', () => {
    it('gives AgentPanelPage exactly the route props, with the default test tab', async () => {
      comConta(conta(false));
      const wrapper = montar({ agentId: '7', tab: 'test' });
      await flushPromises();

      const antiga = wrapper.get('[data-antiga]');
      expect(JSON.parse(antiga.attributes('data-props'))).toEqual({
        agentId: '7',
        tab: 'test',
      });
      expect(antiga.attributes('data-attrs')).toBe('');
      expect(wrapper.find('[data-nova]').exists()).toBe(false);
    });

    it('does not load the new page nor call any new API', async () => {
      comConta(conta(false));
      montar(
        { agentId: '7', tab: 'knowledge' },
        { agentId: '7', tab: 'knowledge' }
      );
      await flushPromises();

      expect(carregouNova).not.toHaveBeenCalled();
      expect(api.semana).not.toHaveBeenCalled();
      expect(api.canaisOcupados).not.toHaveBeenCalled();
      expect(agentesApi.show).not.toHaveBeenCalled();
    });

    it('updates the old page tab in place, without remounting it', async () => {
      comConta(conta(false));
      const Casca = defineComponent({
        props: { tab: { type: String, default: 'test' } },
        setup: props => () =>
          h(AgentePaginaEntrada, { agentId: '7', tab: props.tab }),
      });
      rota.atual = reactive({ params: { agentId: '7' } });
      const wrapper = mount(Casca, { props: { tab: 'test' } });
      await flushPromises();

      await wrapper.setProps({ tab: 'channels' });
      await nextTick();

      expect(
        JSON.parse(wrapper.get('[data-antiga]').attributes('data-props')).tab
      ).toBe('channels');
      expect(montagensAntiga.n).toBe(1);
    });

    it('keeps the old page when the Agents module is off on the account', async () => {
      comConta({ ...conta(true), autonomia_agents_enabled: false });
      const wrapper = montar({ agentId: '7', tab: 'test' });
      await flushPromises();
      expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    });
  });

  describe('flag ligada', () => {
    it('opens the new page without a drawer when the URL has no tab', async () => {
      comConta(conta(true));
      const wrapper = montar({ agentId: '7', tab: 'test' });
      await flushPromises();

      const nova = wrapper.get('[data-nova]');
      expect(nova.attributes('data-agente')).toBe('7');
      expect(nova.attributes('data-gaveta')).toBe('');
      expect(wrapper.find('[data-antiga]').exists()).toBe(false);
    });

    it.each([
      ['test', 'testar'],
      ['knowledge', 'sabe'],
      ['channels', 'onde'],
      ['performance', 'conversas'],
      ['tune', ''],
      ['publish', ''],
    ])('maps the old tab %s to the drawer "%s"', async (tab, gaveta) => {
      comConta(conta(true));
      const wrapper = montar({ agentId: '7', tab }, { agentId: '7', tab });
      await flushPromises();
      expect(wrapper.get('[data-nova]').attributes('data-gaveta')).toBe(gaveta);
    });

    it('remounts the new page when the route switches to another agent', async () => {
      comConta(conta(true));
      const wrapper = montar({ agentId: '7', tab: 'test' });
      await flushPromises();
      const antes = montagensNova.n;

      await wrapper.setProps({ agentId: '8' });
      await flushPromises();
      expect(wrapper.get('[data-nova]').attributes('data-agente')).toBe('8');
      expect(montagensNova.n).toBe(antes + 1);
    });

    it('follows a tab change on the same route', async () => {
      comConta(conta(true));
      const wrapper = montar({ agentId: '7', tab: 'test' });
      await flushPromises();

      rota.atual.params = { agentId: '7', tab: 'knowledge' };
      await nextTick();
      expect(wrapper.get('[data-nova]').attributes('data-gaveta')).toBe('sabe');
    });
  });

  it('does not swap the page when the account changes in the store', async () => {
    const atual = conta(false);
    comConta(atual);
    const wrapper = montar({ agentId: '7', tab: 'test' });
    await flushPromises();

    comConta(conta(true));
    await wrapper.setProps({ tab: 'knowledge' });
    await flushPromises();

    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
  });
});
