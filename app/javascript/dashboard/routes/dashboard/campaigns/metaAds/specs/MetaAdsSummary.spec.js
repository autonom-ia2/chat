import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsSummary from '../components/MetaAdsSummary.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { funnels: vi.fn(), insights: vi.fn(), remove: vi.fn() },
}));
vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { get: vi.fn() },
}));

const CONNECTION = {
  status: 'active',
  mode: 'token',
  ad_account: { id: '1', name: 'CA - Placement Seguros' },
  destinations: { whatsapp: true, site: false },
};

const today = () => {
  const now = new Date();
  const pad = value => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
};

let mounted = null;

const mountSummary = async (connection = CONNECTION) => {
  mounted = mount(MetaAdsSummary, {
    props: { connection },
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
      stubs: {
        Button: { template: '<button><slot /></button>' },
        Dialog: true,
        RouterLink: { template: '<a><slot /></a>' },
      },
    },
  });
  await flushPromises();
  return mounted;
};

const replyInsights = insights =>
  CrmMetaAdsConnectionAPI.insights.mockResolvedValue({ data: { insights } });

describe('Anúncios da Meta · resumo com o gasto (#1073)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.funnels.mockResolvedValue({
      data: { funnels: [] },
    });
    CtwaTrackedLinksAPI.get.mockResolvedValue({ data: { payload: [] } });
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.useRealTimers();
  });

  it('asks for the numbers on open and shows today spend while refreshing', async () => {
    replyInsights({
      date: today(),
      spend: '42.5',
      currency: 'BRL',
      conversations: 3,
      synced_at: new Date(Date.now() - 22 * 60 * 1000).toISOString(),
      refreshing: true,
    });

    const wrapper = await mountSummary();

    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(1);
    const line = wrapper.find('[data-summary-spend]');
    expect(line.text()).toContain('SPEND_TODAY');
    expect(wrapper.find('[data-summary-spend-value]').text()).toContain(
      '42.50'
    );
    expect(wrapper.find('[data-summary-spend-refreshing]').exists()).toBe(true);
  });

  it('swaps the numbers when the realtime event arrives', async () => {
    replyInsights({ date: null, refreshing: true });
    const wrapper = await mountSummary();
    expect(wrapper.find('[data-summary-spend]').text()).toContain(
      'SPEND_EMPTY'
    );

    emitter.emit(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, {
      account_id: 18,
      date: today(),
      spend: '10',
      currency: 'BRL',
      conversations: 1,
      synced_at: new Date().toISOString(),
      refreshing: false,
    });
    await flushPromises();

    expect(wrapper.find('[data-summary-spend-value]').text()).toContain(
      '10.00'
    );
    expect(wrapper.find('[data-summary-spend-refreshing]').exists()).toBe(
      false
    );
  });

  it('uses the ad account day from the server to say today', async () => {
    replyInsights({
      date: '2026-01-02',
      today: '2026-01-02',
      spend: '0',
      currency: 'BRL',
      conversations: 0,
      refreshing: false,
    });

    const wrapper = await mountSummary();

    expect(wrapper.find('[data-summary-spend]').text()).toContain(
      'SPEND_TODAY'
    );
  });

  it('asks again every 2 minutes while the page is open', async () => {
    vi.useFakeTimers();
    replyInsights({ date: today(), spend: '1', refreshing: false });
    await mountSummary();
    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(2 * 60 * 1000);

    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(2);
  });

  it('checks again in 20 seconds while a read is running, in case the realtime event is lost', async () => {
    vi.useFakeTimers();
    replyInsights({ date: null, refreshing: true });
    await mountSummary();

    await vi.advanceTimersByTimeAsync(20 * 1000);

    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(2);
  });

  it('refreshes when the tab becomes visible again', async () => {
    replyInsights({ date: today(), spend: '1', refreshing: false });
    await mountSummary();

    document.dispatchEvent(new Event('visibilitychange'));
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(2);
  });

  it('shows the 90-day load while it runs', async () => {
    replyInsights({ date: null, refreshing: true, backfilling: true });

    const wrapper = await mountSummary();

    expect(wrapper.find('[data-summary-spend-backfilling]').exists()).toBe(
      true
    );
    expect(wrapper.text()).not.toContain('SPEND_EMPTY');
  });

  it('keeps the last numbers when a refresh fails', async () => {
    vi.useFakeTimers();
    replyInsights({ date: today(), spend: '7', currency: 'BRL' });
    const wrapper = await mountSummary();
    CrmMetaAdsConnectionAPI.insights.mockRejectedValue(new Error('offline'));

    await vi.advanceTimersByTimeAsync(2 * 60 * 1000);

    expect(wrapper.find('[data-summary-spend-value]').text()).toContain('7.00');
  });

  it('schedules nothing after leaving the page, even with a request in flight', async () => {
    vi.useFakeTimers();
    let answer;
    CrmMetaAdsConnectionAPI.insights.mockReturnValue(
      new Promise(resolve => {
        answer = resolve;
      })
    );
    const wrapper = await mountSummary();
    wrapper.unmount();
    mounted = null;

    answer({ data: { insights: { date: null, refreshing: true } } });
    await flushPromises();
    await vi.advanceTimersByTimeAsync(5 * 60 * 1000);

    expect(CrmMetaAdsConnectionAPI.insights).toHaveBeenCalledTimes(1);
  });

  it('labels an older day with its date instead of today', async () => {
    replyInsights({
      date: '2026-01-02',
      spend: '5',
      currency: 'BRL',
      conversations: 0,
      refreshing: false,
    });

    const wrapper = await mountSummary();

    expect(wrapper.find('[data-summary-spend]').text()).toContain('SPEND_ON');
  });

  it('explains the lost ad account and does not ask for numbers', async () => {
    const wrapper = await mountSummary({
      ...CONNECTION,
      status: 'invalid',
      last_error: 'ad_account_access_lost',
    });

    expect(CrmMetaAdsConnectionAPI.insights).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain('ACCESS_LOST_HINT');
    expect(wrapper.find('[data-summary-spend]').exists()).toBe(false);
  });
});
