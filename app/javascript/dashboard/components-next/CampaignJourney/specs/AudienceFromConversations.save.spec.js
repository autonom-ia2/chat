import { flushPromises, shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/campaignJourney.json';
import { useAlert } from 'dashboard/composables';
import AudienceFromConversations from '../AudienceFromConversations.vue';
import AudienceSearchReview from '../AudienceSearchReview.vue';

// #2695: salvar o Público por conversa. Contato apagado no meio (422
// foreign_contact) tem frase própria; qualquer outro erro, a frase de sempre.
const api = vi.hoisted(() => ({
  status: vi.fn(),
  open: vi.fn(),
  save: vi.fn(),
  watch: vi.fn(),
  detach: vi.fn(),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => 1) };
});
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: true }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../conversationAudienceApi', () => ({
  createConversationAudienceApi: () => api,
}));

const NS = ptBR.CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS;

// Abre uma procura já lida: a tela vai direto para a revisão, onde fica o salvar.
const abrirNaRevisao = async () => {
  api.status.mockResolvedValue({
    hasOwnKey: true,
    periods: {},
    openSearchId: 1,
  });
  api.open.mockResolvedValue({
    request: 'quem pediu orçamento',
    period: '12m',
    plan: { name: 'Orçamentos', conversations: 1 },
    progress: { state: 'pronto', read: 1, total: 1, people: [] },
  });
  const wrapper = shallowMount(AudienceFromConversations, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
    },
  });
  await flushPromises();
  return wrapper;
};

const salvar = async wrapper => {
  wrapper.findComponent(AudienceSearchReview).vm.$emit('save', false);
  await flushPromises();
};

describe('AudienceFromConversations: erro ao salvar', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('422 foreign_contact mostra a frase do contato apagado', async () => {
    api.save.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'foreign_contact' } },
    });
    const wrapper = await abrirNaRevisao();

    await salvar(wrapper);

    expect(api.save).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(NS.SAVE_ERROR_FOREIGN_CONTACT);
  });

  it('outro erro mostra a frase de sempre', async () => {
    api.save.mockRejectedValueOnce({
      response: { status: 500, data: { error: 'boom' } },
    });
    const wrapper = await abrirNaRevisao();

    await salvar(wrapper);

    expect(useAlert).toHaveBeenCalledWith(NS.SAVE_ERROR);
  });
});
