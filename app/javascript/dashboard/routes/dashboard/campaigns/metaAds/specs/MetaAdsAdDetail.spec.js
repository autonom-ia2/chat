import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAdDetail from '../components/MetaAdsAdDetail.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { panelAd: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: {} }),
}));

const daily = count =>
  Array.from({ length: count }, (_, index) => ({
    date: `2026-09-${String(index + 1).padStart(2, '0')}`,
    spend: index % 2 ? 0 : 12.5,
    conversations: index % 3 ? 0 : 2,
  }));

const AD = {
  days: 7,
  from: '2026-09-01',
  to: '2026-09-07',
  currency: 'BRL',
  ad_id: '1',
  name: 'Capa (1080x1350)',
  thumbnail_url: 'https://scontent/capa.jpg',
  preview_url: 'https://fb.me/preview',
  campaign_name: 'Verão',
  adset_name: 'Mulheres 25-45',
  spend: 163.51,
  conversations: 12,
  quotes: 2,
  sales: 0,
  sales_value: 0,
  cost_per_sale: null,
  verdict: 'early',
  account_average_cost_per_sale: 210.4,
  reason: { kind: 'early', missing_conversations: 8, difference: null },
  daily: daily(7),
  quotes_list: [
    {
      card_id: 7,
      title: 'Virgínia',
      value: 842,
      status: 'open',
      stage_name: 'Proposta enviada',
      conversation_id: 99,
      waiting_since: '2026-09-03T10:00:00Z',
    },
    {
      card_id: 8,
      title: 'Lúcia',
      value: 500,
      status: 'won',
      stage_name: 'Venda',
      conversation_id: null,
      waiting_since: null,
    },
  ],
};

