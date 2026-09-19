import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import { useAutonomiaGuideStore } from 'dashboard/store/modules/autonomiaGuide';
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
vi.mock('dashboard/api/autonomiaGuide', () => ({ default: { chat: vi.fn() } }));

const mountGuide = () =>
  mount(AutonomiaGuideContainer, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      directives: { onClickOutside: {}, dompurifyHtml: {} },
    },
  });

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

  it('keeps the text when a reply is still loading', async () => {
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
  });
});
