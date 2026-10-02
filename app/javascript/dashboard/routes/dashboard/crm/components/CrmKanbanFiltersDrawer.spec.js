import { flushPromises, mount } from '@vue/test-utils';
import { defaultFilters } from 'dashboard/store/modules/crmKanban';
import CrmKanbanFiltersDrawer from './CrmKanbanFiltersDrawer.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

const COMPANY_CHOICES = [
  { value: 'none', label: 'Sem empresa' },
  { value: 7, label: 'Acme' },
];
const CAMPAIGNS = [
  { value: '120000000000000001', label: 'Campanha Inverno' },
  { value: '120000000000000002', label: 'Campanha Verão' },
];

const baseProps = (overrides = {}) => ({
  show: false,
  filters: { ...defaultFilters(), stageIds: [], labelIds: [] },
  companyChoices: COMPANY_CHOICES,
  campaignFilterOptions: CAMPAIGNS,
  stageOptions: [
    { value: 10, label: 'Novo' },
    { value: 11, label: 'Proposta' },
  ],
  ...overrides,
});

// The draft is synced when the drawer opens (show: false → true), as in the page.
const mountOpen = async (overrides = {}) => {
  const wrapper = mount(CrmKanbanFiltersDrawer, {
    attachTo: document.body,
    props: baseProps(overrides),
  });
  await wrapper.setProps({ show: true });
  await flushPromises();
  return wrapper;
};

const buttonByText = (wrapper, text) =>
  wrapper.findAll('button').find(button => button.text() === text);

const buttonByAriaLabel = (wrapper, label) =>
  wrapper.find(`button[aria-label="${label}"]`);

const openSection = async (wrapper, titleKey) => {
  const section = wrapper
    .findAll('details')
    .find(details => details.find('summary').text().includes(titleKey));
  await section.find('summary').trigger('click');
};

const apply = async wrapper => {
  await buttonByText(wrapper, 'CRM_KANBAN.ACTIONS.VIEW_OPPORTUNITIES').trigger(
    'click'
  );
  return wrapper.emitted('apply')?.at(-1)?.[0];
};

const chooseCompany = async (wrapper, value) => {
  const combobox = wrapper.find(
    '[role="combobox"][aria-label="CRM_KANBAN.FILTERS.COMPANY"]'
  );
  await combobox.trigger('click');
  const listId = combobox.attributes('aria-controls');
  await wrapper
    .find(`[id="${listId}"] [role="option"][data-value="${value}"]`)
    .trigger('click');
};

