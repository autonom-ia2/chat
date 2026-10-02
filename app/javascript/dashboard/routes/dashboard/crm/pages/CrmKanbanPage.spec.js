import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import CrmKanbanPage from './CrmKanbanPage.vue';

// The page is a large orchestrator. These specs pin three review findings:
// the Agenda keeps its admin actions, drag is gated by permission, and the
// keyboard "Move" path lands focus inside the picker.

const route = { meta: {}, query: {}, params: {} };
const permissions = {};
const storeGetters = {};
const dispatch = vi.fn();

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
    locale: { value: 'en' },
  }),
}));

vi.mock('vue-router', () => ({
  useRoute: () => route,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: (...args) => dispatch(...args),
    getters: { 'globalConfig/get': {} },
  }),
  useMapGetter: key => storeGetters[key] || ref(undefined),
  useStoreGetters: () => ({}),
}));

vi.mock('../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => permissions,
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('dashboard/api/crmMeetings', () => ({ default: {} }));
vi.mock('dashboard/api/ctwaCampaigns', () => ({
  default: { get: vi.fn(() => Promise.resolve({ data: [] })) },
}));
vi.mock('dashboard/api/companies', () => ({
  default: {
    search: vi.fn(() => Promise.resolve({ data: { payload: [] } })),
    show: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));
vi.mock('dashboard/api/metaConversions', () => ({
  default: { getForCards: vi.fn(() => Promise.resolve({ data: {} })) },
}));

// Renders every card through the item slot and exposes the disabled flag, so
// the drag permission can be asserted without Sortable in jsdom.
const DraggableStub = {
  name: 'Draggable',
  props: {
    modelValue: { type: Array, default: () => [] },
    disabled: { type: Boolean, default: false },
  },
  template: `
    <div data-test-draggable :data-disabled="String(disabled)">
      <template v-for="element in modelValue" :key="element.id">
        <slot name="item" :element="element" />
      </template>
      <slot name="footer" />
    </div>
  `,
};

const PIPELINE = { id: 1, name: 'Vendas' };
const STAGES = [
  {
    id: 10,
    name: 'Novo',
    color: '#2563eb',
    cards: [{ id: 100, title: 'Acme deal', company: { name: 'Acme' } }],
  },
  {
    id: 11,
    name: 'Proposta',
    color: '#22c55e',
    cards: [{ id: 101, title: 'Beta deal', company: { name: 'Beta' } }],
  },
];

const setPermissions = overrides => {
  Object.assign(permissions, {
    canManageCards: ref(true),
    canViewCrm: ref(true),
    canMoveCards: ref(true),
    canManagePipelines: ref(true),
    canManageAi: ref(true),
    canExportCrm: ref(false),
    ...Object.fromEntries(
      Object.entries(overrides).map(([key, value]) => [key, ref(value)])
    ),
  });
};

const setGetters = () => {
  Object.assign(storeGetters, {
    'crmKanban/getPipelines': ref([PIPELINE]),
    'crmKanban/getStages': ref(
      STAGES.map(s => ({ ...s, cards: [...s.cards] }))
    ),
    'crmKanban/getCardsList': ref([]),
    'crmKanban/getCardsListMeta': ref({}),
    'crmKanban/getFollowUps': ref([]),
    'crmKanban/getCalendarEvents': ref([]),
    'crmKanban/getUIFlags': ref({}),
    'crmKanban/getFilters': ref({}),
    'crmKanban/getListPrefs': ref({}),
    'crmKanban/getListSort': ref({}),
    'crmKanban/getListGroupBy': ref(''),
    'crmKanban/getListSelection': ref([]),
    'crmKanban/getSavedViews': ref([]),
    getCurrentUser: ref({ id: 1 }),
    getCurrentAccountId: ref(1),
    'inboxes/getInboxes': ref([]),
    'agents/getAgents': ref([]),
    'teams/getTeams': ref([]),
    'labels/getLabels': ref([]),
  });
};

const mountPage = async ({
  calendarOnly = false,
  perms = {},
  stubs = {},
} = {}) => {
  route.meta = calendarOnly ? { calendarOnly: true } : {};
  setPermissions(perms);
  setGetters();
  const wrapper = mount(CrmKanbanPage, {
    attachTo: document.body,
    global: {
      stubs: {
        Draggable: DraggableStub,
        Spinner: true,
        ConfirmModal: true,
        CrmCardDrawer: true,
        CrmKanbanFiltersDrawer: true,
        CrmOpportunityFromContact: true,
        CrmPipelineDrawer: true,
        CrmInboxSettingsDrawer: true,
        CrmBookingProfilesDrawer: true,
        CrmCardsTable: true,
        CrmListExportButton: true,
        CrmTableColumnSettings: true,
        CrmSavedViews: true,
        CrmResultTabs: true,
        CrmBulkActionBar: true,
        CrmCalendar: true,
        CrmCalendarQuickAdd: true,
        CrmCalendarMeetingScheduler: true,
        CrmMeetingDetail: true,
        ChannelIcon: true,
        CardPriorityIcon: true,
        CardLabels: true,
        SLACardLabel: true,
        CrmCardPill: true,
        ...stubs,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

const openConfiguration = async wrapper => {
  const trigger = wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.ACTIONS.CONFIGURE');
  expect(trigger).toBeDefined();
  await trigger.trigger('click');
  await flushPromises();
  return document.body.textContent;
};

describe('CrmKanbanPage', () => {
  let wrapper;

  beforeEach(() => {
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    dispatch.mockImplementation(async type =>
      type === 'crmKanban/fetchPipelines' ? [PIPELINE] : []
    );
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    document.body.innerHTML = '';
    delete window.globalConfig;
  });

  it('keeps booking page and inbox settings in the Agenda, without funnel actions', async () => {
    wrapper = await mountPage({ calendarOnly: true });

    const text = await openConfiguration(wrapper);

    expect(text).toContain('CRM_KANBAN.BOOKING.ADMIN.ACTION');
    expect(text).toContain('CRM_KANBAN.ACTIONS.INBOX_SETTINGS');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.EDIT_PIPELINE');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS');
  });

  it('opens the booking profiles drawer from the Agenda', async () => {
    wrapper = await mountPage({ calendarOnly: true });
    await openConfiguration(wrapper);

    const booking = Array.from(document.body.querySelectorAll('button')).find(
      button => button.textContent.trim() === 'CRM_KANBAN.BOOKING.ADMIN.ACTION'
    );
    booking.click();
    await flushPromises();

    expect(
      wrapper.findComponent({ name: 'CrmBookingProfilesDrawer' }).props('show')
    ).toBe(true);
  });

  it('shows funnel actions on the Kanban configuration menu', async () => {
    wrapper = await mountPage();

    const text = await openConfiguration(wrapper);

    expect(text).toContain('CRM_KANBAN.ACTIONS.EDIT_PIPELINE');
    expect(text).toContain('CRM_KANBAN.ACTIONS.INBOX_SETTINGS');
  });

  it('disables drag and hides Move without the move permission', async () => {
    wrapper = await mountPage({ perms: { canMoveCards: false } });

    const boards = wrapper.findAll('[data-test-draggable]');
    expect(boards.length).toBe(STAGES.length);
    boards.forEach(board => {
      expect(board.attributes('data-disabled')).toBe('true');
    });
    expect(wrapper.find('[data-crm-card-move]').exists()).toBe(false);
  });

  it('enables drag with the move permission', async () => {
    wrapper = await mountPage();

    wrapper.findAll('[data-test-draggable]').forEach(board => {
      expect(board.attributes('data-disabled')).toBe('false');
    });
  });

  it('moves focus into the stage picker when Move opens and back when it closes', async () => {
    wrapper = await mountPage();
    const move = wrapper.find('[data-crm-card-move]');
    move.element.focus();

    await move.trigger('click');
    await flushPromises();

    const combobox = document.body.querySelector(
      '[data-popover-content] [role="combobox"]'
    );
    expect(combobox).not.toBeNull();
    expect(document.activeElement).toBe(combobox);

    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    await flushPromises();

    expect(
      document.body.querySelector('[data-popover-content] [role="combobox"]')
    ).toBeNull();
    expect(document.activeElement).toBe(move.element);
  });
  it('confirms the open card drafts before switching to another card', async () => {
    const guardNavigation = vi.fn(action => action());
    dispatch.mockImplementation(async (type, payload) => {
      if (type === 'crmKanban/fetchPipelines') return [PIPELINE];
      if (type === 'crmKanban/fetchCard') return { id: payload };
      return [];
    });
    const DrawerStub = defineComponent({
      setup(_, { expose }) {
        expose({ guardNavigation });
        return () => h('div');
      },
    });
    wrapper = await mountPage({ stubs: { CrmCardDrawer: DrawerStub } });
    const openButtons = () =>
      wrapper
        .findAll('button')
        .filter(button =>
          (button.attributes('aria-label') || '').startsWith(
            'CRM_KANBAN.CARD.OPEN_DETAILS'
          )
        );
    expect(openButtons()).toHaveLength(2);

    await openButtons()[0].trigger('click');
    await flushPromises();
    await openButtons()[0].trigger('click');
    await flushPromises();
    expect(guardNavigation).not.toHaveBeenCalled();

    await openButtons()[1].trigger('click');
    await flushPromises();
    expect(guardNavigation).toHaveBeenCalledWith(expect.any(Function), {
      leaving: true,
    });
  });
});
