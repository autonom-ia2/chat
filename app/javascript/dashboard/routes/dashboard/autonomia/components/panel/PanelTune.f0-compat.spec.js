import { shallowMount } from '@vue/test-utils';
import { ref } from 'vue';
import PanelTune from './PanelTune.vue';

const currentAccount = ref({
  id: 9,
  autonomia_agents_redesign: true,
});
const reactiveGetters = {
  'autonomiaBuildThreads/getMessages': ref([]),
  'autonomiaBuildThreads/getStatus': ref('ready'),
  'autonomiaBuildThreads/getPhase': ref('reviewing'),
  'autonomiaBuildThreads/getUIFlags': ref({
    sending: false,
    creating: false,
  }),
  'autonomiaAgents/getInstructionVersions': ref([]),
  'autonomiaAgents/getUIFlags': ref({ updatingItem: false }),
  'autonomiaSources/getUIFlags': ref({ creatingItem: false }),
};

const mocks = vi.hoisted(() => ({
  alert: vi.fn(),
  dialogOpen: vi.fn(),
  dialogClose: vi.fn(),
  store: {
    getters: {
      'autonomiaBuildThreads/getThread': { id: 88 },
      'autonomiaAgents/getUIFlags': { updatingItem: false },
      'autonomiaSources/getUIFlags': { creatingItem: false },
    },
    dispatch: vi.fn(),
    commit: vi.fn(),
  },
  builderImages: {
    upload: vi.fn(),
  },
  canManage: { value: true },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => mocks.store,
  useMapGetter: key => reactiveGetters[key],
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount }),
}));

vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => mocks.canManage,
}));

vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

vi.mock('dashboard/api/autonomia/builderImages', () => ({
  default: mocks.builderImages,
}));

const DialogStub = {
  name: 'Dialog',
  setup(_props, { expose }) {
    expose({ open: mocks.dialogOpen, close: mocks.dialogClose });
    return {};
  },
  template: '<div data-test="reconverse-dialog"><slot /></div>',
};

const BuilderChatStub = {
  name: 'BuilderChat',
  props: ['messages', 'isSending', 'disabled', 'canAttach', 'isAttaching'],
  template: '<div data-test="builder-chat" />',
};

const agent = overrides => ({
  id: 7,
  name: 'Clara',
  agent_type: 'support',
  mode: 'guided',
  greeting: 'Olá',
  fallback_message: 'Vou chamar uma pessoa.',
  tone: 'friendly',
  instruction: 'Atenda com clareza.',
  human_card: 'Ajuda clientes.',
  actuation: 'external',
  config: {},
  ...overrides,
});

const mountPanel = currentAgent =>
  shallowMount(PanelTune, {
    props: { agent: currentAgent, agentId: currentAgent.id },
    global: {
      stubs: {
        Dialog: DialogStub,
        Avatar: true,
        NextButton: true,
        Input: true,
        TextArea: true,
        ChoiceSelect: true,
        Switch: true,
        Icon: true,
        BuilderChat: BuilderChatStub,
        AgentAudienceForm: true,
        AgentScheduleForm: true,
      },
    },
  });

