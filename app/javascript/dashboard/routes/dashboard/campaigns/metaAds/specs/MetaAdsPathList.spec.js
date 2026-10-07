import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsPathList from '../components/MetaAdsPathList.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { panelList: vi.fn(), quoteMessage: vi.fn() },
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '18' }, query: {} }),
}));

const LIST = 'CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST';

const item = overrides => ({
  conversation_id: 901,
  card_id: 77,
  title: 'Virgínia',
  ad_name: 'Promo outubro',
  touched_at: '2026-10-01T15:00:00Z',
  stage_name: 'Proposta',
  status: 'open',
  value: 1500,
  waiting_since: '2026-10-01T10:00:00Z',
  stalled: false,
  response_seconds: null,
  answered: null,
  ...overrides,
});

const reply = list =>
  CrmMetaAdsConnectionAPI.panelList.mockResolvedValue({ data: { list } });

let mounted = null;
const mountList = async (props = {}) => {
  mounted = mount(MetaAdsPathList, {
    props: { step: 'quotes', days: 30, currency: 'BRL', ...props },
    global: {
      mocks: { $t: (key, values) => `${key} ${JSON.stringify(values || {})}` },
      stubs: {
        Spinner: true,
        RouterLink: {
          props: ['to'],
          template:
            '<a :href="typeof to === \'string\' ? to : undefined" :data-to="JSON.stringify(to)"><slot /></a>',
        },
      },
    },
  });
  await flushPromises();
  return mounted;
};

describe('Anúncios da Meta · lista de uma etapa do caminho (#1110, F5)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
  });

  it('asks for the step and the period and shows the title and the total', async () => {
    reply({ step: 'quotes', days: 7, total: 2, items: [item(), item()] });
    const wrapper = await mountList({ days: 7 });

    expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenCalledWith('quotes', 7);
    expect(wrapper.find('[data-panel-path-list]').text()).toContain(
      `${LIST}.TITLE_QUOTES`
    );
    expect(wrapper.find('[data-path-list-total]').text()).toContain(
      `${LIST}.TOTAL_QUOTES {"count":2}`
    );
    expect(wrapper.findAll('[data-panel-path-item]')).toHaveLength(2);
    expect(wrapper.find('[data-path-list-showing]').exists()).toBe(false);
  });

  it('each line goes to the conversation and, with a card, to the CRM', async () => {
    reply({
      step: 'conversations',
      days: 30,
      total: 2,
      items: [item(), item({ conversation_id: 902, card_id: null })],
    });
    const wrapper = await mountList({ step: 'conversations' });

    const [withCard, withoutCard] = wrapper.findAll('[data-panel-path-item]');
    expect(
      withCard.find('[data-path-item-conversation]').attributes('href')
    ).toContain('/app/accounts/18/conversations/901');
    expect(
      JSON.parse(withCard.find('[data-path-item-card]').attributes('data-to'))
    ).toEqual({
      name: 'crm_kanban_index',
      params: { accountId: '18' },
      query: { card_id: '77' },
    });
    expect(withCard.find('[data-path-item-conversation]').classes()).toContain(
      'min-h-11'
    );
    expect(
      withoutCard.find('[data-path-item-conversation]').attributes('href')
    ).toContain('/conversations/902');
    expect(withoutCard.find('[data-path-item-card]').exists()).toBe(false);
  });

  it('offers "Suggest message" only on the stalled quote', async () => {
    reply({
      step: 'quotes',
      days: 30,
      total: 2,
      items: [item({ stalled: true }), item({ card_id: 78, stalled: false })],
    });
    const wrapper = await mountList();

    const [stalled, fresh] = wrapper.findAll('[data-panel-path-item]');
    expect(stalled.find('[data-quote-suggest]').exists()).toBe(true);
    expect(stalled.find('[data-path-item-timing]').classes()).toContain(
      'text-n-amber-11'
    );
    expect(fresh.find('[data-quote-suggest]').exists()).toBe(false);
  });

  it('says how many it shows when there are more than 50', async () => {
    reply({
      step: 'conversations',
      days: 30,
      total: 73,
      items: Array.from({ length: 50 }, (_, index) =>
        item({ conversation_id: index + 1 })
      ),
    });
    const wrapper = await mountList({ step: 'conversations' });

    expect(wrapper.find('[data-path-list-showing]').text()).toContain(
      `${LIST}.SHOWING {"shown":50,"total":73}`
    );
  });

  it('slow replies say "last 30 days" and show the wait or the missing answer', async () => {
    reply({
      step: 'slow_replies',
      days: 30,
      total: 2,
      items: [
        item({ answered: false, response_seconds: null }),
        item({ conversation_id: 902, answered: true, response_seconds: 1500 }),
      ],
    });
    const wrapper = await mountList({ step: 'slow_replies' });

    expect(wrapper.find('[data-path-list-period]').text()).toContain(
      `${LIST}.LAST_30_DAYS`
    );
    const [unanswered, slow] = wrapper.findAll('[data-path-item-timing]');
    expect(unanswered.text()).toContain(`${LIST}.NO_ANSWER`);
    expect(slow.text()).toContain(`${LIST}.ANSWERED_IN`);
    expect(slow.classes()).toContain('text-n-amber-11');
  });

  it('shows the error with "Try again", which asks again', async () => {
    CrmMetaAdsConnectionAPI.panelList.mockRejectedValueOnce(new Error('500'));
    reply({ step: 'sales', days: 30, total: 1, items: [item()] });
    const wrapper = await mountList({ step: 'sales' });

    expect(wrapper.find('[data-path-list-error]').text()).toContain(
      `${LIST}.ERROR`
    );
    const retry = wrapper.find('[data-path-list-retry]');
    expect(retry.classes()).toContain('min-h-11');
    await retry.trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.panelList).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-path-list-error]').exists()).toBe(false);
    expect(wrapper.findAll('[data-panel-path-item]')).toHaveLength(1);
  });

  it('explains an empty step, also without a connection', async () => {
    reply({ step: 'sales', days: 30, total: 0, items: [] });
    const empty = await mountList({ step: 'sales' });
    expect(empty.find('[data-path-list-empty]').exists()).toBe(true);
    empty.unmount();

    reply(null);
    const none = await mountList({ step: 'sales' });
    expect(none.find('[data-path-list-empty]').exists()).toBe(true);
    expect(none.find('[data-path-list-total]').exists()).toBe(false);
  });
});
