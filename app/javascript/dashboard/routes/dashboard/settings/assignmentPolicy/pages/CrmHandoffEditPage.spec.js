import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import CrmHandoffEditPage from './CrmHandoffEditPage.vue';

// Stub the surrounding harness (router, i18n, store, alerts, API) so we can
// mount the settings page in isolation and assert the handoff payload
// round-trips the pool + escalation_action fields correctly.
const getAiSettings = vi.fn();
const getPipelines = vi.fn(() =>
  Promise.resolve({ data: { payload: [{ id: 1, name: 'Funil Comercial' }] } })
);
const getPipelineInboxes = vi.fn(() =>
  Promise.resolve({ data: { payload: [] } })
);
const updateAiSettings = vi.fn(() =>
  Promise.resolve({ data: { payload: {} } })
);

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getAiSettings: (...args) => getAiSettings(...args),
    getPipelines: (...args) => getPipelines(...args),
    getPipelineInboxes: (...args) => getPipelineInboxes(...args),
    updateAiSettings: (...args) => updateAiSettings(...args),
  },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { pipelineId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: () => {} }));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useMapGetter: () => ref([{ id: 7, name: 'Maria' }]),
}));

const mountPage = (handoff = {}) => {
  getAiSettings.mockResolvedValue({
    data: { payload: { handoff, stages: [] } },
  });
  return mount(CrmHandoffEditPage, {
    global: {
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        Breadcrumb: true,
        Button: true,
        HandoffRuleFields: true,
      },
    },
  });
};

describe('CrmHandoffEditPage handoff fields', () => {
  beforeEach(() => {
    getAiSettings.mockReset();
    updateAiSettings.mockClear();
  });

  it('hydrates the pool + escalation_action fields from the loaded payload', async () => {
    const wrapper = mountPage({
      enabled: true,
      handoff_mode: 'r3_invite',
      pool_type: 'user',
      pool_id: 7,
      escalation_action: 'escalate',
      escalation_user_id: 7,
    });
    await flushPromises();

    expect(wrapper.vm.defaultHandoff.pool_type).toBe('user');
    expect(wrapper.vm.defaultHandoff.pool_id).toBe(7);
    expect(wrapper.vm.defaultHandoff.escalation_action).toBe('escalate');
  });

  it('sends the pool + escalation_action fields in the save payload', async () => {
    const wrapper = mountPage({
      enabled: true,
      handoff_mode: 'r3_invite',
      pool_type: 'user',
      pool_id: 7,
      escalation_action: 'escalate',
      escalation_user_id: 7,
    });
    await flushPromises();

    await wrapper.vm.saveSettings();

    expect(updateAiSettings).toHaveBeenCalledTimes(1);
    const [, body] = updateAiSettings.mock.calls[0];
    expect(body.ai_settings.handoff.pool_type).toBe('user');
    expect(body.ai_settings.handoff.pool_id).toBe(7);
    expect(body.ai_settings.handoff.escalation_action).toBe('escalate');
    expect(body.ai_settings.handoff.handoff_mode).toBe('r3_invite');
  });

  it('preserves a legacy escalate config on round-trip (no silent downgrade)', async () => {
    const wrapper = mountPage({
      enabled: true,
      handoff_mode: 'r3_invite',
      pool_type: 'inbox',
      escalation_action: 'escalate',
      escalation_user_id: 7,
    });
    await flushPromises();

    await wrapper.vm.saveSettings();

    const [, body] = updateAiSettings.mock.calls[0];
    expect(body.ai_settings.handoff.escalation_action).toBe('escalate');
    expect(body.ai_settings.handoff.escalation_user_id).toBe(7);
  });
});
