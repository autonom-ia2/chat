import { flushPromises, shallowMount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createRouter, createMemoryHistory } from 'vue-router';
import { createI18n } from 'vue-i18n';
import ChatList from '../ChatList.vue';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

// #2202: a lista "Quem está esperando" só aparece com a chave lista_quem_espera. Desligada, o topo, as abas e o
// aviso de lista vazia são os de sempre.
const Vazio = { render: () => null };

const montar = async ({
  chaveLigada,
  status = 'open',
  filtros = [],
  conversationType = '',
  participando = [],
}) => {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/app/accounts/:accountId/dashboard', name: 'home' }].map(
      rota => ({ ...rota, component: Vazio })
    ),
  });
  await router.push('/app/accounts/1/dashboard');
  await router.isReady();

  const getters = {
    getAppliedConversationFiltersQuery: () => [],
    getCurrentUser: () => ({ id: 5, name: 'Agente', accounts: [] }),
    getFilteredConversations: () => [],
    getMineChats: () => () => [],
    getAllStatusChats: () => () => [],
    getUnAssignedChats: () => () => [],
    getParticipatingChats: () => () => participando,
    getChatListLoadingStatus: () => false,
    getSelectedInbox: () => null,
    'conversationStats/getStats': () => ({}),
    getAppliedConversationFiltersV2: () => filtros,
    getAppliedContactFilter: () => null,
    'customViews/getConversationCustomViews': () => [],
    'customViews/getActiveFolderContactId': () => null,
    'agents/getAgents': () => [],
    'teams/getTeams': () => [],
    'teams/getTeam': () => () => ({}),
    'inboxes/getInboxes': () => [],
    'inboxes/getInbox': () => () => ({}),
    'campaigns/getAllCampaigns': () => [],
    'labels/getLabels': () => [],
    getCurrentAccountId: () => 1,
    getConversationById: () => () => null,
    'contacts/getContact': () => () => ({}),
    getIdsDoFiltroDoLink: () => [],
    getSelectedChat: () => ({}),
    'conversationPage/getCurrentPageFilter': () => () => 0,
    'conversationPage/getHasEndReached': () => () => false,
    'attributes/getAttributesByModel': () => () => [],
    getUISettings: () => ({}),
    'bulkActions/getSelectedConversationIds': () => [],
    'attributes/getConversationAttributes': () => [],
    'accounts/isFeatureEnabledonAccount': () => (_conta, chave) =>
      chaveLigada && chave === FEATURE_FLAGS.LISTA_QUEM_ESPERA,
  };
  const store = createStore({ getters });
  store.dispatch = vi.fn(() => Promise.resolve());

  const i18n = createI18n({ legacy: false, locale: 'en', missingWarn: false });
  const wrapper = shallowMount(ChatList, {
    props: { conversationType },
    global: { plugins: [router, store, i18n] },
  });
  if (status !== 'open') {
    wrapper
      .findComponent({ name: 'ListaCabecalho' })
      .vm.$emit('basicFilterChange', status, 'status');
    await flushPromises();
  }
  return wrapper;
};

