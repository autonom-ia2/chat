import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import ViewAllConversations from '../ViewAllConversations.vue';

// #2202: "Ver todas as conversas" segue o layout que a tela usa de verdade. Com a lista nova no
// computador (condensada mesmo com o expandido salvo), a conversa aberta continua aberta.
const layoutExpandido = ref(false);
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useLayoutDaLista',
  () => ({ useLayoutExpandidoDaLista: () => layoutExpandido })
);

const push = vi.fn(() => Promise.resolve());
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'inbox_conversation' }),
  useRouter: () => ({ push }),
}));

const dispatch = vi.fn(() => Promise.resolve());
const getters = {
  'contactConversations/getConversationNeighbours': ref(() => [1, 2]),
  getSelectedChat: ref({ id: 42 }),
  getConversationById: ref(() => null),
};
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: nome => getters[nome],
}));
vi.mock('dashboard/composables/useConversationRoutePath', () => ({
  useConversationRoutePath: () => ({
    buildConversationPath: id => `/conversa/${id}`,
    buildConversationListPath: () => '/lista',
    isOnFolderView: ref(false),
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const clicar = async () => {
  const wrapper = mount(ViewAllConversations, {
    props: { contact: { id: 7, name: 'Contato Teste' } },
    global: {
      mocks: { $t: chave => chave },
      directives: { tooltip: {} },
      stubs: {
        NextButton: { template: '<button @click="$emit(\'click\')" />' },
      },
    },
  });
  await wrapper.find('button').trigger('click');
  await flushPromises();
};

describe('ViewAllConversations e o layout da lista (#2202)', () => {
  beforeEach(() => {
    push.mockClear();
    dispatch.mockClear();
  });

  it('layout condensado (lista nova no computador, mesmo com o expandido salvo): a conversa aberta fica', async () => {
    layoutExpandido.value = false;
    await clicar();
    expect(push).not.toHaveBeenCalled();
    expect(dispatch).toHaveBeenCalledWith('getConversation', 42);
  });

  it('layout expandido de verdade (chave desligada ou celular): vai para a lista, como antes', async () => {
    layoutExpandido.value = true;
    await clicar();
    expect(push).toHaveBeenCalledWith('/lista');
    expect(dispatch).not.toHaveBeenCalledWith('getConversation', 42);
  });
});
