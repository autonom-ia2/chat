import { config, flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/metaAdsOrganico.json';
import MetaAdsOrganic from '../organico/MetaAdsOrganic.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import FBChannel from 'dashboard/api/channel/fbChannel';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { organico: vi.fn() },
}));
vi.mock('dashboard/api/channel/fbChannel', () => ({
  default: { reauthorizeFacebookPage: vi.fn() },
}));
vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: { generateAuthorization: vi.fn() },
}));
const login = vi.fn();
vi.mock('dashboard/composables/useFacebookPageConnect', () => ({
  useFacebookPageConnect: () => ({
    preloadSdk: () => Promise.resolve(),
    login,
  }),
}));
const granted = ref(['integration_manage', 'inbox_manage']);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    usePermissionGranted: key => computed(() => granted.value.includes(key)),
  };
});
const push = vi.fn();
const replace = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: {}, params: { accountId: 1 } }),
  useRouter: () => ({ push, replace }),
}));

const ready = (extra = {}) => ({
  status: 'ok',
  link: 'https://www.facebook.com/studioacme',
  followers: 8412,
  reach: 4900,
  views: 12700,
  interactions: 791,
  new_followers: 146,
  previous: null,
  messages: { count: 14, inbox_id: 7 },
  top_posts: [],
  ...extra,
});

const answer = (page, instagram) =>
  CrmMetaAdsConnectionAPI.organico.mockResolvedValue({
    data: { days: 30, from: '2026-09-28', to: '2026-10-27', page, instagram },
  });

const mountScreen = async () => {
  const wrapper = mount(MetaAdsOrganic, {
    global: { stubs: { OrganicSourceCard: false } },
  });
  await flushPromises();
  return wrapper;
};