describe('CrmKanbanFiltersDrawer', () => {
  let wrapper;

  // jsdom has no scrollIntoView; ChoiceSelect calls it when its list opens.
  beforeAll(() => {
    Element.prototype.scrollIntoView = () => {};
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('emits the draft on apply', async () => {
    wrapper = await mountOpen();

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.GROUP_OPPORTUNITY');
    await buttonByText(wrapper, 'Proposta').trigger('click');
    const applied = await apply(wrapper);

    expect(applied.stageIds).toEqual([11]);
  });

  it('does not leak a cancelled draft into the next opening', async () => {
    const filters = { ...defaultFilters(), stageIds: [], labelIds: [] };
    wrapper = await mountOpen({ filters });

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.GROUP_OPPORTUNITY');
    await buttonByText(wrapper, 'Novo').trigger('click');
    await buttonByAriaLabel(wrapper, 'CRM_KANBAN.ACTIONS.CLOSE').trigger(
      'click'
    );

    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('apply')).toBeUndefined();
    expect(filters.stageIds).toEqual([]);

    await wrapper.setProps({ show: false });
    await wrapper.setProps({ show: true });
    await flushPromises();
    const applied = await apply(wrapper);

    expect(applied.stageIds).toEqual([]);
  });

  it.each([
    ['101', '', 'CRM_KANBAN.FILTERS.SCORE_INVALID'],
    ['1.5', '', 'CRM_KANBAN.FILTERS.SCORE_INVALID'],
    ['80', '20', 'CRM_KANBAN.FILTERS.SCORE_ORDER_INVALID'],
  ])(
    'blocks apply for score min=%s max=%s',
    async (scoreMin, scoreMax, error) => {
      wrapper = await mountOpen({
        filters: { ...defaultFilters(), scoreMin, scoreMax },
      });

      expect(wrapper.find('[role="alert"]').text()).toBe(error);
      const applyButton = buttonByText(
        wrapper,
        'CRM_KANBAN.ACTIONS.VIEW_OPPORTUNITIES'
      );
      expect(applyButton.attributes('disabled')).toBeDefined();
      await applyButton.trigger('click');
      expect(wrapper.emitted('apply')).toBeUndefined();
    }
  );

  it('accepts a valid score range', async () => {
    wrapper = await mountOpen({
      filters: { ...defaultFilters(), scoreMin: '20', scoreMax: '80' },
    });

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    const applied = await apply(wrapper);
    expect(applied).toMatchObject({ scoreMin: '20', scoreMax: '80' });
  });

  it('applies "without company"', async () => {
    wrapper = await mountOpen();

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.COMPANY');
    await chooseCompany(wrapper, 'none');
    const applied = await apply(wrapper);

    expect(applied.companyId).toBe('none');
  });

  it('keeps the chosen company after a new search drops it from the results', async () => {
    wrapper = await mountOpen();

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.COMPANY');
    await chooseCompany(wrapper, '7');
    await wrapper.setProps({ companyChoices: [], companySearch: 'zzz' });
    const applied = await apply(wrapper);

    expect(applied.companyId).toBe(7);
    expect(wrapper.find('[role="option"][data-value="7"]').text()).toContain(
      'Acme'
    );
  });

  it('emits company searches and keeps the input enabled while searching', async () => {
    wrapper = await mountOpen();

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.COMPANY');
    const input = wrapper.find('input[type="text"], input:not([type])');
    await input.setValue('acm');
    expect(wrapper.emitted('search-company').at(-1)).toEqual(['acm']);

    await wrapper.setProps({ companyLoading: true, companySearch: 'acm' });

    expect(input.attributes('disabled')).toBeUndefined();
    expect(wrapper.text()).toContain('CRM_KANBAN.FILTERS.COMPANY_SEARCHING');
  });

  it('does not toggle a campaign when the Campaign title is clicked', async () => {
    wrapper = await mountOpen();

    await openSection(wrapper, 'CRM_KANBAN.FILTERS.GROUP_ATTENDANCE');
    const title = wrapper.find('#crm-kanban-filters-campaign-label');
    await title.trigger('click');

    const group = wrapper.find(
      '[role="group"][aria-labelledby="crm-kanban-filters-campaign-label"]'
    );
    expect(group.exists()).toBe(true);
    expect(title.element.closest('label')).toBeNull();
    group.findAll('button').forEach(button => {
      expect(button.attributes('aria-pressed')).toBe('false');
    });
    const applied = await apply(wrapper);
    expect(applied.campaignSourceIds).toEqual([]);
  });

  it('starts with the five filter sections collapsed', async () => {
    wrapper = await mountOpen();

    expect(wrapper.findAll('details')).toHaveLength(5);
    expect(wrapper.findAll('details[open]')).toHaveLength(0);
    expect(wrapper.text()).toContain('CRM_KANBAN.FILTERS.SHORTCUTS');
  });

  it('applies the owner and overdue shortcuts to the draft', async () => {
    wrapper = await mountOpen({ currentUserId: 42 });

    await buttonByText(wrapper, 'CRM_KANBAN.FILTERS.SHORTCUT_MINE').trigger(
      'click'
    );
    let applied = await apply(wrapper);
    expect(applied.ownerId).toBe(42);
    expect(applied.responsibleKind).toBe('');

    await buttonByText(wrapper, 'CRM_KANBAN.FILTERS.SHORTCUT_OVERDUE').trigger(
      'click'
    );
    applied = await apply(wrapper);
    expect(applied.followUpStatus).toBe('overdue');
  });
});
