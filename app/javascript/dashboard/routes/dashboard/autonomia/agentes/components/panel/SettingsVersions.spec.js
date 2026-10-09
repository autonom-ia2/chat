import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SettingsVersions from './SettingsVersions.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    getInstructionVersions: vi.fn(),
    restoreInstructionVersion: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

const DialogStub = {
  props: ['title', 'description'],
  emits: ['confirm', 'close'],
  methods: {
    open() {},
    close() {
      this.$emit('close');
    },
  },
  template: `
    <form data-test="dialog-stub" @submit.prevent="$emit('confirm')">
      <slot />
      <slot name="footer" />
    </form>
  `,
};

describe('SettingsVersions', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.getInstructionVersions.mockReset();
    AutonomiaAgentsAPI.restoreInstructionVersion.mockReset();
    AutonomiaAgentsAPI.getInstructionVersions.mockResolvedValue({
      data: {
        payload: [
          {
            id: 1,
            origin: 'guided',
            reason: 'builder',
            created_at: '2026-10-07T12:00:00Z',
            instruction: 'texto guiado que não pode aparecer',
          },
          {
            id: 2,
            origin: 'manual',
            reason: 'manual_edit',
            created_at: '2026-10-08T12:00:00Z',
            instruction: 'texto escrito pela pessoa',
          },
        ],
      },
    });
    AutonomiaAgentsAPI.restoreInstructionVersion.mockResolvedValue({
      data: { id: 42, mode: 'manual' },
    });
  });

  it('oculta texto guiado e mostra somente texto manual', async () => {
    const wrapper = mount(SettingsVersions, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: { stubs: { Dialog: DialogStub } },
    });

    await flushPromises();

    expect(wrapper.text()).not.toContain('texto guiado que não pode aparecer');
    expect(wrapper.text()).toContain('texto escrito pela pessoa');
  });

  it('recarrega a lista quando outra seção salva o agente', async () => {
    const wrapper = mount(SettingsVersions, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard', mode: 'guided' },
        canManage: true,
      },
      global: { stubs: { Dialog: DialogStub } },
    });

    await flushPromises();
    expect(AutonomiaAgentsAPI.getInstructionVersions).toHaveBeenCalledTimes(1);

    await wrapper.setProps({
      agent: { agent_type: 'standard', mode: 'manual' },
    });
    await flushPromises();

    expect(AutonomiaAgentsAPI.getInstructionVersions).toHaveBeenCalledTimes(2);
  });

  it('confirma e restaura a versão escolhida', async () => {
    const wrapper = mount(SettingsVersions, {
      props: {
        agentId: 42,
        agent: { agent_type: 'standard' },
        canManage: true,
      },
      global: { stubs: { Dialog: DialogStub } },
    });

    await flushPromises();
    await wrapper.find('[data-test="restore-version-2"]').trigger('click');
    expect(AutonomiaAgentsAPI.restoreInstructionVersion).not.toHaveBeenCalled();

    await wrapper.find('[data-test="dialog-stub"]').trigger('submit');
    await flushPromises();

    expect(AutonomiaAgentsAPI.restoreInstructionVersion).toHaveBeenCalledWith(
      42,
      2
    );
  });
});
