import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import axios from 'axios';
import FieldConfigurator from '../FieldConfigurator.vue';

// #2138 — os campos internos da WAHA não aparecem no configurador, mas um clique
// numa área não pode tirar da lista salva os ids deles.
const context = vi.hoisted(() => ({ account: 500 }));
vi.mock('axios', () => ({ default: { get: vi.fn(), patch: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ref(false),
  useStore: () => ({
    commit: vi.fn(),
    subscribe: vi.fn(),
    getters: { getCurrentUserID: 1 },
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountId: ref(context.account),
    currentAccount: ref({ id: context.account }),
    isCloudFeatureEnabled: () => true,
  }),
}));

const definicao = (id, chave) => ({
  id,
  attribute_key: chave,
  attribute_model: 'contact_attribute',
  attribute_display_name: chave,
  attribute_description: '',
  attribute_display_type: 'text',
  attribute_values: [],
});
const DEFINICOES = [
  definicao(1, 'melhor_horario'),
  definicao(2, 'waha_whatsapp_chat_id'),
  definicao(3, 'cpf'),
  definicao(4, 'waha_whatsapp_lid'),
];

const originalDashboardClient = window.axios;
beforeEach(() => {
  context.account += 1;
  vi.clearAllMocks();
  window.axios = axios;
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
  };
  axios.patch.mockResolvedValue({
    data: { configuration: { revision: 5, surfaces: {} }, definition: null },
  });
});
afterEach(() => {
  window.axios = originalDashboardClient;
});

const abrirArea = async surfaces => {
  axios.get.mockResolvedValue({
    data: {
      configuration: { version: 1, revision: 4, surfaces },
      definitions: DEFINICOES,
      can_manage: true,
    },
  });
  const wrapper = mount(FieldConfigurator, {
    props: { entity: 'contact', surface: 'contact_sidebar' },
    global: { stubs: { teleport: true } },
  });
  await flushPromises();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'RELATIONSHIPS.CONFIGURE')
    .trigger('click');
  await flushPromises();
  return wrapper;
};
const chave = (wrapper, nome) =>
  wrapper.find(`[role="switch"][aria-label="${nome}"]`);
const salvar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  return axios.patch.mock.calls[0][1].configuration.surfaces.contact_sidebar;
};

describe('FieldConfigurator — campos internos da WAHA', () => {
  it('não mostra os internos entre as chaves da área', async () => {
    const wrapper = await abrirArea({});
    const nomes = wrapper
      .findAll('[role="switch"]')
      .map(item => item.attributes('aria-label'));
    expect(nomes).toEqual(['melhor_horario', 'cpf']);
    wrapper.unmount();
  });

  it('área em lista própria: ligar e desligar campos mantém o id escondido que já estava salvo', async () => {
    const wrapper = await abrirArea({
      contact_sidebar: { mode: 'custom', ids: [1, 2] },
    });
    await chave(wrapper, 'cpf').trigger('click');
    await chave(wrapper, 'melhor_horario').trigger('click');

    const area = await salvar(wrapper);
    expect(area.mode).toBe('custom');
    expect(area.ids).toContain(2);
    expect(area.ids).not.toContain(4);
    expect(area.ids).toContain(3);
    expect(area.ids).not.toContain(1);
    wrapper.unmount();
  });

  it('área no modo de sempre (todos): virar lista própria mantém os escondidos', async () => {
    const wrapper = await abrirArea({});
    await chave(wrapper, 'melhor_horario').trigger('click');

    const area = await salvar(wrapper);
    expect(area).toEqual({ mode: 'custom', ids: [2, 3, 4] });
    wrapper.unmount();
  });
});
