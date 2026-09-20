import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import {
  useAutonomiaGuideStore,
  motivoUtilizavel,
} from 'dashboard/store/modules/autonomiaGuide';
import AutonomiaGuideContainer from '../AutonomiaGuideContainer.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home' }),
  useRouter: () => ({ resolve: () => ({ matched: [] }), push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ is_autonomia_guide_panel_open: true }),
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'accounts/getAccount') {
      return ref(() => ({ autonomia_guide_available: true }));
    }
    if (getter === 'getCurrentAccountId') return ref(1);
    return ref(() => false);
  },
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { chat: vi.fn(), executarAcao: vi.fn() },
}));

const ACAO = {
  nome: 'criar_funil',
  dados: { nome: 'Vendas' },
  descricao: {
    frase: 'Vou criar o funil Vendas.',
    detalhe: 'criar_funil(nome: "Vendas")',
  },
};

const mountGuide = () =>
  mount(AutonomiaGuideContainer, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      directives: { onClickOutside: {}, dompurifyHtml: {} },
    },
  });

// Os botões do cartão de ação são renderizados pelo Button compartilhado, que
// põe o rótulo num <span>. Com o $t de teste o rótulo é a própria chave.
const findByLabel = (wrapper, chave) =>
  wrapper.findAll('button').find(botao => botao.text().includes(chave));

const comAcaoProposta = () => {
  const store = useAutonomiaGuideStore();
  store.addAssistantMessage({ content: 'Posso criar para você.', acao: ACAO });
  return store;
};

describe('AutonomiaGuideContainer', () => {
  let wrapper;

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaGuideStore().reset();
    vi.clearAllMocks();
  });

  it('clears the input as soon as the question enters the thread', async () => {
    let resolveChat;
    AutonomiaGuideAPI.chat.mockReturnValue(
      new Promise(resolve => {
        resolveChat = resolve;
      })
    );
    wrapper = mountGuide();
    const textarea = wrapper.find('textarea');

    await textarea.setValue('Como crio um funil?');
    await textarea.trigger('keydown', { key: 'Enter' });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('');

    resolveChat({ data: { available: true, text: 'Assim.' } });
    await flushPromises();
    expect(useAutonomiaGuideStore().messages).toHaveLength(2);
  });

  it('keeps the text and warns when a reply is still loading', async () => {
    AutonomiaGuideAPI.chat.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    const textarea = wrapper.find('textarea');

    await textarea.setValue('Primeira');
    await textarea.trigger('keydown', { key: 'Enter' });
    await flushPromises();
    await textarea.setValue('Segunda');
    await textarea.trigger('keydown', { key: 'Enter' });
    await flushPromises();

    expect(AutonomiaGuideAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('Segunda');
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.SENDING');
  });

  it('sends a single request when confirm is clicked twice', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    await flushPromises();

    const confirmar = findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM');
    await confirmar.trigger('click');
    await confirmar.trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.executarAcao).toHaveBeenCalledOnce();
  });

  it('warns instead of losing the outcome when the record is gone', async () => {
    const store = comAcaoProposta();
    let resolverAcao;
    AutonomiaGuideAPI.executarAcao.mockReturnValue(
      new Promise(resolve => {
        resolverAcao = resolve;
      })
    );
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    // "Nova conversa" durante a execução: o cartão que mostraria o desfecho
    // deixa de existir, mas a ação já rodou no servidor.
    store.reset();
    resolverAcao({ data: { mensagem: 'Pronto, feito.' } });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('AUTONOMIA_GUIDE.ACTION.LOST');
  });

  it('hides a platform error that carries an HTTP status', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockRejectedValue({
      response: { data: { error: 'A plataforma respondeu 422.' } },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.ACTION.FAILED_GENERIC');
    expect(wrapper.text()).not.toContain('422');
  });

  it('keeps a readable platform error', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockRejectedValue({
      response: { data: { error: 'Este funil não existe mais.' } },
    });
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(wrapper.text()).toContain('Este funil não existe mais.');
  });

  it('lets the user confirm again after declining', async () => {
    comAcaoProposta();
    AutonomiaGuideAPI.executarAcao.mockReturnValue(new Promise(() => {}));
    wrapper = mountGuide();
    await flushPromises();

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CANCEL').trigger(
      'click'
    );
    await flushPromises();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.ACTION.CANCELLED');

    await findByLabel(wrapper, 'AUTONOMIA_GUIDE.ACTION.CONFIRM').trigger(
      'click'
    );
    await flushPromises();

    expect(AutonomiaGuideAPI.executarAcao).toHaveBeenCalledOnce();
  });

  it('names the panel and the message region for screen readers', async () => {
    wrapper = mountGuide();
    await flushPromises();

    expect(
      wrapper.find('[role="complementary"]').attributes('aria-label')
    ).toBe('AUTONOMIA_GUIDE.A11Y.PANEL');
    const log = wrapper.find('[role="log"]');
    expect(log.attributes('aria-live')).toBe('polite');
    expect(log.attributes('aria-label')).toBe('AUTONOMIA_GUIDE.A11Y.LOG');
    expect(
      wrapper.find('[aria-label="AUTONOMIA_GUIDE.A11Y.SEND"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[aria-label="AUTONOMIA_GUIDE.A11Y.CLOSE"]').exists()
    ).toBe(true);
  });
});

describe('motivoUtilizavel', () => {
  it('returns the reason when it reads as a message to a person', () => {
    expect(motivoUtilizavel('  Este funil não existe mais. ')).toBe(
      'Este funil não existe mais.'
    );
  });

  it('drops a reason that carries an HTTP status code', () => {
    expect(motivoUtilizavel('A plataforma respondeu 422.')).toBe('');
    expect(motivoUtilizavel('500 Internal Server Error')).toBe('');
  });

  it('keeps a number that is not an HTTP status', () => {
    expect(motivoUtilizavel('O limite é de 50 por dia.')).toBe(
      'O limite é de 50 por dia.'
    );
    expect(motivoUtilizavel('O contato 1042 já saiu do funil.')).toBe(
      'O contato 1042 já saiu do funil.'
    );
  });

  it('drops what is not a usable string', () => {
    expect(motivoUtilizavel(undefined)).toBe('');
    expect(motivoUtilizavel('   ')).toBe('');
    expect(motivoUtilizavel('x'.repeat(200))).toBe('');
  });
});
