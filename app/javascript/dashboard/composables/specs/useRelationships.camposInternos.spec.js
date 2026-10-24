import { defineComponent, ref, computed } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import axios from 'dashboard/api/relationships';
import { useRelationships } from 'dashboard/composables/useRelationships';

// #2138 — as telas do Relacionamentos (painel da conversa, configurador de campos,
// CRM) recebem as definições sem os campos internos da WAHA; o store recebe a
// lista inteira, e os getters dele é que os escondem.
const context = vi.hoisted(() => ({ store: null }));
vi.mock('dashboard/api/relationships', () => ({
  default: { get: vi.fn(), patch: vi.fn(), post: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => context.store,
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(901),
    currentAccount: computed(() => ({ id: 901 })),
    isCloudFeatureEnabled: () => true,
  }),
}));
const Probe = defineComponent({ setup: useRelationships, template: '<div />' });
const DEFINICOES = [
  { id: 1, attribute_key: 'melhor_horario' },
  { id: 2, attribute_key: 'waha_whatsapp_chat_id' },
  { id: 3, attribute_key: 'waha_whatsapp_jid' },
  { id: 4, attribute_key: 'waha_whatsapp_lid' },
];

beforeEach(() => {
  vi.clearAllMocks();
  context.store = {
    commit: vi.fn(),
    subscribe: vi.fn(),
    getters: { getCurrentUserID: 1, 'attributes/getRevision': 0 },
  };
  axios.get.mockResolvedValue({
    data: {
      configuration: { revision: 0, surfaces: {} },
      definitions: DEFINICOES,
      can_manage: true,
    },
  });
});

it('expõe as definições sem os internos e manda a lista inteira para o store', async () => {
  const wrapper = mount(Probe);
  await flushPromises();

  expect(wrapper.vm.state.definitions.map(d => d.attribute_key)).toEqual([
    'melhor_horario',
  ]);
  expect(context.store.commit).toHaveBeenCalledWith(
    'attributes/SET_CUSTOM_ATTRIBUTE',
    DEFINICOES
  );
  // A lista inteira fica à mão de quem grava a configuração das áreas.
  expect(wrapper.vm.allDefinitions).toEqual(DEFINICOES);
  // O resto do estado continua chegando.
  expect(wrapper.vm.state.can_manage).toBe(true);
  expect(wrapper.vm.state.configuration).toEqual({ revision: 0, surfaces: {} });
  wrapper.unmount();
});
