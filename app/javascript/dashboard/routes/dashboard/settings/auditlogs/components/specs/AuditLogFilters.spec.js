import { mount, shallowMount } from '@vue/test-utils';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import AuditLogFilters from '../AuditLogFilters.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) =>
      key === 'AUDIT_LOGS.FILTERS.AGENT_BY_ID' ? `AI agent #${params.id}` : key,
  }),
}));

const mountComponent = (props = {}, mountFn = shallowMount) =>
  mountFn(AuditLogFilters, {
    props,
    global: {
      directives: { 'on-click-outside': {}, 'on-clickaway': {} },
    },
  });

const openMenu = async (wrapper, index) => {
  await wrapper.findAllComponents(Button).at(index).trigger('click');
  return wrapper.findComponent(DropdownMenu);
};

describe('AuditLogFilters', () => {
  it('labels each menu with the active option', () => {
    const labels = mountComponent({ type: 'Inbox', sort: 'asc' }, mount)
      .findAllComponents(Button)
      .map(button => button.text());

    expect(labels).toEqual([
      'AUDIT_LOGS.FILTERS.DATE_RANGE',
      'AUDIT_LOGS.FILTERS.EVENT_TYPES.INBOXES',
      'AUDIT_LOGS.FILTERS.SORT.OLDEST',
      'AUDIT_LOGS.FILTERS.ALL_AGENTS',
      'AUDIT_LOGS.FILTERS.ALL_OPERATIONS',
    ]);
  });

  it('falls back to the all-records label when unfiltered', () => {
    const labels = mountComponent({}, mount)
      .findAllComponents(Button)
      .map(button => button.text());

    expect(labels).toEqual([
      'AUDIT_LOGS.FILTERS.DATE_RANGE',
      'AUDIT_LOGS.FILTERS.ALL_EVENTS',
      'AUDIT_LOGS.FILTERS.SORT.NEWEST',
      'AUDIT_LOGS.FILTERS.ALL_AGENTS',
      'AUDIT_LOGS.FILTERS.ALL_OPERATIONS',
    ]);
  });

  it('falls back to all events when the type is not recognised', () => {
    const wrapper = mountComponent({ type: 'Bogus' }, mount);

    expect(wrapper.findAllComponents(Button).at(1).text()).toBe(
      'AUDIT_LOGS.FILTERS.ALL_EVENTS'
    );
  });

  it('groups event types into sections', async () => {
    const wrapper = mountComponent();
    const menu = await openMenu(wrapper, 1);

    expect(menu.props('menuSections').map(section => section.title)).toEqual([
      undefined,
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.ACCESS',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.AGENTS_TEAMS',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.CONFIGURATION',
      'AUDIT_LOGS.FILTERS.EVENT_TYPE_GROUPS.CONVERSATIONS',
    ]);
  });

  it('emits an undefined value when the all-records option is picked', async () => {
    const wrapper = mountComponent({ type: 'Inbox' });
    const menu = await openMenu(wrapper, 1);
    menu.vm.$emit('action', { action: 'type', value: undefined });

    expect(wrapper.emitted('update')).toEqual([[{ type: undefined }]]);
  });

  it('closes an open menu when the calendar is revealed', async () => {
    const wrapper = mountComponent();
    await openMenu(wrapper, 1);
    await wrapper.findAllComponents(Button).at(0).trigger('click');

    expect(wrapper.findComponent(WootDatePicker).exists()).toBe(true);
    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  });

  it('closes an open menu when the calendar is reopened', async () => {
    const wrapper = mountComponent({ since: 100, until: 200 });
    await openMenu(wrapper, 1);
    await wrapper.findComponent(WootDatePicker).trigger('click');

    expect(wrapper.findComponent(DropdownMenu).exists()).toBe(false);
  });

  it('keeps a single menu open at a time', async () => {
    const wrapper = mountComponent();
    await openMenu(wrapper, 1);
    await openMenu(wrapper, 2);

    expect(wrapper.findAllComponents(DropdownMenu)).toHaveLength(1);
  });

  it('offers exact agent and operation filters without a native select', async () => {
    const wrapper = mountComponent(
      {
        agentId: 7,
        operationKey: 'voice_reply',
        agents: [{ id: 7, name: 'Agent 7' }],
      },
      mount
    );
    const buttons = wrapper.findAllComponents(Button);

    expect(buttons.at(3).text()).toBe('Agent 7');
    expect(buttons.at(4).text()).toBe('AUDIT_LOGS.OPERATION_KEYS.VOICE_REPLY');

    await buttons.at(3).trigger('click');
    expect(
      wrapper.findComponent(DropdownMenu).props('menuSections')[0].items
    ).toEqual([
      {
        label: 'AUDIT_LOGS.FILTERS.ALL_AGENTS',
        action: 'agent_id',
        isSelected: false,
      },
      {
        label: 'Agent 7',
        value: 7,
        action: 'agent_id',
        isSelected: true,
      },
    ]);
  });

  it('keeps an active agent filter visible when its catalog entry is unavailable', async () => {
    const wrapper = mountComponent({ agentId: 42 }, mount);
    const buttons = wrapper.findAllComponents(Button);

    expect(buttons.at(3).text()).toBe('AI agent #42');

    await buttons.at(3).trigger('click');
    expect(
      wrapper.findComponent(DropdownMenu).props('menuSections')[0].items
    ).toEqual([
      {
        label: 'AUDIT_LOGS.FILTERS.ALL_AGENTS',
        action: 'agent_id',
        isSelected: false,
      },
      {
        label: 'AI agent #42',
        value: 42,
        action: 'agent_id',
        isSelected: true,
      },
    ]);

    wrapper.findComponent(DropdownMenu).vm.$emit('action', {
      action: 'agent_id',
      value: undefined,
    });
    expect(wrapper.emitted('update')).toEqual([[{ agent_id: undefined }]]);
  });

  it('prefers the catalog name when the active agent becomes available', async () => {
    const wrapper = mountComponent({ agentId: 42 }, mount);

    await wrapper.setProps({ agents: [{ id: 42, name: 'Clara' }] });

    expect(wrapper.findAllComponents(Button).at(3).text()).toBe('Clara');
  });

  it('opens the calendar without applying a window', async () => {
    const wrapper = mountComponent();
    await wrapper.findAllComponents(Button).at(0).trigger('click');
    const picker = wrapper.findComponent(WootDatePicker);

    expect(picker.props('hasAppliedRange')).toBe(false);
    expect(wrapper.emitted('update')).toBeUndefined();
  });

  it('swaps the date button for the calendar once a window is applied', () => {
    expect(mountComponent().findComponent(WootDatePicker).exists()).toBe(false);

    const wrapper = mountComponent(
      { range: 'last30days', since: 100, until: 200 },
      mount
    );
    const picker = wrapper.findComponent(WootDatePicker);

    expect(picker.props('rangeType')).toBe('last30days');
    expect(picker.props('dateRange')).toEqual([
      new Date(100000),
      new Date(200000),
    ]);
    expect(wrapper.findAllComponents(Button).at(0).text()).toBe(
      'AUDIT_LOGS.FILTERS.ALL_EVENTS'
    );
  });

  it('widens the window picked in the calendar to whole days', () => {
    const wrapper = mountComponent({ since: 100, until: 200 });
    wrapper
      .findComponent(WootDatePicker)
      .vm.$emit('dateRangeChanged', [
        new Date(2026, 7, 3, 13, 4, 5),
        new Date(2026, 7, 12),
        'custom',
      ]);

    const [[payload]] = wrapper.emitted('update');
    expect(payload.range).toBe('custom');
    expect(new Date(payload.since * 1000)).toEqual(new Date(2026, 7, 3));
    expect(new Date(payload.until * 1000)).toEqual(
      new Date(2026, 7, 12, 23, 59, 59)
    );
  });
});
