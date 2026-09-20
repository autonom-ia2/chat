import { mount } from '@vue/test-utils';
import { ref, computed } from 'vue';
import SingleIntegrationHooks from '../SingleIntegrationHooks.vue';

const integration = ref({});

vi.mock('dashboard/composables/useIntegrationHook', () => ({
  useIntegrationHook: () => ({
    integration,
    hasConnectedHooks: computed(() => Boolean(integration.value.hooks?.length)),
  }),
}));

vi.mock('shared/composables/useBranding', () => ({
  useBranding: () => ({ replaceInstallationName: text => text }),
}));

const mountWith = hooks => {
  integration.value = {
    name: 'CRM Kanban IA',
    description: 'Chave da OpenAI para o CRM',
    hooks,
  };
  return mount(SingleIntegrationHooks, {
    props: { integrationId: 'crm_kanban_ai' },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: { props: ['label'], template: '<button>{{ label }}</button>' },
      },
    },
  });
};

describe('SingleIntegrationHooks', () => {
  it('says the integration is connected and working', () => {
    const wrapper = mountWith([{ id: 1, status: true, settings: {} }]);

    expect(wrapper.text()).toContain('INTEGRATION_APPS.STATUS.ACTIVE');
    expect(wrapper.text()).not.toContain('INTEGRATION_APPS.STATUS.INACTIVE');
  });

  it('warns when the key is connected but the AI is off', () => {
    const wrapper = mountWith([
      { id: 1, status: true, settings: { enabled: false } },
    ]);

    expect(wrapper.text()).toContain('INTEGRATION_APPS.STATUS.INACTIVE');
  });

  it('warns when the hook itself is disabled', () => {
    const wrapper = mountWith([{ id: 1, status: false, settings: {} }]);

    expect(wrapper.text()).toContain('INTEGRATION_APPS.STATUS.INACTIVE');
  });

  it('shows no status before connecting', () => {
    const wrapper = mountWith([]);

    expect(wrapper.text()).not.toContain('INTEGRATION_APPS.STATUS');
  });
});
