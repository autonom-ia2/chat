import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversationParticipant from './ConversationParticipant.vue';
import en from 'dashboard/i18n/locale/en/conversation.json';
import pt_BR from 'dashboard/i18n/locale/pt_BR/conversation.json';

// #1148/#1149 — quem tem acesso restrito por funil na caixa não se adiciona
// como participante; outra pessoa pode adicioná-lo.
const api = vi.hoisted(() => ({ get: vi.fn() }));
const alertas = vi.hoisted(() => []);
vi.mock('dashboard/api/crmMeuAcesso', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));
vi.mock('dashboard/composables/useAgentsList', async () => {
  const { ref } = await import('vue');
  return {
    useAgentsList: () => ({
      agentsList: ref([
        { id: 1, name: 'John' },
        { id: 2, name: 'Ana Lima' },
      ]),
    }),
  };
});

const montar = ({ dispatch = vi.fn() } = {}) =>
  mount(ConversationParticipant, {
    props: { conversationId: 9 },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'pt_BR', messages: { en, pt_BR } }),
      ],
      directives: { tooltip: {}, onClickaway: {} },
      stubs: { ThumbnailGroup: true, Spinner: true },
      mocks: {
        $store: {
          dispatch,
          getters: {
            'conversationWatchers/getUIFlags': {},
            'conversationWatchers/getByConversationId': () => [],
            getCurrentUser: { id: 1, name: 'John' },
            getConversationById: () => ({ id: 9, inbox_id: 4 }),
          },
        },
      },
    },
  });

// O Button do painel vem simplificado no setup dos testes: o rótulo fica no HTML.
const participar = wrapper => wrapper.html().includes('Participar da conversa');

const opcoes = wrapper =>
  wrapper
    .getComponent({ name: 'MultiselectDropdownItems' })
    .props('options')
    .map(agente => agente.name);

describe('ConversationParticipant — acesso restrito', () => {
  beforeEach(() => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
    alertas.length = 0;
  });
  afterEach(() => delete window.globalConfig);

  it('restrita na caixa: sem "Participar da conversa" e fora da própria lista', async () => {
    api.get.mockResolvedValue({
      data: { payload: { restricted_inbox_ids: [4] } },
    });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-participar-restrito]').text()).toBe(
      'Outra pessoa pode adicionar você'
    );
    expect(participar(wrapper)).toBe(false);
    expect(opcoes(wrapper)).toEqual(['Ana Lima']);
  });

  it('restrita em outra caixa: tudo como hoje', async () => {
    api.get.mockResolvedValue({
      data: { payload: { restricted_inbox_ids: [8] } },
    });
    const wrapper = montar();
    await flushPromises();

    expect(participar(wrapper)).toBe(true);
    expect(opcoes(wrapper)).toEqual(['John', 'Ana Lima']);
  });

  it('sem CRM, nem pergunta à API', async () => {
    window.globalConfig = { CRM_KANBAN_ENABLED: 'false' };
    api.get.mockClear();
    const wrapper = montar();
    await flushPromises();

    expect(api.get).not.toHaveBeenCalled();
    expect(participar(wrapper)).toBe(true);
  });

  it('o 403 da API vira o texto traduzido', async () => {
    api.get.mockResolvedValue({
      data: { payload: { restricted_inbox_ids: [] } },
    });
    const proibido = Object.assign(
      new Error('Restricted agents cannot add themselves'),
      { code: 'participants.self_add_restricted' }
    );
    const dispatch = vi.fn(acao =>
      acao === 'conversationWatchers/update'
        ? Promise.reject(proibido)
        : Promise.resolve()
    );
    const wrapper = montar({ dispatch });
    await flushPromises();

    await wrapper.vm.updateParticipant([1]);

    expect(alertas).toEqual([
      'Você não pode se adicionar nesta conversa. Peça a um administrador ou a quem está atendendo para adicionar você.',
    ]);
  });
});
