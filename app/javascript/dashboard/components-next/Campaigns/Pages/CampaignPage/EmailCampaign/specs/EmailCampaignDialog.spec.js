import { mount, config, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';

// G52 (#2760) — o diálogo da campanha de e-mail manda a lista escolhida e, com
// lista, não sobe a planilha que tinha sido escolhida antes.
const store = vi.hoisted(() => ({ dispatch: vi.fn() }));
const getters = vi.hoisted(() => ({}));
const lists = vi.hoisted(() => ({ index: vi.fn(), create: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => store,
  useMapGetter: name => getters[name],
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/emailLists', () => ({ default: lists }));

const { default: EmailCampaignDialog } = await import(
  '../EmailCampaignDialog.vue'
);
const { default: EmailListAudience } = await import('../EmailListAudience.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});
beforeEach(() => {
  getters['emailCampaigns/getUIFlags'] = ref({});
  getters['emailSenderIdentities/getIdentities'] = ref([
    { id: 1, domain: 'exemplo.com', status: 'verified' },
  ]);
  getters['inboxes/getInboxes'] = ref([]);
  lists.index.mockResolvedValue({
    data: [{ id: 5, name: 'Dicas', contatos_count: 2, recebem_count: 2 }],
  });
  store.dispatch.mockResolvedValue({ id: 7 });
});
afterEach(() => vi.clearAllMocks());

const CAMPANHA = {
  id: 7,
  name: 'Novidades',
  sender_identity_id: 1,
  from_name: 'Loja',
  from_email: 'oi@exemplo.com',
  reply_to: 'oi@exemplo.com',
};

const montar = campaign =>
  mount(EmailCampaignDialog, {
    props: { campaign },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
    },
  });

const chamadas = acao =>
  store.dispatch.mock.calls.filter(([nome]) => nome === acao);

describe('EmailCampaignDialog com lista de e-mail', () => {
  it('manda a lista escolhida ao salvar', async () => {
    const wrapper = montar({ ...CAMPANHA, email_list_id: 5 });
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(chamadas('emailCampaigns/update')).toEqual([
      [
        'emailCampaigns/update',
        expect.objectContaining({ id: 7, email_list_id: 5 }),
      ],
    ]);
  });

  it('na planilha, manda a campanha sem lista', async () => {
    const wrapper = montar(CAMPANHA);
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(chamadas('emailCampaigns/update')[0][1]).toMatchObject({
      email_list_id: null,
    });
  });

  it('com lista, não sobe a planilha escolhida antes', async () => {
    const wrapper = montar(CAMPANHA);
    await flushPromises();
    const arquivo = new File(['email\nana@exemplo.com'], 'base.csv', {
      type: 'text/csv',
    });
    const input = wrapper.find('input[type="file"]');
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');

    const publico = wrapper.findComponent(EmailListAudience);
    publico.vm.$emit('update:modo', 'lista');
    publico.vm.$emit('update:listaId', 5);
    await flushPromises();
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(chamadas('emailCampaigns/update')[0][1]).toMatchObject({
      email_list_id: 5,
    });
    expect(chamadas('emailCampaigns/importRecipients')).toEqual([]);
  });

  it('a planilha ainda sobe quando não há lista', async () => {
    const wrapper = montar(CAMPANHA);
    await flushPromises();
    const arquivo = new File(['email\nana@exemplo.com'], 'base.csv', {
      type: 'text/csv',
    });
    const input = wrapper.find('input[type="file"]');
    Object.defineProperty(input.element, 'files', { value: [arquivo] });
    await input.trigger('change');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(chamadas('emailCampaigns/importRecipients')).toEqual([
      ['emailCampaigns/importRecipients', { id: 7, file: arquivo }],
    ]);
  });

  it('lista sem escolha não salva', async () => {
    const wrapper = montar({ ...CAMPANHA });
    await flushPromises();
    wrapper.findComponent(EmailListAudience).vm.$emit('update:modo', 'lista');
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(store.dispatch).not.toHaveBeenCalled();
    expect(wrapper.find('[data-lista-obrigatoria]').exists()).toBe(true);
  });
});