describe('F0: compatibilidade de PanelTune com thread retomada', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    currentAccount.value = {
      id: 9,
      autonomia_agents_redesign: true,
    };
    reactiveGetters['autonomiaBuildThreads/getMessages'].value = [];
    reactiveGetters['autonomiaBuildThreads/getStatus'].value = 'ready';
    reactiveGetters['autonomiaBuildThreads/getPhase'].value = 'reviewing';
    reactiveGetters['autonomiaBuildThreads/getUIFlags'].value = {
      sending: false,
      creating: false,
    };
    reactiveGetters['autonomiaAgents/getInstructionVersions'].value = [];
    reactiveGetters['autonomiaAgents/getUIFlags'].value = {
      updatingItem: false,
    };
    reactiveGetters['autonomiaSources/getUIFlags'].value = {
      creatingItem: false,
    };
    mocks.canManage.value = true;
    mocks.dialogOpen.mockReset();
    mocks.dialogClose.mockReset();
    mocks.store.getters['autonomiaBuildThreads/getThread'] = { id: 88 };
    mocks.store.getters['autonomiaAgents/getUIFlags'] = {
      updatingItem: false,
    };
    mocks.store.getters['autonomiaSources/getUIFlags'] = {
      creatingItem: false,
    };
    mocks.store.dispatch.mockResolvedValue(undefined);
    mocks.builderImages.upload.mockResolvedValue({
      data: { signed_id: 'signed-image-1' },
    });
  });

  it('mostra o histórico real e não apaga a thread hidratada ao abrir', async () => {
    const messages = [
      { id: 1, role: 'user', content: 'Atendo escolas.' },
      { id: 2, role: 'assistant', content: 'Qual público você atende?' },
    ];
    reactiveGetters['autonomiaBuildThreads/getMessages'].value = messages;
    const wrapper = mountPanel(agent());

    expect(wrapper.findComponent(BuilderChatStub).props('messages')).toEqual(
      messages
    );

    await wrapper.vm.openReconverse();

    expect(mocks.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      { agentId: 7 }
    );
    expect(mocks.store.commit).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/RESET'
    );
    expect(mocks.dialogOpen).toHaveBeenCalledTimes(1);
    expect(mocks.store.getters['autonomiaBuildThreads/getThread']).toEqual({
      id: 88,
    });
  });

  it('envia a primeira fala usando o id existente e nunca chama start', async () => {
    const wrapper = mountPanel(agent());

    await wrapper.vm.onReconverseSend({ content: 'Ajuste a saudação' });

    expect(mocks.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/send',
      {
        threadId: 88,
        content: 'Ajuste a saudação',
        extra: { image_signed_ids: [] },
      }
    );
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
  });

  it('preserva a criação antiga quando o fluxo legado não tem thread', async () => {
    currentAccount.value.autonomia_agents_redesign = false;
    mocks.store.getters['autonomiaBuildThreads/getThread'] = null;
    const wrapper = mountPanel(
      agent({ mode: 'guided', instruction: 'Atenda com esta regra.' })
    );

    await wrapper.vm.openReconverse();
    await wrapper.vm.onReconverseSend({ content: 'Nova instrução' });

    expect(mocks.store.commit).toHaveBeenCalledWith(
      'autonomiaBuildThreads/RESET'
    );
    expect(mocks.dialogOpen).toHaveBeenCalledTimes(1);
    expect(mocks.store.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      {
        agentId: 7,
        type: 'support',
        message: 'Nova instrução',
        image_signed_ids: [],
      }
    );
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/send',
      expect.anything()
    );
  });

  it('não abre nem escreve quando o painel manual tenta abrir uma conversa', async () => {
    const wrapper = mountPanel(agent({ mode: 'manual' }));

    await wrapper.vm.openReconverse();

    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      expect.anything()
    );
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    expect(mocks.store.commit).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/RESET'
    );
    expect(mocks.dialogOpen).not.toHaveBeenCalled();
  });

  it('não faz upload nem cria thread se a retomada não deixou id disponível', async () => {
    const wrapper = mountPanel(agent());

    await wrapper.vm.openReconverse();
    mocks.store.getters['autonomiaBuildThreads/getThread'] = null;

    await wrapper.vm.onReconverseSend({
      content: 'Ajuste sem thread',
      images: [{ name: 'logo.png' }],
    });

    expect(mocks.builderImages.upload).not.toHaveBeenCalled();
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/start',
      expect.anything()
    );
    expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/send',
      expect.anything()
    );
    expect(mocks.alert).toHaveBeenCalledWith('AGENTS.BUILDER.SEND_ERROR');
  });

  it.each([401, 404, 422])(
    'não abre o diálogo nem cria thread quando o resume retorna %s',
    async status => {
      mocks.store.dispatch.mockImplementation(action => {
        if (action === 'autonomiaBuildThreads/resume') {
          return Promise.reject(
            Object.assign(new Error('resume failed'), { response: { status } })
          );
        }
        return Promise.resolve();
      });
      const wrapper = mountPanel(agent());

      await wrapper.vm.openReconverse();

      expect(mocks.dialogOpen).not.toHaveBeenCalled();
      expect(mocks.store.commit).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/RESET'
      );
      expect(mocks.store.dispatch).not.toHaveBeenCalledWith(
        'autonomiaBuildThreads/start',
        expect.anything()
      );
      expect(mocks.alert).toHaveBeenCalledWith(
        expect.stringMatching(/^AGENTS\./)
      );
    }
  );
});
