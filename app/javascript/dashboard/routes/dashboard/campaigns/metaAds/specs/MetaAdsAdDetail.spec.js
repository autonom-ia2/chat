import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAdDetail from '../components/MetaAdsAdDetail.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { lerGestao } from '../gestaoDoAnuncio';
import comentariosInstagram from '../components/comentarios/comentariosInstagram';
import MetaAdsAdStatus from '../components/MetaAdsAdStatus.vue';
import MetaAdsComments from '../components/comentarios/MetaAdsComments.vue';

// Permissões negadas no teste; o resto passa (administrador).
const { negadas } = vi.hoisted(() => ({ negadas: new Set() }));

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { panelAd: vi.fn(), adBudget: vi.fn() },
}));
// Gestão mínima (#2161): a flag meta_ads_gestao e a situação/post vêm do adaptador.
const flags = ref({});
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    computed(() => (_accountId, flag) => Boolean(flags.value[flag])),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: key => computed(() => !negadas.has(key)),
}));
vi.mock('../gestaoDoAnuncio', () => ({ lerGestao: vi.fn() }));
// Comentários (#2196): o adaptador do Instagram responde sem chamar a API.
vi.mock('../components/comentarios/comentariosInstagram', async () => {
  const real = await vi.importActual(
    '../components/comentarios/comentariosInstagram'
  );
  return {
    default: {
      listar: vi.fn(),
      podeEntrar: real.podeEntrar,
      PERMISSOES_PARA_ENTRAR: real.PERMISSOES_PARA_ENTRAR,
    },
  };
});
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
    props: { adId: '1', period: '7d', ...props },
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
    flags.value = {};
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(answer(AD));
  });

  afterEach(() => {
    mounted?.unmount();
    mounted = null;
    vi.useRealTimers();
  });

  it('asks for the ad and period and shows name, campaign and ad set', async () => {
    const wrapper = await mountDetail();

    expect(CrmMetaAdsConnectionAPI.panelAd).toHaveBeenCalledWith('1', '7d');
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

  // #2075 — sem a chave de valores de venda, a proposta de outra pessoa vem sem valor; a da própria pessoa, com.
  it('shows the value only on the quotes that come with one', async () => {
    const [stalled, won] = AD.quotes_list;
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({
        ...AD,
        sales_value: null,
        value_hidden: true,
        quotes_list: [{ ...stalled, value: null, value_hidden: true }, won],
      })
    );
    const wrapper = await mountDetail();

    const hidden = wrapper.find('[data-ad-detail-quote="7"]');
    expect(hidden.text()).toContain('Virgínia');
    expect(hidden.text()).not.toMatch(/R\$|842/);
    expect(wrapper.find('[data-ad-detail-quote="8"]').text()).toContain('500');
  });

  it('draws one bar per day and a dot only on days with conversations', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({ ...AD, daily: daily(30) })
    );
    const wrapper = await mountDetail({ period: '30d' });

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

    await wrapper.setProps({ period: '30d' });
    await wrapper.setProps({ period: '7d' });
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
  it('shows the comments only with the Instagram comments flag on (#2196)', async () => {
    lerGestao.mockResolvedValue(null);
    flags.value = { meta_ads_gestao: true };
    const off = await mountDetail();
    expect(off.find('[data-ad-comments]').exists()).toBe(false);
    off.unmount();

    comentariosInstagram.listar.mockResolvedValue({
      status: 'ready',
      account: { username: 'lojaexemplo' },
      comments: [],
      total: 0,
      next_cursor: null,
    });
    flags.value = {
      meta_ads_gestao: true,
      meta_ads_comentarios_instagram: true,
    };
    const on = await mountDetail();
    expect(on.find('[data-ad-comments]').exists()).toBe(true);
    expect(on.find('[data-ad-comments-empty]').exists()).toBe(true);
  });

  // #2358: entrar de novo com o Instagram pede integration_manage e inbox_manage; a aba recebe essa régua ligada às
  // permissões reais.
  it('wires the Instagram login rule to integration_manage and inbox_manage (#2358)', async () => {
    flags.value = {
      meta_ads_gestao: true,
      meta_ads_comentarios_instagram: true,
    };

    const canLogIn = async (deniedKeys, status) => {
      deniedKeys.forEach(key => negadas.add(key));
      const wrapper = await mountDetail();
      const [instagram] = wrapper.findComponent(MetaAdsComments).props('abas');
      const allowed = instagram.podeEntrar(status);
      negadas.clear();
      wrapper.unmount();
      return allowed;
    };

    expect(await canLogIn([], 'needs_login')).toBe(true);
    expect(await canLogIn(['integration_manage'], 'needs_login')).toBe(false);
    expect(await canLogIn(['inbox_manage'], 'needs_login')).toBe(false);
    expect(await canLogIn(['integration_manage'], 'not_connected')).toBe(true);
  });

  it('lets only who has inbox_manage connect the Page to Messenger (#2359)', async () => {
    flags.value = {
      meta_ads_gestao: true,
      meta_ads_comentarios_instagram: true,
    };
    expect(
      (await mountDetail())
        .findComponent(MetaAdsComments)
        .props('canCreateInbox')
    ).toBe(true);

    negadas.add('inbox_manage');
    const sem = await mountDetail();
    negadas.clear();
    expect(sem.findComponent(MetaAdsComments).props()).toMatchObject({
      canCreateInbox: false,
      canManage: true,
    });
  });

  // #2335 — anúncio que nunca rodou ou parou antes do período: sem números, mas a conexão lê o anúncio ao vivo.
  const COMMENT_FLAGS = {
    meta_ads_gestao: true,
    meta_ads_comentarios_instagram: true,
  };
  const READY = {
    status: 'ready',
    account: { username: 'lojaexemplo' },
    comments: [],
    total: 0,
    next_cursor: null,
  };

  it('without numbers but with the ad read from Meta, keeps the empty notice and shows status, post and comments (#2335)', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(answer(null));
    comentariosInstagram.listar.mockResolvedValue(READY);
    lerGestao.mockResolvedValue({
      name: 'Anúncio do post',
      status: 'PAUSED',
      effective_status: 'PAUSED',
      can_change: true,
      needs_login: false,
      post: { message: 'Texto do post', reactions: 0, comments: 1, shares: 0 },
    });
    flags.value = COMMENT_FLAGS;
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-detail-empty]').exists()).toBe(true);
    expect(
      wrapper.find('[data-ad-detail-gestao] [data-ad-status]').exists()
    ).toBe(true);
    // A confirmação de pausar e ativar diz o nome, que aqui vem da Meta.
    expect(wrapper.findComponent(MetaAdsAdStatus).props('adName')).toBe(
      'Anúncio do post'
    );
    expect(wrapper.find('[data-ad-post-message]').text()).toBe('Texto do post');
    expect(wrapper.find('[data-ad-comments]').exists()).toBe(true);
  });

  it('without numbers and without the ad read from Meta, shows only the empty notice (#2335)', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(answer(null));
    lerGestao.mockResolvedValue(null);
    flags.value = COMMENT_FLAGS;
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-detail-empty]').exists()).toBe(true);
    expect(wrapper.find('[data-ad-detail-gestao]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-comments]').exists()).toBe(false);
  });

  it('an ad without connection (no spend) shows no comments, unless Meta reads it live (#1960, #2335)', async () => {
    CrmMetaAdsConnectionAPI.panelAd.mockResolvedValue(
      answer({ ...AD, spend: null, people: [] })
    );
    comentariosInstagram.listar.mockResolvedValue(READY);
    lerGestao.mockResolvedValue(null);
    flags.value = COMMENT_FLAGS;
    const without = await mountDetail();
    expect(without.find('[data-ad-comments]').exists()).toBe(false);
    without.unmount();

    lerGestao.mockResolvedValue({
      status: 'ACTIVE',
      effective_status: 'ACTIVE',
    });
    const read = await mountDetail();
    expect(read.find('[data-ad-comments]').exists()).toBe(true);
  });

  it('without the meta_ads_gestao flag, asks nothing about the ad and shows no status or post (#2161)', async () => {
    const wrapper = await mountDetail();

    expect(lerGestao).not.toHaveBeenCalled();
    expect(wrapper.find('[data-ad-status]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-post]').exists()).toBe(false);
  });

  it('with the flag, shows the status in the hero and the Page post under the image (#2161)', async () => {
    flags.value = { meta_ads_gestao: true };
    lerGestao.mockResolvedValue({
      status: 'ACTIVE',
      effective_status: 'ACTIVE',
      can_change: true,
      needs_login: false,
      post: { message: 'Texto do post', reactions: 3, comments: 1, shares: 0 },
    });
    const wrapper = await mountDetail();

    expect(lerGestao).toHaveBeenCalledWith('1');
    expect(
      wrapper.find('[data-ad-detail-hero] [data-ad-status]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-ad-post-message]').text()).toBe('Texto do post');
  });

  it('without the meta_ads_criar flag, reads no budget and shows no budget card (#2198)', async () => {
    flags.value = { meta_ads_gestao: true };
    lerGestao.mockResolvedValue({
      status: 'PAUSED',
      effective_status: 'PAUSED',
      can_change: true,
    });
    const wrapper = await mountDetail();

    expect(CrmMetaAdsConnectionAPI.adBudget).not.toHaveBeenCalled();
    expect(wrapper.find('[data-ad-budget]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(true);
  });

  it('with meta_ads_criar, shows the budget and dates of the ad (#2198)', async () => {
    flags.value = { meta_ads_criar: true };
    CrmMetaAdsConnectionAPI.adBudget.mockResolvedValue({
      data: {
        budget: {
          level: 'adset',
          object_name: 'Público',
          kind: 'daily',
          amount: 30,
          currency: 'BRL',
          start_time: '2026-10-01T09:00:00-0300',
          end_time: null,
          ads_count: 1,
          active_ads_count: 0,
          min_daily: 6,
          max_daily: 500,
          can_change: true,
        },
      },
    });
    const wrapper = await mountDetail();

    expect(CrmMetaAdsConnectionAPI.adBudget).toHaveBeenCalledWith('1');
    expect(wrapper.find('[data-ad-budget]').exists()).toBe(true);
  });

  it('a failed budget read keeps "Activate" from guessing and offers to try again (#2198)', async () => {
    flags.value = { meta_ads_gestao: true, meta_ads_criar: true };
    lerGestao.mockResolvedValue({
      status: 'PAUSED',
      effective_status: 'PAUSED',
      can_change: true,
    });
    CrmMetaAdsConnectionAPI.adBudget.mockRejectedValue({
      response: { status: 422, data: { error: 'meta_unavailable' } },
    });
    const wrapper = await mountDetail();

    expect(wrapper.find('[data-ad-budget]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-budget-failed]').exists()).toBe(true);

    await wrapper.find('[data-ad-status-budget-retry]').trigger('click');
    await flushPromises();
    expect(CrmMetaAdsConnectionAPI.adBudget).toHaveBeenCalledTimes(2);
  });
});
