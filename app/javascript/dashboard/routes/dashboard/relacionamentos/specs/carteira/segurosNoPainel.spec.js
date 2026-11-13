import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import {
  criarI18n,
  criarStore,
} from 'dashboard/components-next/painel-do-contato/specs/apoio';

// O que decide se o painel da conversa ganha os seguros (#2897), no painel de
// verdade (o ContactPanel, nos dois desenhos: o antigo e o novo). A conta sem a
// carteira fica idêntica à de hoje: não monta a peça, não baixa o arquivo dela
// e não chama rota. A função personalizada sem a chave de contatos também não
// (o servidor responderia 401). A peça de verdade tem teste próprio
// (painelDeSeguros.spec.js); aqui ela é um pedaço de mentira que só conta
// quantas vezes foi baixada e montada.
//
// ATENÇÃO À ORDEM: o arquivo de mentira só é "baixado" uma vez por arquivo de
// teste. Os casos em que ele NÃO pode ser baixado vêm antes do caso em que é.
const peca = vi.hoisted(() => ({ baixada: 0, montada: 0 }));
vi.mock('../../components/carteira/PainelDeSeguros.vue', async () => {
  peca.baixada += 1;
  const { defineComponent, h } = await import('vue');
  return {
    __esModule: true,
    default: defineComponent({
      name: 'PainelDeSeguros',
      props: { contactId: { type: [Number, String], default: null } },
      setup(props) {
        peca.montada += 1;
        return () => h('div', { 'data-peca-de-seguros': props.contactId });
      },
    }),
  };
});
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { daPessoa: vi.fn() },
}));

// A conta aberta, como o servidor manda: `carteira_seguros` liga a carteira.
const conta = vi.hoisted(() => ({ atual: {} }));
vi.mock('dashboard/composables/useAccount', async () => {
  const { computed } = await import('vue');
  return {
    useAccount: () => ({
      isCloudFeatureEnabled: () => false,
      currentAccount: computed(() => conta.atual),
    }),
  };
});
const ui = vi.hoisted(() => ({ updateUISettings: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref } = await import('vue');
  return {
    useUISettings: () => ({
      uiSettings: ref({ is_contact_sidebar_open: true }),
      updateUISettings: ui.updateUISettings,
      isContactSidebarItemOpen: () => false,
      conversationSidebarItemsOrder: ref([]),
      toggleSidebarUIState: vi.fn(),
      isOnExpandedLayout: ref(false),
    }),
  };
});
// Celular (390 px): é onde o painel fecha "ao clicar fora".
vi.mock('@vueuse/core', async importOriginal => {
  const { ref } = await import('vue');
  return {
    ...(await importOriginal()),
    useWindowSize: () => ({ width: ref(390), height: ref(844) }),
  };
});

enableAutoUnmount(afterEach);

const CONTATO = 9;
// A peça de mentira, com o contato que recebeu.
const PECA = '[data-peca-de-seguros]';
const CONVERSA = { id: 42, inbox_id: 1, meta: { sender: { id: CONTATO } } };
const PAINEL_NOVO = { painel_contato_enxuto: true };
const PAINEL_ANTIGO = {};
const DESENHOS = [
  ['painel antigo', PAINEL_ANTIGO],
  ['painel novo', PAINEL_NOVO],
];

const extras = {
  canOperateConversation: () => () => true,
  'contacts/getContact': () => () => ({ id: CONTATO, name: 'Marcos' }),
  'conversationMetadata/getConversationMetadata': () => () => ({}),
  getAppliedContactFilter: () => null,
  'integrations/getIntegration': () => () => ({ enabled: false }),
};

// O painel de verdade, com os vizinhos da peça trocados por caixas vazias. O
// painel novo de mentira desenha o encaixe que o de verdade oferece.
const VIZINHOS = {
  PainelDoContato: {
    template: '<div data-painel-novo><slot name="depois-do-contato" /></div>',
  },
  SidebarActionsHeader: true,
  ContactInfo: true,
  ContatoBasico: true,
  ContactOriginsPanel: true,
  Draggable: true,
};

const montarPainel = async ({ features, quem = {} }) => {
  const { store } = criarStore(
    { conversaSelecionada: CONVERSA, features, ...quem },
    extras
  );
  const painel = mount(ContactPanel, {
    props: { conversationId: CONVERSA.id, inboxId: 1 },
    global: { plugins: [store, criarI18n()], stubs: VIZINHOS },
  });
  await flushPromises();
  await vi.dynamicImportSettled();
  await flushPromises();
  return painel;
};

const SEM_VER_CONTATOS = {
  papel: 'agent',
  funcao: 5,
  permissoes: ['conversation_manage', 'crm_view'],
};
const SO_VE_CONTATOS = {
  papel: 'agent',
  funcao: 6,
  permissoes: ['contact_view'],
};

beforeEach(() => {
  peca.montada = 0;
  conta.atual = { id: 1, carteira_seguros: true };
});

