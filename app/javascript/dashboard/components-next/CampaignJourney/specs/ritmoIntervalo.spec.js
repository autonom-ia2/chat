import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import RitmoIntervalo from '../ritmo/RitmoIntervalo.vue';

const montar = props =>
  mount(RitmoIntervalo, {
    props,
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

describe('RitmoIntervalo (#3101)', () => {
  it('explains the gap only when one is chosen', async () => {
    const wrapper = montar({ modelValue: 0 });
    expect(wrapper.find('[data-ritmo-intervalo-exemplo]').exists()).toBe(false);

    await wrapper.setProps({ modelValue: 4 });
    expect(wrapper.find('[data-ritmo-intervalo-exemplo]').text()).toContain(
      'at least 4 hours'
    );
  });
});