describe('Anúncios · Seus posts (#2199)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    granted.value = ['integration_manage', 'inbox_manage'];
    delete window.location;
    window.location = { href: '' };
  });

  it('reads the numbers of the period from the server', async () => {
    answer(ready({ name: 'Studio Acme', views_from_ads: 4064 }), {
      status: 'not_connected',
    });

    const wrapper = await mountScreen();

    expect(CrmMetaAdsConnectionAPI.organico).toHaveBeenCalledWith(30);
    expect(wrapper.find('[data-organic-source="page"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-organic-blocked="not_connected"]').exists()
    ).toBe(true);
  });

  it('a number Meta did not send shows "—", never 0', async () => {
    answer(
      ready({
        name: 'Studio Acme',
        views: null,
        reach: null,
        views_from_ads: null,
      }),
      { status: 'not_connected' }
    );

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-hero]').text()).toContain(
      'META_ADS_ORGANIC.HEADLINE.UNAVAILABLE'
    );
    expect(wrapper.find('[data-organic-tile="views"]').text()).toContain('—');
    expect(wrapper.find('[data-organic-quiet]').exists()).toBe(false);
  });

  it('a place without the number does not turn the other 0 into "nobody saw"', async () => {
    answer(
      ready({ name: 'Studio Acme', views: null }),
      ready({ username: 'studioacme', views: 0 })
    );

    const wrapper = await mountScreen();

    const hero = wrapper.find('[data-organic-hero]').text();
    expect(hero).not.toContain('META_ADS_ORGANIC.HEADLINE.ZERO');
    expect(hero).toContain('META_ADS_ORGANIC.HEADLINE.INSTAGRAM');
  });

  it('shows the retry when Meta is down', async () => {
    CrmMetaAdsConnectionAPI.organico.mockRejectedValue(new Error('503'));

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-error]').exists()).toBe(true);
  });

  it('reauthorizes the Page with read_insights and reads again', async () => {
    answer(
      { status: 'needs_permission', name: 'Studio Acme', inbox_id: 7 },
      ready({ username: 'studioacme', messages: null })
    );
    login.mockResolvedValue('user-token');
    FBChannel.reauthorizeFacebookPage.mockResolvedValue({});
    const wrapper = await mountScreen();

    await wrapper.find('[data-organic-connect="page"]').trigger('click');
    await flushPromises();

    expect(login).toHaveBeenCalledWith(['read_insights']);
    expect(FBChannel.reauthorizeFacebookPage).toHaveBeenCalledWith({
      omniauthToken: 'user-token',
      inboxId: 7,
    });
    expect(CrmMetaAdsConnectionAPI.organico).toHaveBeenCalledTimes(2);
  });

  it('sends Instagram to its login and back to this tab', async () => {
    answer(ready({ name: 'Studio Acme' }), {
      status: 'needs_permission',
      username: 'studioacme',
      inbox_id: 9,
    });
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: 'https://www.instagram.com/oauth/authorize?x=1' },
    });
    const wrapper = await mountScreen();

    await wrapper.find('[data-organic-connect="instagram"]').trigger('click');
    await flushPromises();

    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
      inbox_id: 9,
      return_to: 'meta_ads',
      purpose: 'meta_ads_organico',
    });
    expect(window.location.href).toBe(
      'https://www.instagram.com/oauth/authorize?x=1'
    );
  });

  it('warns when the sign-in fails', async () => {
    answer(ready({ name: 'Studio Acme' }), {
      status: 'needs_permission',
      inbox_id: 9,
    });
    instagramClient.generateAuthorization.mockRejectedValue(new Error('422'));
    const wrapper = await mountScreen();

    await wrapper.find('[data-organic-connect="instagram"]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('META_ADS_ORGANIC.CONNECT_ERROR');
  });

  it('without a Page inbox, opens the usual Facebook inbox creation', async () => {
    answer({ status: 'not_connected' }, ready({ username: 'studioacme' }));
    const wrapper = await mountScreen();

    await wrapper.find('[data-organic-connect="page"]').trigger('click');

    expect(push).toHaveBeenCalledWith(
      '/app/accounts/1/settings/inboxes/new/facebook'
    );
  });

  it('who cannot see the inbox reads "no access", never 0', async () => {
    answer(
      ready({ name: 'Studio Acme', messages: { count: null, inbox_id: null } }),
      { status: 'not_connected' }
    );

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-messages]').text()).toBe(
      'META_ADS_ORGANIC.MESSAGES_NO_ACCESS'
    );
    expect(wrapper.find('[data-organic-main-conversations]').exists()).toBe(
      false
    );
  });

  it('who cannot swap the inbox credential reads "ask an admin"', async () => {
    granted.value = ['inbox_manage'];
    answer(
      { status: 'needs_permission', name: 'Studio Acme', inbox_id: 7 },
      ready({ username: 'studioacme' })
    );

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-connect="page"]').exists()).toBe(false);
    expect(wrapper.text()).toContain('META_ADS_ORGANIC.ASK_ADMIN');
  });

  // A volta do login do Instagram exige também inbox_manage (OauthBinding), mesmo para reautorizar.
  it('Instagram reauthorization asks for inbox_manage too', async () => {
    granted.value = ['integration_manage'];
    answer(ready({ name: 'Studio Acme' }), {
      status: 'needs_permission',
      inbox_id: 9,
    });

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-connect="instagram"]').exists()).toBe(
      false
    );
  });

  // Sem anúncio (#2199, conta real de 27/10): o alcance do Instagram é soma por tipo, sem deduplicar; o destaque
  // passa a ser as vezes que apareceu.
  it('leads with times shown and reads Instagram reach as "up to"', async () => {
    answer(ready({ name: 'Studio Acme', views_from_ads: 4064 }), ready());

    const wrapper = await mountScreen();
    const instagramCard = wrapper.find('[data-organic-source="instagram"]');
    const tiles = instagramCard.findAll('[data-organic-tile]');

    expect(tiles[0].attributes('data-organic-tile')).toBe('views');
    expect(instagramCard.find('[data-organic-tile="reach"]').text()).toContain(
      'META_ADS_ORGANIC.TILES.UP_TO'
    );
    expect(
      wrapper
        .find('[data-organic-source="page"] [data-organic-tile="reach"]')
        .text()
    ).not.toContain('META_ADS_ORGANIC.TILES.UP_TO');
  });

  it('previous period without views, says so instead of "X more"', async () => {
    answer(
      ready({ name: 'Studio Acme', views_from_ads: 4064 }),
      ready({ previous: null, first_period: true })
    );

    const wrapper = await mountScreen();
    const instagramCard = wrapper.find('[data-organic-source="instagram"]');

    expect(instagramCard.find('[data-organic-first-period]').text()).toBe(
      'META_ADS_ORGANIC.TILES.FIRST_PERIOD'
    );
    expect(instagramCard.find('[data-organic-change]').exists()).toBe(false);
  });

  // Meta fora só no Instagram: a Página aparece e só o cartão do Instagram pede "Tentar de novo", até para quem só lê.
  it('Meta down on Instagram only: retry lives in its card and reads again', async () => {
    granted.value = [];
    answer(ready({ name: 'Studio Acme', views_from_ads: 4064 }), {
      status: 'unavailable',
    });
    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-error]').exists()).toBe(false);
    expect(
      wrapper.find('[data-organic-source="page"] [data-organic-tile]').exists()
    ).toBe(true);
    const retry = wrapper.find('[data-organic-retry="instagram"]');
    expect(retry.exists()).toBe(true);
    expect(wrapper.find('[data-organic-retry="page"]').exists()).toBe(false);

    await retry.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.organico).toHaveBeenCalledTimes(2);
  });

  // Página: views já vem sem anúncio; a barra "vale pagar?" soma o anúncio de volta para o total.
  it('Page bar splits free and paid times from views without ads', async () => {
    answer(ready({ name: 'Studio Acme', views: 8636, views_from_ads: 4064 }), {
      status: 'not_connected',
    });

    const wrapper = await mountScreen();
    const bar = wrapper.findComponent({ name: 'OrganicShareBar' });

    expect(bar.props()).toMatchObject({ part: 8636, total: 12700 });
  });
});

