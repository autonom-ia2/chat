import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import enResult from 'dashboard/i18n/locale/en/resultJourney.json';
import ResultCrmBand from '../ResultCrmBand.vue';

// #3063: the band leads with the money; with no sale yet it says so instead of "R$ 0".
const mountBand = deals =>
  mount(ResultCrmBand, {
    props: {
      name: 'Renovação auto',
      crm: { source_id: 'campaign:whatsapp:5', enabled: true, deals },
    },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: enResult } }),
      ],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });

describe('ResultCrmBand', () => {
  it('shows the closed sales value and the counts', () => {
    const wrapper = mountBand({
      cards: 9,
      won: 2,
      won_value: [{ currency: 'BRL', cents: 1234500 }],
    });

    expect(wrapper.find('[data-crm-won-value]').text()).toBe(
      'R$12,345 in closed sales'
    );
    expect(wrapper.find('[data-crm-deals]').text()).toContain(
      '9 cards · 2 became a sale'
    );
  });

  it('says there is no sale yet instead of a zero', () => {
    const wrapper = mountBand({ cards: 4, won: 0, won_value: [] });

    expect(wrapper.find('[data-crm-no-sale]').text()).toBe(
      'No closed sale yet'
    );
    expect(wrapper.find('[data-crm-won-value]').exists()).toBe(false);
  });

  it('keeps the counts and hides money for who does not see sales values', () => {
    const wrapper = mountBand({ cards: 4, won: 1, won_value: null });

    expect(wrapper.find('[data-crm-won-value]').exists()).toBe(false);
    expect(wrapper.find('[data-crm-deals]').text()).toContain(
      '4 cards · 1 became a sale'
    );
  });
});
