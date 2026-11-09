import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import AudienceSearchExtras from '../AudienceSearchExtras.vue';

const NS = en.CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS;

const montar = leftAside =>
  mount(AudienceSearchExtras, {
    props: { leftAside },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

// chat#2733: quem está bloqueado aparece num motivo próprio no fim da lista.
describe('AudienceSearchExtras', () => {
  it('names blocked people under their own reason', () => {
    const wrapper = montar([
      ['Ana', 'bloqueado'],
      ['Bia', 'bloqueado'],
      ['Caio', 'nao_quer'],
    ]);

    const text = wrapper.find('[data-test="left-aside"]').text();
    expect(text).toContain(NS.OUT_BLOCKED.replace('{count}', '2'));
    expect(text).toContain(NS.OUT_OPTED_OUT.replace('{count}', '1'));
  });
});
