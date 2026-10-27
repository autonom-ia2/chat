import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
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
});
