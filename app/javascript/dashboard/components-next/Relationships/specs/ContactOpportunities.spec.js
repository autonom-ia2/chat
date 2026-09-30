import { mount } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import ContactOpportunities from '../ContactOpportunities.vue';

const accountLocale = ref('pt_BR');
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: accountLocale }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));
const row = {
  id: 7,
  title: 'Renewal',
  status: 'open',
  value_cents: 125050,
  currency: 'BRL',
  pipeline: { id: 1, name: 'Commercial' },
  stage: { id: 2, name: 'Proposal' },
  owner: { id: 3, name: 'Person' },
};
const RouterLink = {
  props: ['to'],
  template: '<a :data-destination="JSON.stringify(to)"><slot /></a>',
};
let wrapper;
let list;
beforeEach(() => {
  accountLocale.value = 'pt_BR';
  list = reactive({
    state: {
      items: [row],
      total: 7,
      page: 1,
      hasMore: true,
      result: 'active',
      query: '',
      failed: false,
      loaded: true,
    },
    loading: false,
    load: vi.fn(),
    apply: vi.fn(),
    setResult: vi.fn(),
    setQuery: vi.fn(),
  });
});
afterEach(() => wrapper?.unmount());
const render = () => {
  wrapper = mount(ContactOpportunities, {
    props: { list },
    global: { stubs: { RouterLink } },
  });
};

it('shows the canonical title, pipeline, stage, status, owner and currency without a summed total', () => {
  render();
  ['Renewal', 'Commercial', 'Proposal', 'Person', '1.250,50'].forEach(text =>
    expect(wrapper.text()).toContain(text)
  );
  expect(wrapper.findAll('[data-contact-opportunity]')).toHaveLength(1);
  expect(wrapper.findAll('select')).toHaveLength(0);
});
it('opens the exact existing card in a separate tab without writing anything', () => {
  render();
  const link = wrapper.find('[data-contact-opportunity]');
  expect(JSON.parse(link.attributes('data-destination'))).toEqual({
    name: 'crm_kanban_index',
    params: { accountId: 1 },
    query: { card_id: '7' },
  });
  expect(link.attributes('target')).toBe('_blank');
  expect(link.attributes('rel')).toBe('noopener noreferrer');
});
it('renders forecast dates using the actual pt_BR account locale without losing the rows', () => {
  list.state.items = [
    { ...row, expected_close_at: '2026-11-15T00:00:00.000Z' },
  ];
  render();
  expect(wrapper.text()).toContain('15/11/2026');
  expect(wrapper.findAll('[data-contact-opportunity]')).toHaveLength(1);
});

it('retains zero and the stated currency instead of a blank placeholder', () => {
  list.state.items = [{ ...row, value_cents: 0, currency: 'USD' }];
  render();
  expect(wrapper.text()).toContain('0,00');
});
it('does not crash or invent an exchange rate for an unsupported legacy currency string', () => {
  list.state.items = [{ ...row, currency: 'Legacy unit' }];
  render();
  expect(wrapper.text()).toContain('Legacy unit');
});
it('shows a real empty response without misrepresenting hidden opportunities', () => {
  list.state.items = [];
  list.state.total = 0;
  list.state.hasMore = false;
  render();
  expect(wrapper.find('[data-opportunities-empty]').exists()).toBe(true);
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});
it('distinguishes loading and errors from empty results and hides old totals', async () => {
  list.loading = true;
  render();
  expect(wrapper.find('[data-opportunities-empty]').exists()).toBe(false);
  expect(wrapper.findAll('[data-contact-opportunity]')).toHaveLength(0);
  list.loading = false;
  list.state.failed = true;
  await wrapper.vm.$nextTick();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.find('[data-opportunities-empty]').exists()).toBe(false);
  await wrapper.find('[role="alert"] button').trigger('click');
  expect(list.load).toHaveBeenCalledTimes(1);
});
it('submits the search explicitly and exposes server pagination controls', async () => {
  render();
  await wrapper.find('form').trigger('submit');
  expect(list.apply).toHaveBeenCalledTimes(1);
  const buttons = wrapper.find('nav').findAll('button');
  expect(buttons[0].attributes('disabled')).toBeDefined();
  await buttons[1].trigger('click');
  expect(list.load).toHaveBeenCalledWith(2);
});
it('shows unassigned owners and long titles as text, never executable markup', () => {
  list.state.items = [
    { ...row, owner: null, title: '<img src=x onerror=alert(1)> A long title' },
  ];
  render();
  expect(wrapper.text()).toContain('NO_OWNER');
  expect(wrapper.find('[data-contact-opportunity] img').exists()).toBe(false);
  expect(wrapper.text()).toContain('<img src=x');
});
