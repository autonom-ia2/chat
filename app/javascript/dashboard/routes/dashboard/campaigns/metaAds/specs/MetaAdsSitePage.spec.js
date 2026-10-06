import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsSitePage from '../components/MetaAdsSitePage.vue';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';

vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { get: vi.fn() },
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
    { campaign_key: 'none', name: null, clicks: 4, conversations: 2 },
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
  CtwaTrackedLinksAPI.get.mockResolvedValue({
    data: { payload: [{ ...PAGE, last_signal_at: signalAt }] },
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
});