let mounted = null;
const mountDetail = async (props = {}, options = {}) => {
  mounted = mount(MetaAdsAdDetail, {
    props: { adId: '1', days: 7, ...props },
    ...options,
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
      stubs: {
        Spinner: true,
        RouterLink: {
          props: ['to'],
          template: '<a :href="to"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return mounted;
};

const answer = ad => ({ data: { ad } });

describe('Anúncios da Meta · o anúncio por dentro (#1088, F3b)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(answer(AD));
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.useRealTimers();
  });

  it('asks for the ad and period and shows name, campaign and ad set', async () => {
    const wrapper = await mountDetail();

    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledWith('1', 7);
    expect(wrapper.find('[data-ad-detail-name]').text()).toBe(
      'Capa (1080x1350)'
    );
    const context = wrapper.find('[data-ad-detail-context]').text();
    expect(context).toContain('AD_DETAIL.CAMPAIGN');
    expect(context).toContain('AD_DETAIL.ADSET');
    expect(wrapper.find('[data-ad-detail-image]').attributes('src')).toBe(
      'https://scontent/capa.jpg'
    );
  });

  it('swaps an image that does not load (expired Meta link) for the placeholder', async () => {
    const wrapper = await mountDetail();

    await wrapper.find('[data-ad-detail-image]').trigger('error');

    expect(wrapper.find('[data-ad-detail-image]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-detail-placeholder]').exists()).toBe(true);
  });

  it('shows the verdict, the tiles and the early reason with the meanwhile block', async () => {
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-verdict]').text()).toContain('VERDICT.EARLY');
    expect(wrapper.find('[data-ad-detail-tile="SALES"]').text()).toContain('0');
    expect(
      wrapper.find('[data-ad-detail-tile="CONVERSATIONS"]').text()
    ).toContain('12');
    const why = wrapper.find('[data-ad-detail-why]');
    expect(why.attributes('data-reason')).toBe('early');
    expect(why.text()).toContain('AD_DETAIL.REASON.EARLY');
    expect(wrapper.find('[data-ad-detail-meanwhile]').text()).toContain(
      '"count":2'
    );
  });

  it.each([
    ['no_sales', 'review', 'NO_SALES'],
    ['signal', 'signal', 'SIGNAL'],
    ['below_average', 'up', 'BELOW_AVERAGE'],
    ['near_average', 'keep', 'NEAR_AVERAGE'],
    ['above_average', 'review', 'ABOVE_AVERAGE'],
  ])('explains the %s reason in words', async (kind, verdict, key) => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({
        ...AD,
        verdict,
        sales: 3,
        cost_per_sale: 150,
        reason: { kind, missing_conversations: 0, difference: 60.4 },
      })
    );
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-detail-why]').text()).toContain(
      `AD_DETAIL.REASON.${key}`
    );
    expect(wrapper.find('[data-ad-detail-meanwhile]').exists()).toBe(false);
    expect(wrapper.find('[data-verdict]').attributes('data-verdict')).toBe(
      verdict
    );
  });

  it('lists the quotes of the ad with the link to the conversation', async () => {
    const wrapper = await mountDetail();

    const open = wrapper.find('[data-ad-detail-quote="7"]');
    expect(open.text()).toContain('Virgínia');
    expect(open.text()).toContain('Proposta enviada');
    expect(open.text()).toContain('PANEL.STALLED_SINCE');
    expect(open.find('a').attributes('href')).toContain(
      '/app/accounts/18/conversations/99'
    );
    const won = wrapper.find('[data-ad-detail-quote="8"]');
    expect(won.find('[data-ad-detail-quote-won]').exists()).toBe(true);
    expect(won.find('a').exists()).toBe(false);
  });

  it('draws one bar per day and a dot only on days with conversations', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({ ...AD, daily: daily(30) })
    );
    const wrapper = await mountDetail({ days: 30 });

    expect(wrapper.findAll('[data-ad-detail-bar]')).toHaveLength(30);
    expect(wrapper.findAll('[data-ad-detail-dot]')).toHaveLength(10);
  });

  it('says so when the ad has no data', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(answer(null));
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-detail-empty]').exists()).toBe(true);
    expect(wrapper.find('[data-ad-detail-back]').exists()).toBe(true);
  });

  it('back asks the panel to close the ad', async () => {
    const wrapper = await mountDetail();

    await wrapper.find('[data-ad-detail-back]').trigger('click');

    expect(wrapper.emitted('back')).toHaveLength(1);
  });

  it('drops the answer of a period that is no longer chosen', async () => {
    const wrapper = await mountDetail();
    let slow;
    CrmMetaAdsConnectionAPI.panelAd
      .mockReturnValueOnce(
        new Promise(resolve => {
          slow = resolve;
        })
      )
      .mockResolvedValueOnce(answer({ ...AD, days: 7, conversations: 5 }));

    await wrapper.setProps({ days: 30 });
    await wrapper.setProps({ days: 7 });
    await flushPromises();
    slow(answer({ ...AD, days: 30, conversations: 999 }));
    await flushPromises();

    const tile = wrapper.find('[data-ad-detail-tile="CONVERSATIONS"]').text();
    expect(tile).toContain('5');
    expect(tile).not.toContain('999');
  });

  it('reloads on the realtime event', async () => {
    await mountDetail();

    emitter.emit(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, { account_id: 18 });
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledTimes(2);
  });

  it('counts the open quotes from the ad numbers, not from the list cut at 20', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({ ...AD, quotes: 35, sales: 0 })
    );
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-detail-meanwhile]').text()).toContain(
      '"count":35'
    );
  });

  it('without a sale shows what exists instead of two dashes on top', async () => {
    const wrapper = await mountDetail();

    const keys = wrapper
      .findAll('[data-ad-detail-tile]')
      .map(tile => tile.attributes('data-ad-detail-tile'));
    expect(keys).toEqual(['SPEND', 'CONVERSATIONS', 'QUOTES', 'SALES']);
  });

  it('with a sale puts cost per sale next to the account average', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({
        ...AD,
        verdict: 'up',
        sales: 3,
        cost_per_sale: 150,
        reason: { kind: 'below_average', difference: 60.4 },
      })
    );
    const wrapper = await mountDetail();

    const keys = wrapper
      .findAll('[data-ad-detail-tile]')
      .map(tile => tile.attributes('data-ad-detail-tile'));
    expect(keys).toEqual([
      'COST_PER_SALE',
      'AVERAGE',
      'SALES',
      'CONVERSATIONS',
    ]);
  });

  it('the meanwhile button takes the person to the quotes list', async () => {
    const scroll = vi.fn();
    Element.prototype.scrollIntoView = scroll;
    const wrapper = await mountDetail({}, { attachTo: document.body });

    const see = wrapper.find('[data-ad-detail-meanwhile-see]');
    expect(see.classes()).toContain('min-h-11');
    await see.trigger('click');

    expect(scroll).toHaveBeenCalled();
    expect(document.activeElement.textContent).toContain(
      'AD_DETAIL.QUOTES_TITLE'
    );
    delete Element.prototype.scrollIntoView;
  });

  it('shows campaign and ad set names without repeating the label in the sentence', async () => {
    const wrapper = await mountDetail();

    const context = wrapper.find('[data-ad-detail-context]').text();
    expect(context).toContain('Verão');
    expect(context).toContain('Mulheres 25-45');
    expect(context).toContain('AD_DETAIL.CAMPAIGN {}');
  });

  it('gives the numbers of each day in a table, for touch and screen readers', async () => {
    const wrapper = await mountDetail();

    expect(
      wrapper.find('[data-ad-detail-chart]').attributes('aria-hidden')
    ).toBe('true');
    expect(wrapper.findAll('[data-ad-detail-day]')).toHaveLength(7);
    expect(wrapper.find('[data-ad-detail-chart-scale]').text()).toContain(
      'AD_DETAIL.CHART_SCALE'
    );
  });

  it('turns a failed first read into a message with try again, not an endless spinner', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockRejectedValueOnce(new Error('500'));
    const wrapper = await mountDetail();

    expect(wrapper.find('spinner-stub').exists()).toBe(false);
    expect(wrapper.find('[data-ad-detail-error]').exists()).toBe(true);

    await wrapper.find('[data-ad-detail-retry]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-ad-detail-error]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-detail-name]').exists()).toBe(true);
  });

  it('keeps the numbers on screen when a later read fails', async () => {
    const wrapper = await mountDetail();
    CrmMetaAdsConnectionAPI.panelAd.mockRejectedValueOnce(new Error('500'));

    emitter.emit(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, { account_id: 18 });
    await flushPromises();

    expect(wrapper.find('[data-ad-detail-name]').exists()).toBe(true);
    expect(wrapper.find('[data-ad-detail-error]').exists()).toBe(false);
  });
});
