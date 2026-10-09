import { flushPromises, mount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import Index from '../Index.vue';

const humanAgents = ref([{ id: 7, name: 'Humano 7' }]);
const autonomiaAgents = ref([{ id: 42, name: 'IA 42' }]);
const accountEnabled = ref(true);
const records = ref([]);
const dispatch = vi.fn(() => Promise.resolve());

const rawSecret = 'do-not-render-this-secret';

const autonomiaAuditLog = () => ({
  id: 1,
  auditable_type: 'Autonomia::Agents::Agent',
  action: 'update',
  user_id: 7,
  actor: { type: 'User', id: 7, name: 'Humano 7' },
  auditable_id: 42,
  operation_keys: ['voice_reply', 'test_allowlist_phones'],
  audited_changes: {
    operation_config: {
      voice_reply: { old: true, new: false },
      test_allowlist_phones: {
        old: ['+551••••00'],
        new: ['+551••••11', '+551••••22', '+551••••33', '+551••••44'],
      },
      secret_key: { old: rawSecret, new: rawSecret },
    },
  },
  created_at: 1_728_000_000,
  location: 'local',
});

const translate = (key, params = {}) => {
  const labels = {
    'AUDIT_LOGS.OPERATION_KEYS.MULTIPLE': 'multiple settings',
    'AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY': 'voice replies',
    'AUDIT_LOGS.OPERATION_KEYS.TEST_ALLOWLIST_PHONES': 'test phone allowlist',
    'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.ON': 'on',
    'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.OFF': 'off',
  };

  if (key === 'AUDIT_LOGS.AUTONOMIA_AGENT.EDIT') {
    return `${params.actor} updated ${params.operationKey} for AI agent (#${params.id})`;
  }
  if (key === 'AUDIT_LOGS.AUTONOMIA_AGENT.CHANGE') {
    return `${params.label}: ${params.before} -> ${params.after}`;
  }
  if (key === 'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.MASKED_LIST') {
    return params.preview;
  }
  if (key === 'AUDIT_LOGS.AUTONOMIA_AGENT.VALUES.MASKED_LIST_MORE') {
    return `${params.preview} and ${params.remaining} more`;
  }

  return labels[key] || key;
};

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: translate }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'auditlogs_list', query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

vi.mock('shared/helpers/timeHelper', () => ({
  messageTimestamp: () => 'Oct 07, 2026 10:00 AM',
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useStoreGetters: () => ({
    'auditlogs/getAuditLogs': computed(() => records.value),
    'auditlogs/getUIFlags': computed(() => ({ fetchingList: false })),
    'auditlogs/getMeta': computed(() => ({
      totalEntries: records.value.length,
      currentPage: 1,
      perPage: 25,
    })),
    'agents/getAgents': humanAgents,
    'autonomiaAgents/getRecords': autonomiaAgents,
    'accounts/isFeatureEnabledonAccount': computed(() => () => false),
    getCurrentAccountId: computed(() => 16),
  }),
  useMapGetter: key => {
    if (key === 'getCurrentAccountId') return computed(() => 16);
    if (key === 'globalConfig/get') {
      return computed(() => ({ autonomiaAgentsEnabled: true }));
    }
    if (key === 'accounts/getAccount') {
      return computed(() => () => ({
        autonomia_agents_enabled: accountEnabled.value,
      }));
    }
    return computed(() => undefined);
  },
}));

const mountPage = async () => {
  records.value = [autonomiaAuditLog()];
  const wrapper = mount(Index, {
    global: {
      mocks: { $t: translate },
      stubs: {
        SettingsLayout: {
          template: '<div><slot name="header" /><slot name="body" /></div>',
        },
        BaseSettingsHeader: {
          props: ['searchQuery'],
          template:
            '<div><slot name="tabs" /><slot name="count" /><slot name="actions" /></div>',
        },
        AuditLogFilters: {
          props: ['agents'],
          template: `
            <div data-testid="ai-filter">
              <span v-for="agent in agents" :key="agent.id">{{ agent.name }}</span>
            </div>
          `,
        },
        BaseTable: {
          props: ['items'],
          template:
            '<div data-testid="table"><slot name="row" :items="items" /></div>',
        },
        BaseTableRow: {
          template: '<div data-testid="row"><slot /></div>',
        },
        BaseTableCell: {
          template: '<div data-testid="cell"><slot /></div>',
        },
        PaginationFooter: { template: '<div data-testid="pagination" />' },
        Button: {
          props: ['label'],
          template: '<button>{{ label }}</button>',
        },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Audit log page Autonom.ia integration', () => {
  beforeEach(() => {
    accountEnabled.value = true;
    dispatch.mockClear();
  });

  it('uses the AI catalog for filters and renders masked typed changes', async () => {
    const wrapper = await mountPage();

    expect(dispatch.mock.calls.map(([action]) => action)).toEqual(
      expect.arrayContaining([
        'agents/get',
        'autonomiaAgents/get',
        'auditlogs/fetch',
      ])
    );
    expect(wrapper.get('[data-testid="ai-filter"]').text()).toContain('IA 42');
    expect(wrapper.get('[data-testid="ai-filter"]').text()).not.toContain(
      'Humano 7'
    );

    const rendered = wrapper.text();
    expect(rendered).toContain('multiple settings');
    expect(rendered).toContain('+551••••00');
    expect(rendered).toContain('+551••••11');
    expect(rendered).not.toContain(rawSecret);
    expect(rendered).not.toContain('secret_key');

    wrapper.unmount();
  });

  it('does not request or expose the AI catalog when the product gate is off', async () => {
    accountEnabled.value = false;
    const wrapper = await mountPage();

    expect(dispatch.mock.calls.map(([action]) => action)).not.toContain(
      'autonomiaAgents/get'
    );
    expect(wrapper.get('[data-testid="ai-filter"]').text()).not.toContain(
      'IA 42'
    );

    wrapper.unmount();
  });
});
