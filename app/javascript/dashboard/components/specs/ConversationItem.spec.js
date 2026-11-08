import { defineComponent, h } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import ConversationItem from '../ConversationItem.vue';

// #1883: Ctrl/Cmd+clique numa conversa da lista filtrada pelo link abre a outra aba com o mesmo filtro.
const Vazio = { render: () => null };
const CartaoStub = defineComponent({
  name: 'ConversationCard',
  emits: ['click'],
  setup(_, { emit }) {
    return () => h('button', { onClick: evento => emit('click', evento) });
  },
});

const montar = async (
  inicio,
  { listaNova = false, showExpanded = false } = {}
) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/app/accounts/:accountId/dashboard', name: 'home' },
      {
        path: '/app/accounts/:accountId/conversations/:conversation_id',
        name: 'inbox_conversation',
      },
      { path: '/app/accounts/:accountId/crm', name: 'crm_kanban_index' },
    ].map(rota => ({ ...rota, component: Vazio })),
  });
  await router.push(inicio);
  await router.isReady();
  const store = createStore({
    getters: {
      getSelectedChat: () => ({ id: 99 }),
      'inboxes/getInboxes': () => [],
      'inboxes/getInbox': () => () => ({ id: 1 }),
      getSelectedInbox: () => null,
      getCurrentAccountId: () => 1,
      'contacts/getContact': () => () => ({}),
      canOperateConversation: () => () => true,
      'accounts/isFeatureEnabledonAccount': () => (_conta, chave) =>
        listaNova && chave === 'lista_quem_espera',
    },
  });
  const provides = Object.fromEntries(
    [
      'selectConversation',
      'deSelectConversation',
      'assignAgent',
      'assignTeam',
      'assignLabels',
      'removeLabels',
      'updateConversationStatus',
      'toggleContextMenu',
      'markAsUnread',
      'markAsRead',
      'assignPriority',
      'deleteConversation',
    ].map(chave => [chave, vi.fn()])
  );
  provides.isConversationSelected = () => false;
  const wrapper = shallowMount(ConversationItem, {
    props: { source: { id: 7, inbox_id: 1, meta: {} }, showExpanded },
    global: {
      plugins: [router, store],
      provide: provides,
      stubs: {
        ConversationCard: CartaoStub,
        CardDaConversa: true,
        ConversationCardExpanded: true,
      },
    },
  });
  return { wrapper, router };
};

describe('ConversationItem (#1883)', () => {
  let abrir;
  beforeEach(() => {
    window.chatwootConfig = { hostURL: 'https://painel.test' };
    abrir = vi.spyOn(window, 'open').mockImplementation(() => null);
  });
  afterEach(() => abrir.mockRestore());

  it('Ctrl/Cmd+clique na lista filtrada abre a outra aba com o link', async () => {
    const { wrapper } = await montar(
      '/app/accounts/1/dashboard?da_ia=1&esperando_min=30'
    );

    await wrapper.find('button').trigger('click', { ctrlKey: true });

    expect(abrir).toHaveBeenCalledWith(
      'https://painel.test/app/accounts/1/conversations/7?da_ia=1&esperando_min=30',
      '_blank',
      'noopener,noreferrer'
    );
  });

  it('sem o filtro, Ctrl/Cmd+clique abre a conversa sem nada a mais', async () => {
    const { wrapper } = await montar('/app/accounts/1/dashboard');

    await wrapper.find('button').trigger('click', { metaKey: true });

    expect(abrir).toHaveBeenCalledWith(
      'https://painel.test/app/accounts/1/conversations/7',
      '_blank',
      'noopener,noreferrer'
    );
  });

  it('clique normal na lista filtrada abre a conversa com o link (a guarda leva)', async () => {
    const { wrapper, router } = await montar(
      '/app/accounts/1/dashboard?da_ia=1'
    );

    await wrapper.find('button').trigger('click');
    await vi.waitFor(() =>
      expect(router.currentRoute.value.name).toBe('inbox_conversation')
    );

    expect(router.currentRoute.value.query).toEqual({ da_ia: '1' });
    expect(abrir).not.toHaveBeenCalled();
  });
});

describe('ConversationItem com a chave lista_quem_espera (#2202)', () => {
  it('desligada: o cartão de sempre', async () => {
    const { wrapper } = await montar('/app/accounts/1/dashboard');

    expect(wrapper.findComponent({ name: 'ConversationCard' }).exists()).toBe(
      true
    );
    expect(wrapper.findComponent({ name: 'CardDaConversa' }).exists()).toBe(
      false
    );
  });

  it('ligada: o item novo, com a conversa e a seleção de sempre', async () => {
    const { wrapper } = await montar('/app/accounts/1/dashboard', {
      listaNova: true,
    });

    const card = wrapper.findComponent({ name: 'CardDaConversa' });
    expect(card.exists()).toBe(true);
    expect(card.props('chat')).toEqual({ id: 7, inbox_id: 1, meta: {} });
    expect(card.props('selectable')).toBe(true);
    expect(wrapper.findComponent({ name: 'ConversationCard' }).exists()).toBe(
      false
    );
  });

  it('layout expandido salvo e chave ligada: o item novo, condensado', async () => {
    const { wrapper } = await montar('/app/accounts/1/dashboard', {
      listaNova: true,
      showExpanded: true,
    });
    expect(wrapper.findComponent({ name: 'CardDaConversa' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'ConversationCardExpanded' }).exists()
    ).toBe(false);
  });

  it('layout expandido salvo e chave desligada: o card expandido, como na main', async () => {
    const { wrapper } = await montar('/app/accounts/1/dashboard', {
      showExpanded: true,
    });
    expect(
      wrapper.findComponent({ name: 'ConversationCardExpanded' }).exists()
    ).toBe(true);
    expect(wrapper.findComponent({ name: 'CardDaConversa' }).exists()).toBe(
      false
    );
  });
});