describe('conta sem a carteira de seguros', () => {
  it.each(DESENHOS)(
    '%s: não monta a peça, não baixa o arquivo dela e não chama rota',
    async (_nome, features) => {
      conta.atual = { id: 1, carteira_seguros: false };

      const painel = await montarPainel({ features });

      expect(painel.find(PECA).exists()).toBe(false);
      expect(peca).toEqual({ baixada: 0, montada: 0 });
      expect(SegurosAPI.daPessoa).not.toHaveBeenCalled();
    }
  );

  it('conta que nem diz se tem a carteira fica igual', async () => {
    conta.atual = { id: 1 };

    const painel = await montarPainel({ features: PAINEL_NOVO });

    expect(painel.find(PECA).exists()).toBe(false);
    expect(peca).toEqual({ baixada: 0, montada: 0 });
  });
});

describe('conta com a carteira, para quem não pode ver contatos', () => {
  it.each(DESENHOS)(
    '%s: a função sem a chave de contatos não vê os seguros do contato da conversa, e a tela nem pergunta',
    async (_nome, features) => {
      const painel = await montarPainel({ features, quem: SEM_VER_CONTATOS });

      expect(painel.find(PECA).exists()).toBe(false);
      expect(peca).toEqual({ baixada: 0, montada: 0 });
      expect(SegurosAPI.daPessoa).not.toHaveBeenCalled();
    }
  );
});

// Daqui para baixo a peça é baixada (ver o aviso de ordem no alto do arquivo).
describe('conta com a carteira, para quem pode ver contatos', () => {
  const pecaNoPainel = painel => painel.find(PECA);

  it.each(DESENHOS)(
    '%s: o agente comum vê a peça, com o contato da conversa',
    async (_nome, features) => {
      const painel = await montarPainel({ features });

      await vi.waitFor(() => expect(pecaNoPainel(painel).exists()).toBe(true));
      expect(pecaNoPainel(painel).attributes('data-peca-de-seguros')).toBe(
        String(CONTATO)
      );
      expect(peca.baixada).toBe(1);
      expect(peca.montada).toBe(1);
    }
  );

  it('no painel novo a peça entra no encaixe logo abaixo do contato', async () => {
    const painel = await montarPainel({ features: PAINEL_NOVO });

    const noEncaixe = `[data-painel-novo] > ${PECA}`;

    await vi.waitFor(() => expect(painel.find(noEncaixe).exists()).toBe(true));
  });

  it('a função com contact_view também vê', async () => {
    const painel = await montarPainel({
      features: PAINEL_NOVO,
      quem: SO_VE_CONTATOS,
    });

    await vi.waitFor(() => expect(pecaNoPainel(painel).exists()).toBe(true));
  });
});

describe('o painel que fecha "ao clicar fora" (celular) e a gaveta do seguro', () => {
  const montarGaveta = features => {
    const { store } = criarStore(
      { conversaSelecionada: CONVERSA, features },
      extras
    );
    return mount(ConversationSidebar, {
      props: { currentChat: CONVERSA },
      global: {
        plugins: [store, criarI18n()],
        stubs: { ContactPanel: true },
      },
      attachTo: document.body,
    });
  };
  // O que fica no <body> com a gaveta do seguro aberta: a própria gaveta e o
  // fundo escuro atrás dela.
  const gavetaAberta = () => {
    const fundo = document.createElement('div');
    const gaveta = document.createElement('div');
    gaveta.setAttribute('data-relacionamentos', 'gaveta-do-seguro');
    const botao = document.createElement('button');
    gaveta.appendChild(botao);
    document.body.append(fundo, gaveta);
    const tirar = () => [fundo, gaveta].forEach(no => no.remove());
    return { fundo, botao, tirar };
  };
  const tocar = async alvo => {
    alvo.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    alvo.click();
    await flushPromises();
  };
  // O onClickOutside do vueuse ignora um segundo clique no mesmo ciclo.
  const proximoCiclo = () =>
    new Promise(resolve => {
      setTimeout(resolve, 0);
    });
  const fechouOPainel = () =>
    expect.objectContaining({ is_contact_sidebar_open: false });

  it.each(DESENHOS)(
    '%s: tocar dentro da gaveta ou no fundo dela não fecha o painel',
    async (_nome, features) => {
      montarGaveta(features);
      const { fundo, botao, tirar } = gavetaAberta();

      await tocar(botao);
      await proximoCiclo();
      await tocar(fundo);

      expect(ui.updateUISettings).not.toHaveBeenCalled();
      tirar();
    }
  );

  it.each(DESENHOS)(
    '%s: sem gaveta aberta, tocar fora fecha o painel como sempre',
    async (_nome, features) => {
      montarGaveta(features);
      const { tirar } = gavetaAberta();
      tirar();
      const fora = document.createElement('button');
      document.body.appendChild(fora);

      await tocar(fora);
      fora.remove();

      expect(ui.updateUISettings).toHaveBeenCalledWith(fechouOPainel());
    }
  );
});
