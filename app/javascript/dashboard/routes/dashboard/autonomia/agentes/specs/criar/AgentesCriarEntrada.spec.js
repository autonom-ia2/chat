import { defineComponent, h, nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AgentesCriarEntrada from '../../entrada/AgentesCriarEntrada.vue';

// O seletor da rota autonomia_agents_builder (DECISOES.md item 1): flag desligada = o Construtor
// antigo, sem carregar o pedaço novo e sem chamada nova (nem build_threads, nem leituras da
// jornada); ligada = a criação nova. Decide uma vez só.
const store = vi.hoisted(() => ({ getters: {}, dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const jornada = vi.hoisted(() => ({
  semana: vi.fn(),
  canaisOcupados: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornada }));
const construtor = vi.hoisted(() => ({ create: vi.fn(), show: vi.fn() }));
vi.mock('dashboard/api/autonomia/buildThreads', () => ({
  default: construtor,
}));

// #1543: sem modelo, rascunho nem atuação na URL, a flag ligada abre antes a página "Criar agente".
const rota = vi.hoisted(() => ({ atual: null }));
const roteador = vi.hoisted(() => ({ replace: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => rota.atual,
  useRouter: () => roteador,
}));
vi.mock('../../pages/AgenteEscolherPage.vue', async () => {
  const { defineComponent: definir, h: hh } = await import('vue');
  return {
    __esModule: true,
    default: definir({
      name: 'AgenteEscolherPage',
      emits: ['escolher'],
      setup:
        (_props, { emit }) =>
        () =>
          hh('button', {
            'data-escolher': '',
            onClick: () => emit('escolher', { atuacao: 'interno' }),
          }),
    }),
  };
});

const carregouNova = vi.hoisted(() => vi.fn());
vi.mock('../../pages/AgenteCriarPage.vue', async () => {
  carregouNova();
  const { defineComponent: definir, h: hh } = await import('vue');
  return {
    __esModule: true,
    default: definir({
      name: 'AgenteCriarPage',
      setup: () => () => hh('div', { 'data-nova': '' }),
    }),
  };
});
const montouAntiga = vi.hoisted(() => vi.fn());
const desmontouAntiga = vi.hoisted(() => vi.fn());
vi.mock('../../../pages/AgentBuilderPage.vue', async () => {
  const {
    defineComponent: definir,
    h: hh,
    onMounted,
    onBeforeUnmount,
  } = await import('vue');
  return {
    default: definir({
      name: 'AgentBuilderPage',
      inheritAttrs: false,
      setup: (_props, { attrs }) => {
        onMounted(() => montouAntiga(attrs));
        onBeforeUnmount(desmontouAntiga);
        return () => hh('div', { 'data-antiga': '' });
      },
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

describe('AgentesCriarEntrada', () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    const { reactive } = await import('vue');
    rota.atual = reactive({ query: { modelo: 'support' } });
    roteador.replace.mockImplementation(async ({ query }) => {
      rota.atual.query = query;
    });
  });

  it('keeps the old Builder with the flag off, without loading the new page nor calling any API', async () => {
    comConta({ ...conta });
    const wrapper = mount(AgentesCriarEntrada);
    await flushPromises();

    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
    expect(carregouNova).not.toHaveBeenCalled();
    expect(store.dispatch).not.toHaveBeenCalled();
    expect(construtor.create).not.toHaveBeenCalled();
    expect(jornada.semana).not.toHaveBeenCalled();
    expect(jornada.canaisOcupados).not.toHaveBeenCalled();
  });

  it('mounts the old Builder with no props, as the route does today', async () => {
    comConta({ ...conta });
    mount(AgentesCriarEntrada);
    await flushPromises();
    expect(montouAntiga).toHaveBeenCalledWith({});
  });

  it('keeps the old Builder when the Agents module is off on the account', async () => {
    comConta({
      ...conta,
      autonomia_agents_enabled: false,
      features: { autonomia_agents_journey: true },
    });
    const wrapper = mount(AgentesCriarEntrada);
    await flushPromises();
    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(carregouNova).not.toHaveBeenCalled();
  });

  it('shows the new creation with the flag on', async () => {
    comConta({ ...conta, features: { autonomia_agents_journey: true } });
    const wrapper = mount(AgentesCriarEntrada);
    await flushPromises();

    expect(wrapper.find('[data-nova]').exists()).toBe(true);
    expect(wrapper.find('[data-antiga]').exists()).toBe(false);
  });

  it('never unmounts the old Builder when the account changes in the store (no force_close)', async () => {
    const atual = { ...conta, features: { autonomia_agents_journey: false } };
    comConta(atual);
    const Casca = defineComponent({
      setup: () => () => h(AgentesCriarEntrada),
    });
    const wrapper = mount(Casca);
    await flushPromises();

    comConta({ ...atual, features: { autonomia_agents_journey: true } });
    await nextTick();
    await flushPromises();

    expect(wrapper.find('[data-antiga]').exists()).toBe(true);
    expect(wrapper.find('[data-nova]').exists()).toBe(false);
    expect(desmontouAntiga).not.toHaveBeenCalled();
  });

  describe('página "Criar agente" (#1543)', () => {
    const ligada = { ...conta, features: { autonomia_agents_journey: true } };

    it('opens the "Criar agente" page first when the URL has no choice', async () => {
      comConta(ligada);
      rota.atual.query = {};
      const wrapper = mount(AgentesCriarEntrada);
      await flushPromises();
      expect(wrapper.find('[data-escolher]').exists()).toBe(true);
      expect(wrapper.find('[data-nova]').exists()).toBe(false);
      expect(carregouNova).not.toHaveBeenCalled();
    });

    it('puts the choice in the URL and only then mounts the creation', async () => {
      comConta(ligada);
      rota.atual.query = {};
      const wrapper = mount(AgentesCriarEntrada);
      await flushPromises();
      await wrapper.get('[data-escolher]').trigger('click');
      await flushPromises();
      expect(roteador.replace).toHaveBeenCalledWith({
        query: { atuacao: 'interno' },
      });
      expect(wrapper.find('[data-escolher]').exists()).toBe(false);
      expect(wrapper.find('[data-nova]').exists()).toBe(true);
    });

    it.each([
      [{ modelo: 'sdr' }],
      [{ type: 'support' }],
      [{ agente: '7' }],
      [{ atuacao: 'interno' }],
    ])('goes straight to the creation with %o', async query => {
      comConta(ligada);
      rota.atual.query = query;
      const wrapper = mount(AgentesCriarEntrada);
      await flushPromises();
      expect(wrapper.find('[data-escolher]').exists()).toBe(false);
      expect(wrapper.find('[data-nova]').exists()).toBe(true);
    });

    it('goes back to the page when the same route opens again without a choice (menu)', async () => {
      comConta(ligada);
      const wrapper = mount(AgentesCriarEntrada);
      await flushPromises();
      expect(wrapper.find('[data-nova]').exists()).toBe(true);
      rota.atual.query = {};
      await flushPromises();
      expect(wrapper.find('[data-escolher]').exists()).toBe(true);
    });

    it('keeps the old Builder with the flag off even without a choice in the URL', async () => {
      comConta({ ...conta });
      rota.atual.query = {};
      const wrapper = mount(AgentesCriarEntrada);
      await flushPromises();
      expect(wrapper.find('[data-antiga]').exists()).toBe(true);
      expect(wrapper.find('[data-escolher]').exists()).toBe(false);
    });
  });
});
