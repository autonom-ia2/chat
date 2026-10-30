import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import MetaAdsChecklist from '../components/MetaAdsChecklist.vue';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

// O passo da conta só ganha o visto com o código do site gravado ou "Não tenho site" (#2343).
describe('Anúncios da Meta · passos da conexão', () => {
  const globalPlugins = config.global.plugins;
  beforeAll(() => {
    config.global.plugins = [
      createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
    ];
  });
  afterAll(() => {
    config.global.plugins = globalPlugins;
  });

  const account = wrapper => wrapper.find('[data-step="ACCOUNT"]');

  it('the account step is done when nothing is missing', () => {
    const wrapper = mount(MetaAdsChecklist, { props: { current: 4 } });

    expect(account(wrapper).find('.i-lucide-check').exists()).toBe(true);
    expect(account(wrapper).find('[data-step-pending]').exists()).toBe(false);
  });

  it('without the website code, the account step asks to choose instead of showing done', async () => {
    const wrapper = mount(MetaAdsChecklist, {
      props: { current: 4, accountPending: true },
    });

    expect(account(wrapper).find('.i-lucide-check').exists()).toBe(false);
    expect(account(wrapper).text()).toContain('Falta o código do site');
    await account(wrapper).find('[data-step-pending]').trigger('click');
    expect(wrapper.emitted('change')).toEqual([[2]]);
  });

  it('while the account step is still the current one, nothing is pending', () => {
    const wrapper = mount(MetaAdsChecklist, {
      props: { current: 2, accountPending: true },
    });

    expect(account(wrapper).find('[data-step-pending]').exists()).toBe(false);
  });

  // #2338: anúncio levando ao site sem página ligada — o passo do Destino pede a página, com "Ligar".
  const destinations = wrapper => wrapper.find('[data-step="DESTINATIONS"]');

  it('with the site chosen and no page linked, the destination step asks to link it', async () => {
    const wrapper = mount(MetaAdsChecklist, {
      props: { current: 5, destinationsPending: true },
    });

    expect(destinations(wrapper).find('.i-lucide-check').exists()).toBe(false);
    expect(destinations(wrapper).text()).toContain(
      'Falta ligar a página do site'
    );
    const button = destinations(wrapper).find('[data-step-pending]');
    expect(button.text()).toBe('Ligar');
    await button.trigger('click');
    expect(wrapper.emitted('change')).toEqual([[3]]);
  });
});
