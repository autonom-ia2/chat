import {
  mount,
  shallowMount,
  flushPromises,
  enableAutoUnmount,
} from '@vue/test-utils';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — a chave painel_contato_enxuto da conta: desligada, o painel e a gaveta
// ficam como sempre; ligada, entra o painel novo, a gaveta ocupa a tela no
// celular e um clique dentro de um Dialog aberto não fecha o painel.
const ui = vi.hoisted(() => ({
  uiSettings: { value: { is_contact_sidebar_open: true } },
  updateUISettings: vi.fn(),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ui.uiSettings,
    updateUISettings: ui.updateUISettings,
    isContactSidebarItemOpen: () => false,
    conversationSidebarItemsOrder: { value: [] },
    toggleSidebarUIState: vi.fn(),
    isOnExpandedLayout: { value: false },
  }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: () => false }),
}));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useWindowSize: () => ({ width: { value: 390 } }),
}));

enableAutoUnmount(afterEach);

const CONVERSA = { id: 42, inbox_id: 1, meta: { sender: { id: 9 } } };

const extras = {
  canOperateConversation: () => () => true,
  'contacts/getContact': () => () => ({ id: 9, name: 'Marcos' }),
  'conversationMetadata/getConversationMetadata': () => () => ({}),
  getAppliedContactFilter: () => null,
  'integrations/getIntegration': () => () => ({ enabled: false }),
};

const storeCom = features => {
  return criarStore({ conversaSelecionada: CONVERSA, features }, extras);
};

const montarPainel = features => {
  const { store } = storeCom(features);
  return shallowMount(ContactPanel, {
    props: { conversationId: 42, inboxId: 1 },
    global: { plugins: [store, criarI18n()] },
  });
};

describe('ContactPanel com a chave da conta', () => {
  it('desligada: o painel antigo, sem o novo', () => {
    const wrapper = montarPainel({});
    expect(wrapper.findComponent({ name: 'PainelDoContato' }).exists()).toBe(
      false
    );
    expect(
      wrapper.findComponent({ name: 'SidebarActionsHeader' }).exists()
    ).toBe(true);
  });

  it('ligada: o painel novo, sem o antigo', () => {
    const wrapper = montarPainel({ painel_contato_enxuto: true });
    expect(wrapper.findComponent({ name: 'PainelDoContato' }).exists()).toBe(
      true
    );
    expect(
      wrapper.findComponent({ name: 'SidebarActionsHeader' }).exists()
    ).toBe(false);
  });

  it('a URL e o navegador não ligam o painel novo (?painel=novo saiu)', () => {
    window.history.replaceState({}, '', '/?painel=novo');
    try {
      window.localStorage.setItem('proto2138_painel_do_contato', 'novo');
    } catch {
      // sem armazenamento, nada a provar
    }
    const wrapper = montarPainel({});
    expect(wrapper.findComponent({ name: 'PainelDoContato' }).exists()).toBe(
      false
    );
    window.history.replaceState({}, '', '/');
  });
});

describe('ConversationSidebar com a chave da conta (celular, 390 px)', () => {
  const montarGaveta = features => {
    const { store } = storeCom(features);
    return mount(ConversationSidebar, {
      props: { currentChat: CONVERSA },
      global: {
        plugins: [store, criarI18n()],
        stubs: { ContactPanel: true },
      },
      attachTo: document.body,
    });
  };
  const dialogoAberto = () => {
    const dialogo = document.createElement('dialog');
    dialogo.setAttribute('open', '');
    const botao = document.createElement('button');
    dialogo.appendChild(botao);
    document.body.appendChild(dialogo);
    return { dialogo, botao };
  };

  beforeEach(() => ui.updateUISettings.mockClear());

  it('desligada: a gaveta tem max-w-sm e um clique no Dialog fecha o painel, como hoje', async () => {
    const wrapper = montarGaveta({});
    expect(wrapper.classes()).toContain('max-w-sm');
    const { dialogo, botao } = dialogoAberto();
    botao.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    botao.click();
    await flushPromises();
    expect(ui.updateUISettings).toHaveBeenCalledWith(
      expect.objectContaining({ is_contact_sidebar_open: false })
    );
    dialogo.remove();
  });

  it('ligada: tela inteira no celular, e o clique dentro do Dialog não fecha o painel', async () => {
    const wrapper = montarGaveta({ painel_contato_enxuto: true });
    expect(wrapper.classes()).not.toContain('max-w-sm');
    const { dialogo, botao } = dialogoAberto();
    botao.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    botao.click();
    await flushPromises();
    expect(ui.updateUISettings).not.toHaveBeenCalled();

    // Fora do Dialog, fecha como sempre. O onClickOutside do vueuse ignora um
    // segundo clique no mesmo ciclo (setTimeout 0): espera o ciclo passar.
    dialogo.remove();
    await new Promise(resolve => {
      setTimeout(resolve, 0);
    });
    const fora = document.createElement('button');
    document.body.appendChild(fora);
    fora.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true }));
    fora.click();
    await flushPromises();
    fora.remove();
    expect(ui.updateUISettings).toHaveBeenCalledWith(
      expect.objectContaining({ is_contact_sidebar_open: false })
    );
  });
});
