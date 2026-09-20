import { mount, flushPromises } from '@vue/test-utils';
import { ref, computed } from 'vue';
import Index from '../Index.vue';

const lista = ref([]);

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({
    'integrations/getUIFlags': computed(() => ({ isFetching: false })),
    'integrations/getAppIntegrations': computed(() => lista.value),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: texto => texto }),
}));

// `enabled` é o que o backend responde para esta integração: o
// CredentialResolver, que aceita a chave da conta ou a da instalação.
const integracao = (id, { enabled = false, hooks = [] } = {}) => ({
  id,
  name: `Nome ${id}`,
  description: `Descrição ${id}`,
  enabled,
  hooks,
});

const COM_CHAVE = {
  enabled: true,
  hooks: [{ id: 1, status: true, settings: { enabled: true } }],
};

const montar = async integracoes => {
  lista.value = integracoes;
  const wrapper = mount(Index, {
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        SettingsLayout: { template: '<div><slot name="body" /></div>' },
        BaseSettingsHeader: true,
        IntegrationItem: {
          props: ['id', 'highlighted'],
          template:
            '<div class="item" :data-id="id" :data-destaque="String(highlighted)" />',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const idsNaTela = wrapper =>
  wrapper.findAll('.item').map(item => item.attributes('data-id'));

const destaqueDe = (wrapper, id) =>
  wrapper.find(`.item[data-id="${id}"]`).attributes('data-destaque');

describe('Index das integrações', () => {
  it('põe a CRM Kanban IA na frente enquanto falta a chave', async () => {
    const wrapper = await montar([
      integracao('webhook'),
      integracao('slack'),
      integracao('crm_kanban_ai'),
    ]);

    expect(idsNaTela(wrapper)[0]).toBe('crm_kanban_ai');
    expect(destaqueDe(wrapper, 'crm_kanban_ai')).toBe('true');
  });

  it('mantém a ordem original quando a chave já está ligada', async () => {
    const wrapper = await montar([
      integracao('webhook'),
      integracao('slack'),
      integracao('crm_kanban_ai', COM_CHAVE),
    ]);

    expect(idsNaTela(wrapper)).toEqual(['webhook', 'slack', 'crm_kanban_ai']);
    expect(destaqueDe(wrapper, 'crm_kanban_ai')).toBe('false');
  });

  it('volta a destacar quando o hook existe mas a IA está desligada', async () => {
    const wrapper = await montar([
      integracao('webhook'),
      integracao('crm_kanban_ai', {
        enabled: false,
        hooks: [{ id: 1, status: true, settings: { enabled: false } }],
      }),
    ]);

    expect(idsNaTela(wrapper)[0]).toBe('crm_kanban_ai');
    expect(destaqueDe(wrapper, 'crm_kanban_ai')).toBe('true');
  });

  it('não pede chave na conta que roda com a chave da instalação', async () => {
    const wrapper = await montar([
      integracao('webhook'),
      integracao('crm_kanban_ai', { enabled: true, hooks: [] }),
    ]);

    expect(idsNaTela(wrapper)).toEqual(['webhook', 'crm_kanban_ai']);
    expect(destaqueDe(wrapper, 'crm_kanban_ai')).toBe('false');
  });

  it('não destaca nenhuma outra integração', async () => {
    const wrapper = await montar([
      integracao('webhook'),
      integracao('crm_kanban_ai'),
    ]);

    expect(destaqueDe(wrapper, 'webhook')).toBe('false');
  });

  it('funciona na conta onde a CRM Kanban IA nem aparece', async () => {
    const wrapper = await montar([integracao('webhook'), integracao('slack')]);

    expect(idsNaTela(wrapper)).toEqual(['webhook', 'slack']);
    expect(destaqueDe(wrapper, 'webhook')).toBe('false');
  });
});
