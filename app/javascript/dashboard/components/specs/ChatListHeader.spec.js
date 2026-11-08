import { shallowMount } from '@vue/test-utils';
import ChatListHeader from '../ChatListHeader.vue';

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref } = await import('vue');
  return {
    useUISettings: () => ({
      uiSettings: ref({}),
      updateUISettings: vi.fn(),
    }),
  };
});

const listaNova = vi.hoisted(() => ({ value: false }));
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useListaNova',
  async () => {
    const { ref } = await import('vue');
    return { useListaNova: () => ref(listaNova.value) };
  }
);

const mountHeader = props =>
  shallowMount(ChatListHeader, {
    props: {
      pageTitle: 'Conversations',
      hasAppliedFilters: false,
      hasActiveFolders: false,
      activeStatus: 'open',
      isOnExpandedLayout: false,
      conversationStats: { allCount: 12 },
      isListLoading: false,
      ...props,
    },
    global: {
      mocks: { $t: key => key },
    },
  });

const contactFilter = { id: 7, name: 'Jane Doe' };

describe('ChatListHeader', () => {
  it('renders the page title and the filter button without filters', () => {
    const wrapper = mountHeader();

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(false);
  });

  it('keeps the page title and the filter button for non contact filters', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('names the contact and hides the filter button when scoped to a contact', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true, contactFilter });

    expect(wrapper.find('h1').text()).toBe('Jane Doe');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('falls back to the page title when the scoped contact has no name', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      contactFilter: { id: 7, name: '' },
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
  });

  it('filtro pelo link (#1883): mostra o título do filtro e a seta que limpa, sem salvar como pasta', async () => {
    const wrapper = mountHeader({
      pageTitle: 'Recebidas da IA',
      hasLinkFilter: true,
    });

    expect(wrapper.find('h1').text()).toBe('Recebidas da IA');
    expect(wrapper.find('[icon="i-lucide-save"]').exists()).toBe(false);
    const limpar = wrapper.find('[icon="i-lucide-chevron-left"]');
    expect(limpar.exists()).toBe(true);
    await limpar.trigger('click');
    expect(wrapper.emitted('resetFilters')).toHaveLength(1);
  });

  it('keeps the folder controls when a folder is active', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      hasActiveFolders: true,
      contactFilter,
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('[icon="i-lucide-pen-line"]').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-trash-2"]').exists()).toBe(true);
  });

  // #2202: com a lista nova, o layout não muda no computador; o botão de trocar não aparece.
  it('mostra o botão de trocar o layout com a chave lista_quem_espera desligada', () => {
    listaNova.value = false;
    expect(mountHeader().findComponent({ name: 'SwitchLayout' }).exists()).toBe(
      true
    );
  });

  it('esconde o botão de trocar o layout com a chave lista_quem_espera ligada', () => {
    listaNova.value = true;
    expect(mountHeader().findComponent({ name: 'SwitchLayout' }).exists()).toBe(
      false
    );
    listaNova.value = false;
  });
});
