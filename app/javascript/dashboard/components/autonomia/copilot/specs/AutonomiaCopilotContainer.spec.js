import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaCopilotAPI from 'dashboard/api/autonomiaCopilot';
import { useAutonomiaCopilotStore } from 'dashboard/store/modules/autonomiaCopilot';
import AutonomiaCopilotContainer from '../AutonomiaCopilotContainer.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ is_autonomia_copilot_panel_open: true }),
    updateUISettings: vi.fn(),
  }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    if (getter === 'globalConfig/get') {
      return ref({ crmKanbanEnabled: true, crmCopilotEnabled: true });
    }
    if (getter === 'getSelectedChat') return ref({ id: 42 });
    return ref(null);
  },
}));
vi.mock('dashboard/api/autonomiaCopilot', () => ({
  default: { listAgents: vi.fn(), chat: vi.fn() },
}));

const mountCopilot = async () => {
  const wrapper = mount(AutonomiaCopilotContainer, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      directives: { onClickOutside: {}, dompurifyHtml: {} },
    },
  });
  await flushPromises();
  return wrapper;
};

const send = async (textarea, text) => {
  await textarea.setValue(text);
  await textarea.trigger('keydown', { key: 'Enter' });
  await flushPromises();
};

describe('AutonomiaCopilotContainer', () => {
  let wrapper;

  beforeEach(() => {
    AutonomiaCopilotAPI.listAgents.mockResolvedValue({
      data: { agents: [{ id: 7, name: 'Lia' }] },
    });
  });

  afterEach(() => {
    wrapper?.unmount();
    useAutonomiaCopilotStore().reset();
    vi.clearAllMocks();
  });

  it('clears the input as soon as the question enters the thread', async () => {
    let resolveChat;
    AutonomiaCopilotAPI.chat.mockReturnValue(
      new Promise(resolve => {
        resolveChat = resolve;
      })
    );
    wrapper = await mountCopilot();
    const textarea = wrapper.find('textarea');

    await send(textarea, 'Resuma a conversa');

    expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledWith(
      42,
      expect.objectContaining({ agentId: 7, message: 'Resuma a conversa' })
    );
    expect(textarea.element.value).toBe('');

    resolveChat({ data: { available: true, text: 'Resumo.' } });
    await flushPromises();
    expect(useAutonomiaCopilotStore().messages).toHaveLength(2);
  });

  it('keeps the text when a reply is still loading', async () => {
    AutonomiaCopilotAPI.chat.mockReturnValue(new Promise(() => {}));
    wrapper = await mountCopilot();
    const textarea = wrapper.find('textarea');

    await send(textarea, 'Primeira');
    await send(textarea, 'Segunda');

    expect(AutonomiaCopilotAPI.chat).toHaveBeenCalledOnce();
    expect(textarea.element.value).toBe('Segunda');
  });
});
