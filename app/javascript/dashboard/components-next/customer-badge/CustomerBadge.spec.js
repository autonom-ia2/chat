import { mount } from '@vue/test-utils';
import CustomerBadge from './CustomerBadge.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

// 2026-03-15 12:00 UTC
const SINCE = 1773576000;

describe('CustomerBadge', () => {
  it('shows "Cliente" for a customer, with text and not only color', () => {
    const wrapper = mount(CustomerBadge, {
      props: { contact: { contact_type: 'customer', customer_since: SINCE } },
    });

    expect(wrapper.find('[data-customer-badge]').text()).toBe(
      'CONTACT_PANEL.CUSTOMER'
    );
  });

  it('shows the month the contact became a customer when asked', () => {
    const wrapper = mount(CustomerBadge, {
      props: {
        contact: { contact_type: 'customer', customer_since: SINCE },
        showSince: true,
      },
    });

    expect(wrapper.text()).toBe(
      'CONTACT_PANEL.CUSTOMER_SINCE:{"date":"03/2026"}'
    );
  });

  it('falls back to "Cliente" when the date is unknown', () => {
    const wrapper = mount(CustomerBadge, {
      props: { contact: { contact_type: 'customer' }, showSince: true },
    });

    expect(wrapper.text()).toBe('CONTACT_PANEL.CUSTOMER');
  });

  it.each(['lead', 'visitor', undefined])('stays hidden for %s', type => {
    const wrapper = mount(CustomerBadge, {
      props: { contact: { contact_type: type } },
    });

    expect(wrapper.find('[data-customer-badge]').exists()).toBe(false);
  });

  it('stays hidden without a contact', () => {
    expect(mount(CustomerBadge).find('[data-customer-badge]').exists()).toBe(
      false
    );
  });
});