// Com os textos reais (o i18n vazio do setup dá lugar ao pt_BR só neste bloco): os números que a pessoa lê.
describe('Anúncios · Seus posts sem anúncio, textos reais (#2199)', () => {
  let savedPlugins;

  beforeEach(() => {
    vi.clearAllMocks();
    granted.value = ['integration_manage', 'inbox_manage'];
    savedPlugins = config.global.plugins;
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        messages: { pt_BR: ptBR },
        missingWarn: false,
        fallbackWarn: false,
      }),
    ];
  });

  afterEach(() => {
    config.global.plugins = savedPlugins;
  });

  it('headline counts times shown without ads; Instagram reach reads "até N" with no "X a mais"', async () => {
    answer(
      ready({ name: 'Studio Acme', views: 8636, views_from_ads: 4064 }),
      ready({ reach: 349, previous: { reach: 77, views: 350 } })
    );

    const wrapper = await mountScreen();
    const reach = wrapper.find(
      '[data-organic-source="instagram"] [data-organic-tile="reach"]'
    );

    expect(wrapper.text()).toContain(
      'Seus posts apareceram 8.636 vezes no Facebook e 12.700 no Instagram, sem contar anúncios.'
    );
    expect(reach.text()).toContain('até 349');
    expect(reach.find('[data-organic-change]').exists()).toBe(false);
  });

  it('Meta down with nothing else to show: the headline says so, not "allow access"', async () => {
    answer({ status: 'unavailable' }, { status: 'not_connected' });

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-headline]').text()).toBe(
      'Não deu para ler os números agora. Tente de novo.'
    );
  });

  it('previous period without views, explains the missing comparison', async () => {
    answer(
      { status: 'not_connected' },
      ready({ previous: null, first_period: true })
    );

    const wrapper = await mountScreen();

    expect(wrapper.find('[data-organic-first-period]').text()).toBe(
      'Primeiro período com dado: nos 30 dias anteriores seus posts não apareceram sem anúncio.'
    );
  });
});
