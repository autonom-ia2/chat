import { flushPromises, mount } from '@vue/test-utils';
import { defineComponent, h, ref } from 'vue';
import CrmKanbanPage from './CrmKanbanPage.vue';
import CrmKanbanZoom from '../components/CrmKanbanZoom.vue';
import {
  KANBAN_ZOOM_CLASSES,
  KANBAN_ZOOM_DRAG_CLASSES,
} from '../helpers/kanbanZoom';

// The page is a large orchestrator. These specs pin three review findings:
// the Agenda keeps its admin actions, drag is gated by permission, and the
// stage changes stay available inside the card details.

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
    'accounts/isRTL': ref(false),
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

  it('keeps inbox settings in the Agenda, without funnel actions', async () => {
    wrapper = await mountPage({ calendarOnly: true });

    const text = await openConfiguration(wrapper);

    expect(text).toContain('CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT');
    expect(text).toContain('CRM_KANBAN.ACTIONS.INBOX_SETTINGS');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.EDIT_PIPELINE');
    expect(text).not.toContain('CRM_KANBAN.ACTIONS.HANDOFF_SETTINGS');
  });

  it('opens the booking profiles drawer from the Agenda', async () => {
    wrapper = await mountPage({ calendarOnly: true });
    await openConfiguration(wrapper);

    const booking = Array.from(document.body.querySelectorAll('button')).find(
      button =>
        button.textContent.trim() === 'CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT'
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

    expect(text).not.toContain('CRM_KANBAN.BOOKING.ADMIN.ACTION_SHORT');
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

// The drawer uses the existing move endpoint, separate from commercial edits.
it('moves the selected card from details without overwriting its title', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10, title: 'Current title' };
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).toHaveBeenCalledWith('crmKanban/moveCard', {
    cardId: 100,
    stageId: 11,
  });
  expect(wrapper.vm.selectedCard).toMatchObject({
    stage_id: 11,
    title: 'Current title',
  });
  wrapper.unmount();
});

it('does not move from details without movement permission', async () => {
  const wrapper = await mountPage({ perms: { canMoveCards: false } });
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  dispatch.mockClear();
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).not.toHaveBeenCalledWith(
    'crmKanban/moveCard',
    expect.anything()
  );
  wrapper.unmount();
});

it('keeps the current stage when the move request fails', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  dispatch.mockRejectedValueOnce(new Error('Move failed'));
  await wrapper.vm.moveCardFromDetails(11);
  expect(wrapper.vm.selectedCard.stage_id).toBe(10);
  wrapper.unmount();
});

it('loads all authorized stages for card details independently of board filters', async () => {
  const wrapper = await mountPage({ calendarOnly: true });
  dispatch.mockImplementation(async (type, payload) => {
    if (type === 'crmKanban/fetchCard')
      return { id: payload, pipeline_id: 1, stage_id: 10 };
    if (type === 'crmKanban/fetchPipelineStages') return STAGES;
    return [];
  });
  storeGetters['crmKanban/getStages'].value = [];
  await wrapper.vm.openCardDrawer({ id: 100 });
  expect(dispatch).toHaveBeenCalledWith('crmKanban/fetchPipelineStages', 1);
  expect(
    wrapper.findComponent({ name: 'CrmCardDrawer' }).attributes('stages')
  ).toBeTruthy();
  expect(wrapper.vm.cardDrawerStages).toEqual(STAGES);
  wrapper.unmount();
});

it('does not start another move while a card is moving', async () => {
  const wrapper = await mountPage();
  wrapper.vm.selectedCard = { id: 100, stage_id: 10 };
  storeGetters['crmKanban/getUIFlags'].value = { isMovingCard: true };
  dispatch.mockClear();
  await wrapper.vm.moveCardFromDetails(11);
  expect(dispatch).not.toHaveBeenCalledWith(
    'crmKanban/moveCard',
    expect.anything()
  );
  wrapper.unmount();
});

