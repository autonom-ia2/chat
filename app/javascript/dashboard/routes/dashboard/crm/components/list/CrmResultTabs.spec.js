import { mount } from '@vue/test-utils';
import { useI18n } from 'vue-i18n';
import CrmResultTabs from './CrmResultTabs.vue';

vi.mock('vue-i18n');

describe('CrmResultTabs', () => {
  beforeEach(() => {
    useI18n.mockReturnValue({ t: key => key });
  });

  const activeButton = wrapper =>
    wrapper
      .findAll('button')
      .find(btn => btn.attributes('aria-pressed') === 'true');

  it('renders the three everyday outcome tabs', () => {
    const wrapper = mount(CrmResultTabs, { props: { modelValue: 'open' } });
    expect(wrapper.findAll('button')).toHaveLength(3);
  });

  it('marks the matching tab as active', () => {
    const wrapper = mount(CrmResultTabs, { props: { modelValue: 'won' } });
    expect(activeButton(wrapper).text()).toBe('CRM_KANBAN.DRAWER.STATUS_WON');
  });

  it('keeps the outcome tab active for a status from the previous funnel kind (#1197)', () => {
    const wrapper = mount(CrmResultTabs, {
      props: { modelValue: 'won', pipeline: { counts_as_sale: false } },
    });
    expect(activeButton(wrapper).attributes('data-value')).toBe('resolved');
  });

  it('marks no tab active when result is empty ("Todos")', () => {
    const wrapper = mount(CrmResultTabs, { props: { modelValue: '' } });
    expect(activeButton(wrapper)).toBeUndefined();
  });

  it('emits update:modelValue with the clicked tab value', async () => {
    const wrapper = mount(CrmResultTabs, { props: { modelValue: 'open' } });
    await wrapper.get('button[data-value="lost"]').trigger('click');
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['lost']);
  });

  it('uses resolved/cancelled and the funnel names when it is not a sale funnel', () => {
    const pipeline = {
      counts_as_sale: false,
      metadata: { outcome_labels: { success: 'Sinistro pago' } },
    };
    const wrapper = mount(CrmResultTabs, {
      props: { modelValue: 'open', pipeline },
    });
    const values = wrapper
      .findAll('button')
      .map(btn => btn.attributes('data-value'));
    expect(values).toEqual(['open', 'resolved', 'cancelled']);
    expect(wrapper.get('button[data-value="resolved"]').text()).toBe(
      'Sinistro pago'
    );
    expect(wrapper.get('button[data-value="cancelled"]').text()).toBe(
      'CRM_KANBAN.DRAWER.STATUS_CANCELLED'
    );
  });
});
