import { ref } from 'vue';
import { mount, shallowMount } from '@vue/test-utils';
import ContactHeader from 'dashboard/components-next/Contacts/ContactsHeader/ContactHeader.vue';
import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';
import ContactDetailActions from 'dashboard/components-next/Relationships/ContactDetailActions.vue';
import Sidebar from 'dashboard/components-next/sidebar/Sidebar.vue';
import ContactInfo from 'dashboard/routes/dashboard/conversation/contact/ContactInfo.vue';
import TelaAntigaDireta from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NovaConversaEntrada from '../NovaConversaEntrada.vue';

// #1459 — os cinco lugares do painel que abrem "Nova conversa" passam pela
// ponte (NovaConversaEntrada), e não pelo ComposeConversation direto. É a
// ponte que escolhe entre a tela nova e a antiga pela flag da conta; um ponto
// de entrada que a pule fica preso numa das duas.
const { marcador } = vi.hoisted(() => ({
  marcador: nome => ({
    name: nome,
    props: ['contactId', 'align'],
    template: `<div :data-entrada="'${nome}'">
      <slot name="trigger" :is-open="false" />
    </div>`,
  }),
}));

vi.mock('../NovaConversaEntrada.vue', () => ({ default: marcador('Ponte') }));
vi.mock(
  'dashboard/components-next/NewConversation/ComposeConversation.vue',
  () => ({ default: marcador('TelaAntigaDireta') })
);

// O que as cinco telas pedem ao redor (os mesmos dublês do Sidebar.spec.js).
const getters = {
  'globalConfig/get': ref({}),
  getCurrentAccountId: ref(9),
  getCurrentRole: ref('administrator'),
  getCurrentCustomRoleId: ref(null),
  getCurrentUser: ref({ accounts: [{ id: 9, permissions: [] }] }),
  'accounts/getAccount': ref(() => ({ id: 9, features: {} })),
  'accounts/isFeatureEnabledonAccount': ref(() => false),
  'inboxes/getInboxes': ref([]),
  'labels/getLabelsOnSidebar': ref([]),
  'teams/getMyTeams': ref([]),
  'customViews/getContactCustomViews': ref([]),
  'customViews/getConversationCustomViews': ref([]),
};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ fullPath: '/', params: { contactId: '9' } }),
  // O menu lateral liga o ⌘K da busca da lista (#2211), que navega pelo router.
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('vuex', async original => ({
  ...(await original()),
  useStore: () => ({ dispatch: vi.fn() }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: chave => getters[chave] || ref(() => 0),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: (name, params) => ({ name, params }),
    isOnChatwootCloud: ref(false),
  }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));
vi.mock('dashboard/composables/utils/useKbd', () => ({
  useKbd: () => ref(''),
}));
vi.mock('dashboard/composables/useBrandedSidebar', () => ({
  useBrandedSidebar: () => ({ brandedColor: ref('') }),
}));
vi.mock('dashboard/composables/useRelationships', () => ({
  useRelationships: () => ({ navigationEnabled: ref(false) }),
}));
vi.mock('dashboard/composables/useScrollActiveItemIntoView', () => ({
  useScrollActiveItemIntoView: vi.fn(),
}));
vi.mock('dashboard/components-next/sidebar/provider', async () => {
  const { ref: flag } = await import('vue');
  return {
    provideSidebarContext: vi.fn(),
    useSidebarResize: () => ({
      sidebarWidth: flag(200),
      isCollapsed: flag(false),
      setSidebarWidth: vi.fn(),
      saveWidth: vi.fn(),
      snapToCollapsed: vi.fn(),
      snapToExpanded: vi.fn(),
    }),
  };
});
vi.mock(
  'dashboard/components-next/sidebar/useSidebarKeyboardShortcuts',
  () => ({ useSidebarKeyboardShortcuts: vi.fn() })
);

const Botao = {
  name: 'Button',
  props: ['label', 'icon'],
  template: '<button data-botao :data-icone="icon">{{ label }}</button>',
};

// Monta de verdade, com a ponte no lugar (o marcador) e o resto em dublê.
const montar = (componente, props = {}) =>
  mount(componente, {
    props,
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        Button: Botao,
        Input: true,
        Icon: true,
        Breadcrumb: true,
        ContactSortMenu: true,
        ContactMoreActions: true,
        VoiceCallButton: true,
        RelationshipActionMenu: true,
        ContactOpportunityLink: true,
        LembreteNaFicha: true,
      },
    },
  });