describe('ChatList com a chave lista_quem_espera (#2202)', () => {
  it('desligada: o topo, as abas e a lista vazia de sempre', async () => {
    const wrapper = await montar({ chaveLigada: false });

    expect(wrapper.findComponent({ name: 'ChatListHeader' }).exists()).toBe(
      true
    );
    const abas = wrapper.findComponent({ name: 'ChatTypeTabs' });
    expect(abas.exists()).toBe(true);
    expect(abas.attributes()).toHaveProperty('is-compact');
    ['ListaCabecalho', 'ListaAbas', 'ChipDoStatus'].forEach(name =>
      expect(wrapper.findComponent({ name }).exists()).toBe(false)
    );

    const vazia = wrapper.find('p');
    expect(vazia.text()).toBe('CHAT_LIST.LIST.404');
    expect(vazia.attributes('class')).toBe(
      'flex overflow-auto justify-center items-center p-4'
    );
    expect(vazia.attributes()).not.toHaveProperty('data-lista-vazia');
  });

  it('ligada: o topo novo, as abas novas e o aviso da aba', async () => {
    const wrapper = await montar({ chaveLigada: true });

    expect(wrapper.findComponent({ name: 'ListaCabecalho' }).exists()).toBe(
      true
    );
    expect(wrapper.findComponent({ name: 'ListaAbas' }).exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'ChatListHeader' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'ChatTypeTabs' }).exists()).toBe(
      false
    );
    expect(wrapper.find('[data-lista-vazia]').text()).toBe(
      'LISTA_DE_CONVERSAS.VAZIA.MINHAS'
    );
  });

  it.each([
    ['pending', 'LISTA_DE_CONVERSAS.VAZIA.PENDENTES'],
    ['all', 'LISTA_DE_CONVERSAS.VAZIA.TODOS_OS_STATUS'],
  ])(
    'ligada, status %s: o chip do status e a lista vazia falando do status',
    async (status, texto) => {
      const wrapper = await montar({ chaveLigada: true, status });

      const chip = wrapper.findComponent({ name: 'ChipDoStatus' });
      expect(chip.exists()).toBe(true);
      expect(chip.props('status')).toBe(status);
      expect(wrapper.find('[data-lista-vazia]').text()).toBe(texto);
    }
  );

  it('ligada: a lista é o painel das abas', async () => {
    const wrapper = await montar({ chaveLigada: true });
    const lista = wrapper.findComponent({ name: 'ConversationList' });
    expect(lista.attributes('id')).toBe('lista-de-conversas-painel');
    expect(lista.attributes('role')).toBe('tabpanel');
    expect(lista.attributes('aria-labelledby')).toBe('lista-aba-me');
    expect(wrapper.findComponent({ name: 'ListaAbas' }).props('painelId')).toBe(
      'lista-de-conversas-painel'
    );
  });

  it('ligada com filtro avançado (sem as abas novas): a lista não é tabpanel', async () => {
    const wrapper = await montar({
      chaveLigada: true,
      filtros: [{ attributeKey: 'status', values: ['open'] }],
    });
    const lista = wrapper.findComponent({ name: 'ConversationList' });
    expect(wrapper.findComponent({ name: 'ListaAbas' }).exists()).toBe(false);
    expect(lista.attributes('role')).toBeUndefined();
    expect(lista.attributes('aria-labelledby')).toBeUndefined();
  });
});

// #2211 — a busca no topo da lista nova. Desligada a chave, nada de busca: a lista é a de sempre.
describe('ChatList: busca na lista (#2211)', () => {
  it('desligada: sem campo de busca nem resultado', async () => {
    const wrapper = await montar({ chaveLigada: false });
    expect(wrapper.findComponent({ name: 'CampoDaBusca' }).exists()).toBe(
      false
    );
    expect(wrapper.findComponent({ name: 'ResultadoDaBusca' }).exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'ConversationList' }).isVisible()
    ).toBe(true);
  });

  it('ligada: o campo fica no topo; com texto, o resultado toma o lugar da lista, que só se esconde', async () => {
    const wrapper = await montar({ chaveLigada: true });
    const campo = wrapper.findComponent({ name: 'CampoDaBusca' });
    expect(campo.exists()).toBe(true);
    expect(wrapper.findComponent({ name: 'ResultadoDaBusca' }).exists()).toBe(
      false
    );

    campo.vm.$emit('update:modelValue', 'joana');
    await flushPromises();

    expect(wrapper.findComponent({ name: 'ResultadoDaBusca' }).exists()).toBe(
      true
    );
    const lista = wrapper.findComponent({ name: 'ConversationList' });
    expect(lista.exists()).toBe(true);
    expect(lista.attributes('style')).toContain('display: none');
    expect(wrapper.find('[data-lista-vazia]').exists()).toBe(false);
  });
});

// #2249 — em Participando, a aba "Minhas" filtra no próprio painel. Robô com o meu id não é meu.
describe('ChatList: aba Minhas de Participando (#2249)', () => {
  it('robô (AgentBot) com o mesmo id do usuário fica de fora; a pessoa com o meu id fica', async () => {
    const conversa = (id, assigneeType) => ({
      id,
      status: 'open',
      inbox_id: 1,
      labels: [],
      timestamp: 100 - id,
      meta: { assignee: { id: 5 }, assignee_type: assigneeType },
    });
    const wrapper = await montar({
      chaveLigada: false,
      conversationType: 'participating',
      participando: [conversa(1, 'AgentBot'), conversa(2, 'User')],
    });

    const lista = wrapper.findComponent({ name: 'ConversationList' });
    expect(lista.props('conversationList').map(c => c.id)).toEqual([2]);
  });
});
