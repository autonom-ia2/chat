import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import SettingsHandoff from './SettingsHandoff.vue';

vi.mock('dashboard/api/autonomia/agents', () => ({
  default: {
    getHandoffTargets: vi.fn(),
    update: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

describe('SettingsHandoff', () => {
  beforeEach(() => {
    AutonomiaAgentsAPI.getHandoffTargets.mockReset();
    AutonomiaAgentsAPI.update.mockReset();
    AutonomiaAgentsAPI.getHandoffTargets.mockResolvedValue({
      data: {
        members: [{ id: 9, name: 'Ana' }],
        teams: [{ id: 4, name: 'Comercial' }],
      },
    });
    AutonomiaAgentsAPI.update.mockResolvedValue({
      data: { id: 42, config: { handoff_strategy: 'always_ask' } },
    });
  });

  it('salva estratégia e alvo no próprio config', async () => {
    const wrapper = mount(SettingsHandoff, {
      props: {
        agentId: 42,
        agent: { id: 42, config: { handoff_strategy: 'low_confidence' } },
        canManage: true,
      },
    });

    await flushPromises();
    await wrapper.find('#handoff-always_ask').trigger('change');
    await wrapper.find('[data-test="handoff-save"]').trigger('click');

    expect(AutonomiaAgentsAPI.update).toHaveBeenCalledWith(42, {
      agent: {
        config: {
          handoff_strategy: 'always_ask',
          handoff_target_type: 'any',
          handoff_target_id: null,
        },
      },
    });
  });
});
