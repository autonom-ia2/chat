import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import SettingsInstructions from './SettingsInstructions.vue';

withFullI18n();
enableAutoUnmount(afterEach);

const mocks = vi.hoisted(() => {
  const refLike = value => ({ __v_isRef: true, value });
  const dispatch = vi.fn();
  const commit = vi.fn();

  return {
    update: vi.fn(),
    getInstructionVersions: vi.fn(),
    restoreInstructionVersion: vi.fn(),
    upload: vi.fn(),
    dispatch,
    commit,
    builderStatus: refLike('idle'),
    builderPhase: refLike('collecting'),
    builderMessages: refLike([]),
    builderThread: refLike({ id: 91, agent_id: 42 }),
    builderUiFlags: refLike({ sending: false, creating: false }),
    empty: refLike([]),
    store: { dispatch, commit, getters: {} },
  };
});

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    update: mocks.update,
    getInstructionVersions: mocks.getInstructionVersions,
    restoreInstructionVersion: mocks.restoreInstructionVersion,
  },
}));

vi.mock('dashboard/api/autonomia/builderImages', () => ({
  default: { upload: mocks.upload },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => mocks.store,
  useMapGetter: key => {
    if (key.endsWith('getMessages')) return mocks.builderMessages;
    if (key.endsWith('getStatus')) return mocks.builderStatus;
    if (key.endsWith('getPhase')) return mocks.builderPhase;
    if (key.endsWith('getThread')) return mocks.builderThread;
    if (key.endsWith('getUIFlags')) return mocks.builderUiFlags;
    return mocks.empty;
  },
}));

const agent = {
  id: 42,
  name: 'Clara',
  mode: 'guided',
  human_card: 'Ajuda clientes com dúvidas sobre pedidos.',
  has_guided_version: false,
  instruction: 'instrução gerada que nunca deve aparecer',
};

const DialogStub = {
  props: ['title', 'description'],
  emits: ['close'],
  data: () => ({ isOpen: false }),
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
      this.$emit('close');
    },
  },
  template: `
    <div v-if="isOpen" data-test="dialog-stub">
      <slot />
      <slot name="footer" />
    </div>
  `,
};

describe('SettingsInstructions', () => {
  beforeEach(() => {
    mocks.update.mockReset();
    mocks.update.mockResolvedValue({ data: { id: 42, mode: 'manual' } });
    mocks.getInstructionVersions.mockReset();
    mocks.getInstructionVersions.mockResolvedValue({
      data: { payload: [], has_guided_version: false },
    });
    mocks.restoreInstructionVersion.mockReset();
    mocks.upload.mockReset();
    mocks.dispatch.mockReset();
    mocks.dispatch.mockResolvedValue(undefined);
    mocks.commit.mockReset();
    mocks.builderThread.value = { id: 91, agent_id: 42 };
  });

  it('não expõe a instrução guiada no campo manual', () => {
    const wrapper = mount(SettingsInstructions, {
      props: { agent, agentId: 42, canManage: true, resumeBuild: false },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });

    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.text()).not.toContain(agent.instruction);
  });

  it('abre o modo manual com o campo vazio e só salva texto preenchido', async () => {
    const wrapper = mount(SettingsInstructions, {
      props: { agent, agentId: 42, canManage: true, resumeBuild: false },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });

    await wrapper.find('[data-test="open-manual"]').trigger('click');
    await wrapper.find('[data-test="confirm-manual"]').trigger('click');

    const field = wrapper.find('textarea');
    expect(field.exists()).toBe(true);
    expect(field.element.value).toBe('');

    await wrapper.find('[data-test="save-manual"]').trigger('click');
    expect(mocks.update).not.toHaveBeenCalled();

    await field.setValue('Instrução escrita pela pessoa.');
    await wrapper.find('[data-test="save-manual"]').trigger('click');

    expect(mocks.update).toHaveBeenCalledWith(42, {
      agent: {
        mode: 'manual',
        instruction: 'Instrução escrita pela pessoa.',
      },
    });
  });

  it('não oferece retorno ao guiado sem versão guiada', () => {
    const wrapper = mount(SettingsInstructions, {
      props: {
        agent: { ...agent, mode: 'manual', instruction: 'texto da pessoa' },
        agentId: 42,
        canManage: true,
        resumeBuild: false,
      },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });

    expect(wrapper.find('[data-test="return-guided"]').exists()).toBe(false);
    expect(wrapper.find('textarea').element.value).toBe('texto da pessoa');
  });

  it('retoma a conversa existente quando o painel recebe resumeBuild', async () => {
    mount(SettingsInstructions, {
      props: { agent, agentId: 42, canManage: true, resumeBuild: true },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });

    await flushPromises();

    expect(mocks.dispatch).toHaveBeenCalledWith(
      'autonomiaBuildThreads/resume',
      {
        agentId: 42,
        signal: expect.any(AbortSignal),
      }
    );
  });

  it('não envia a thread antiga se fechar durante o upload das imagens', async () => {
    let resolveUpload;
    mocks.upload.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveUpload = resolve;
        })
    );
    const wrapper = mount(SettingsInstructions, {
      props: { agent, agentId: 42, canManage: true, resumeBuild: false },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub },
      },
    });

    const sending = wrapper.vm.onReconverseSend({
      content: 'Pergunta antiga',
      images: [{ name: 'foto.png' }],
    });
    expect(mocks.upload).toHaveBeenCalledTimes(1);

    wrapper.vm.closeReconverse();
    resolveUpload({ data: { signed_id: 'signed-old' } });
    await sending;
    await flushPromises();

    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'autonomiaBuildThreads/send',
      expect.anything()
    );
    expect(mocks.commit).toHaveBeenCalledWith('autonomiaBuildThreads/RESET');
  });
});
