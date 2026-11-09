import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import pt from 'dashboard/i18n/locale/pt_BR/emailCampaignProtection.json';
import enLists from 'dashboard/i18n/locale/en/emailLists.json';
import ptLists from 'dashboard/i18n/locale/pt_BR/emailLists.json';
import Badge from '../EmailStatusBadge.vue';

// G52 (#2760): a campanha com lista que falhou na hora do envio diz por quê no selo.
const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const messages = { en: { ...en, ...enLists }, pt_BR: { ...pt, ...ptLists } };

describe.each(['en', 'pt_BR'])('e-mail list failure in %s', locale => {
  const i18n = createI18n({ legacy: false, locale, messages });
  const { t } = i18n.global;
  const titulo = record =>
    mount(Badge, {
      global: { plugins: [i18n] },
      props: { record, campaign: true },
    }).attributes('title');

  it.each([
    ['email_list_empty', 'EMAIL_LISTS.FALHA.VAZIA'],
    ['email_list_all_suppressed', 'EMAIL_LISTS.FALHA.TODOS_BLOQUEADOS'],
  ])('%s', (code, key) => {
    expect(t(key)).not.toBe(key);
    expect(titulo({ status: 'failed', last_error: code })).toBe(t(key));
  });

  it('outro erro não vira motivo de lista', () => {
    expect(
      titulo({ status: 'failed', last_error: 'email_campaign.failed' })
    ).not.toContain(t('EMAIL_LISTS.FALHA.VAZIA'));
  });
});