describe('Kanban zoom integration', () => {
  let wrapper;
  beforeEach(() => {
    localStorage.clear();
    window.globalConfig = { CRM_CALENDAR_MEETINGS_ENABLED: 'true' };
    dispatch.mockImplementation(async type =>
      type === 'crmKanban/fetchPipelines' ? [PIPELINE] : []
    );
  });
  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
    document.body.innerHTML = '';
    localStorage.clear();
    delete window.globalConfig;
  });

  it.each([70, 80, 87, 90, 100, 110, 117, 120, 130])(
    'scales only the board at %i without rebuilding cards or refetching data',
    async value => {
      wrapper = await mountPage();
      const board = wrapper.get('[data-kanban-board]').element;
      const column = wrapper.get('[data-stage-id="10"]').element;
      const header = wrapper.get('main > header').element;
      dispatch.mockClear();
      wrapper.findComponent(CrmKanbanZoom).vm.$emit('update:modelValue', value);
      await flushPromises();
      expect(wrapper.get('[data-kanban-board]').classes()).toContain(
        KANBAN_ZOOM_CLASSES[value]
      );
      expect(wrapper.get('[data-kanban-board]').element).toBe(board);
      expect(wrapper.get('[data-stage-id="10"]').element).toBe(column);
      expect(wrapper.get('main > header').element).toBe(header);
      expect(header.className).not.toContain('[zoom:');
      expect(wrapper.get('main').classes()).toContain('w-full');
      expect(wrapper.get('[data-card-id]').classes()).toContain(
        KANBAN_ZOOM_DRAG_CLASSES[value]
      );
      expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(
        value
      );
      expect(dispatch).not.toHaveBeenCalled();
      wrapper.findAll('[data-test-draggable]').forEach(list => {
        expect(list.attributes('sort')).toBe('false');
        expect(list.attributes('fallback-on-body')).toBe('true');
        expect(list.attributes('force-fallback')).toBe('true');
        expect(list.attributes('fallback-tolerance')).toBe('4');
        expect(list.attributes('scroll')).toBe('false');
        expect(list.attributes('fallback-class')).toBe(
          'crm-kanban-drag-preview'
        );
      });
      wrapper.vm.onDragStart();
      await wrapper.vm.onDragChange(STAGES[1], {
        added: { element: STAGES[0].cards[0] },
      });
      expect(dispatch).toHaveBeenCalledWith('crmKanban/moveCard', {
        cardId: 100,
        stageId: 11,
      });
    }
  );

  it.each(['list', 'calendar'])(
    'keeps the exact preference through %s without scaling it',
    async mode => {
      wrapper = await mountPage();
      wrapper.vm.setZoom(87);
      wrapper.vm.setViewMode(mode);
      await flushPromises();
      expect(wrapper.findComponent(CrmKanbanZoom).exists()).toBe(false);
      expect(wrapper.find('[data-kanban-board]').exists()).toBe(false);
      expect(
        wrapper
          .findAll('[class]')
          .some(node => node.attributes('class').includes('[zoom:'))
      ).toBe(false);
      wrapper.vm.setViewMode('kanban');
      await flushPromises();
      expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(87);
    }
  );

  it('restores the exact percentage after leaving and mounting the CRM again', async () => {
    wrapper = await mountPage();
    wrapper.vm.setZoom(87);
    wrapper.unmount();
    wrapper = await mountPage();
    expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(87);
  });

  it('preserves the account direction on cards cloned outside the app', async () => {
    wrapper = await mountPage();
    expect(wrapper.get('[data-card-id]').attributes('dir')).toBe('ltr');
    storeGetters['accounts/isRTL'].value = true;
    await flushPromises();
    expect(wrapper.get('[data-card-id]').attributes('dir')).toBe('rtl');
  });

  it('suppresses the trailing click after dragging, not a fresh pointer click', async () => {
    wrapper = await mountPage();
    const target = wrapper.get('[data-card-id]').element;
    const clicked = vi.fn();
    target.addEventListener('click', clicked);
    wrapper.vm.onDragStart();
    const trailing = new MouseEvent('click', {
      bubbles: true,
      cancelable: true,
      detail: 1,
    });
    target.dispatchEvent(trailing);
    expect(trailing.defaultPrevented).toBe(true);
    expect(clicked).not.toHaveBeenCalled();
    target.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 1 }));
    expect(clicked).toHaveBeenCalledOnce();
  });

  it('preserves keyboard activation after an abandoned drag', async () => {
    wrapper = await mountPage();
    const target = wrapper.get('[data-card-id]').element;
    const clicked = vi.fn();
    target.addEventListener('click', clicked);
    wrapper.vm.onDragStart();
    target.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 0 }));
    expect(clicked).toHaveBeenCalledOnce();
  });

  it('keeps zoom across funnels and never exposes the control on the Agenda-only route', async () => {
    wrapper = await mountPage();
    wrapper.vm.setZoom(83);
    storeGetters['crmKanban/getPipelines'].value = [
      PIPELINE,
      { id: 2, name: 'Outro funil' },
    ];
    wrapper.vm.currentPipelineId = 2;
    await flushPromises();
    expect(wrapper.findComponent(CrmKanbanZoom).props('modelValue')).toBe(83);
    wrapper.unmount();
    wrapper = await mountPage({ calendarOnly: true });
    expect(wrapper.findComponent(CrmKanbanZoom).exists()).toBe(false);
  });
});
