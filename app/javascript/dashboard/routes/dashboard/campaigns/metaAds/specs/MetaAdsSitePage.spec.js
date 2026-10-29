import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsSitePage from '../components/MetaAdsSitePage.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { relativeTime } from '../metaAdsHelpers';

// "Testar agora" relê a página por Anúncios (#2338), que não traz cliques nem campanhas.
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { sitePages: vi.fn() },
}));

const BEFORE = '2026-10-06T10:00:00Z';
const PAGE = {
  id: 2,
  name: 'LP Seguro Viagem',
  usage: 'website',
  allowed_origins: ['https://placement.com.br'],
  last_signal_at: BEFORE,
  campaigns: [
    { campaign_key: '1', name: 'CBO 1-1-4', clicks: 31, conversations: 22 },
    { campaign_key: '2', name: 'Viagem Europa', clicks: 9, conversations: 7 },
    {
      campaign_key: 'none',
      name: null,
      clicks: 4,
      meta_clicks: 4,
      conversations: 2,
    },
  ],
};

const mountPage = (page = PAGE) =>
  mount(MetaAdsSitePage, {
    props: { page },
    global: {
      mocks: { $t: key => key },
      stubs: { Button: { template: '<button><slot /></button>' } },
    },
  });

const replyWith = signalAt =>
  CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
    data: {
      payload: [{ ...PAGE, campaigns: undefined, last_signal_at: signalAt }],
    },
  });

describe('Anúncios da Meta · página do site (#1047)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.spyOn(window, 'open').mockReturnValue(null);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('confirms each named campaign and flags clicks without a name', () => {
    const wrapper = mountPage();

    expect(wrapper.findAll('[data-site-campaign]')).toHaveLength(2);
    expect(wrapper.text()).toContain('CBO 1-1-4');
    expect(wrapper.find('[data-site-unnamed]').exists()).toBe(true);
  });

  it('opens the page and confirms when a new click arrives', async () => {
    replyWith('2026-10-06T16:52:00Z');
    const wrapper = mountPage();

    await wrapper.find('[data-site-test]').trigger('click');
    expect(window.open).toHaveBeenCalledWith(
      'https://placement.com.br',
      '_blank',
      'noopener'
    );
    expect(wrapper.find('[data-site-test-waiting]').exists()).toBe(true);

    await vi.advanceTimersByTimeAsync(5000);
    await flushPromises();

    expect(wrapper.find('[data-site-test-ok]').exists()).toBe(true);
    expect(wrapper.findAll('[data-site-campaign]')).toHaveLength(2);
  });

  it('gives up with a hint when no click arrives in time', async () => {
    replyWith(BEFORE);
    const wrapper = mountPage();

    await wrapper.find('[data-site-test]').trigger('click');
    await vi.advanceTimersByTimeAsync(5000 * 36);
    await flushPromises();

    expect(wrapper.find('[data-site-test-ok]').exists()).toBe(false);
    expect(wrapper.find('[data-site-test-timeout]').exists()).toBe(true);
  });

  it('hides the test when the page has no authorized address', () => {
    const wrapper = mountPage({ ...PAGE, allowed_origins: [] });

    expect(wrapper.find('[data-site-test]').exists()).toBe(false);
  });

  it('says when the last click without a name came and sends the website kit (#1068)', () => {
    const wrapper = mountPage({
      ...PAGE,
      kit_url: 'https://chat.hub2you.ai/l/GB7DDH/kit',
      campaigns: [
        {
          campaign_key: 'none',
          name: null,
          clicks: 4,
          meta_clicks: 4,
          last_clicked_at: '2026-10-06T10:00:00Z',
          last_meta_clicked_at: '2026-10-06T10:00:00Z',
        },
      ],
    });

    expect(wrapper.get('[data-site-unnamed]').text()).toContain(
      'CRM_KANBAN.META_ADS_HUB.SITE.UNNAMED_WHEN'
    );
    const href = wrapper.get('[data-site-kit-whatsapp]').attributes('href');
    expect(href.startsWith('https://wa.me/?text=')).toBe(true);
  });

  // #2338: visita direta ao site também chega sem nome de campanha. O aviso conta só clique de anúncio, e o "último"
  // é o do último clique de anúncio.
  describe('clicks without a campaign name', () => {
    const mountCounting = campaigns =>
      mount(MetaAdsSitePage, {
        props: { page: { ...PAGE, campaigns } },
        global: {
          mocks: {
            $t: (key, params) =>
              `${key} ${params?.count ?? ''} ${params?.time ?? ''}`,
          },
          stubs: { Button: { template: '<button><slot /></button>' } },
        },
      });

    it('counts only the clicks that came from an ad', () => {
      const wrapper = mountCounting([
        { campaign_key: 'none', name: null, clicks: 9, meta_clicks: 1 },
      ]);

      expect(wrapper.get('[data-site-unnamed]').text()).toContain(
        'CRM_KANBAN.META_ADS_HUB.SITE.UNNAMED 1'
      );
    });

    it('hides the warning when no click without a name came from an ad', () => {
      const wrapper = mountCounting([
        { campaign_key: 'none', name: null, clicks: 8, meta_clicks: 0 },
      ]);

      expect(wrapper.find('[data-site-unnamed]').exists()).toBe(false);
    });

    it('dates the warning by the last click from an ad, not the last visit', () => {
      vi.setSystemTime(new Date('2026-10-06T12:00:00Z'));
      const wrapper = mountCounting([
        {
          campaign_key: 'none',
          name: null,
          clicks: 9,
          meta_clicks: 1,
          last_clicked_at: '2026-10-06T11:59:00Z',
          last_meta_clicked_at: '2026-10-04T12:00:00Z',
        },
      ]);

      const text = wrapper.get('[data-site-unnamed]').text();
      expect(text).toContain('CRM_KANBAN.META_ADS_HUB.SITE.UNNAMED_WHEN 1');
      expect(text).toContain(relativeTime('2026-10-04T12:00:00Z', 'en'));
      expect(text).not.toContain(relativeTime('2026-10-06T11:59:00Z', 'en'));
    });
  });
});