// Procura pelo próprio módulo importado, e não pelo nome: vale também para o
// dublê da montagem rasa.
const ponteDe = wrapper => wrapper.findComponent(NovaConversaEntrada);
const usaDireto = wrapper => wrapper.findComponent(TelaAntigaDireta).exists();

describe('pontos de entrada da Nova conversa', () => {
  it('os marcadores são a ponte e a tela antiga, e não se confundem', () => {
    expect(NovaConversaEntrada.name).toBe('Ponte');
    expect(TelaAntigaDireta.name).toBe('TelaAntigaDireta');
  });

  it('lista de contatos: o botão do cabeçalho abre pela ponte, sem contato', () => {
    const wrapper = montar(ContactHeader, {
      headerTitle: 'Contatos',
      buttonLabel: 'Enviar mensagem',
    });

    const ponte = ponteDe(wrapper);
    expect(ponte.exists()).toBe(true);
    expect(ponte.props('contactId')).toBeUndefined();
    expect(ponte.find('[data-botao]').text()).toBe('Enviar mensagem');
    expect(usaDireto(wrapper)).toBe(false);
  });

  it('página do contato: "Enviar mensagem" abre pela ponte, com o contato da rota', () => {
    const wrapper = montar(ContactsDetailsLayout, {
      selectedContact: { id: 9, name: 'Ana' },
    });

    const ponte = ponteDe(wrapper);
    expect(ponte.exists()).toBe(true);
    expect(ponte.props('contactId')).toBe('9');
    expect(ponte.find('[data-botao]').text()).toBe(
      'CONTACTS_LAYOUT.HEADER.SEND_MESSAGE'
    );
    expect(usaDireto(wrapper)).toBe(false);
  });

  it('ficha de relacionamento: "Enviar mensagem" abre pela ponte, com o id em texto', () => {
    const wrapper = montar(ContactDetailActions, {
      contact: { id: 9, name: 'Ana', blocked: false },
    });

    const ponte = ponteDe(wrapper);
    expect(ponte.exists()).toBe(true);
    expect(ponte.props('contactId')).toBe('9');
    expect(ponte.find('[data-botao]').text()).toBe(
      'CONTACTS_LAYOUT.HEADER.SEND_MESSAGE'
    );
    expect(usaDireto(wrapper)).toBe(false);
  });

  it('menu lateral: o lápis abre pela ponte, sem contato e alinhado ao início', () => {
    // Montagem rasa (o menu tem 1.400 linhas): a ponte vira dublê, mas segue
    // lá, com o nome e os props que o menu passa.
    const wrapper = shallowMount(Sidebar, {
      global: {
        stubs: {
          RouterLink: true,
          SidebarGroup: { props: ['name', 'children'], template: '<li />' },
        },
      },
    });

    const ponte = ponteDe(wrapper);
    expect(ponte.exists()).toBe(true);
    expect(ponte.props('align')).toBe('start');
    expect(ponte.props('contactId')).toBeUndefined();
    expect(usaDireto(wrapper)).toBe(false);
  });

  it('painel do contato na conversa: o componente registrado é a ponte', () => {
    // Options API: confere o módulo que o arquivo registra, sem montar.
    expect(ContactInfo.components.ComposeConversation).toBe(
      NovaConversaEntrada
    );
    expect(Object.values(ContactInfo.components)).not.toContain(
      TelaAntigaDireta
    );
  });
});
