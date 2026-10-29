import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAdStatus from '../components/MetaAdsAdStatus.vue';
import { mudarStatus } from '../gestaoDoAnuncio';
import { useAlert } from 'dashboard/composables';

vi.mock('../gestaoDoAnuncio', () => ({ mudarStatus: vi.fn() }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS';

// O Dialog real abre um <dialog> nativo; aqui ele só mostra o conteúdo e confirma pelo botão.
const DialogStub = {
  props: ['title', 'confirmButtonLabel'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-dialog><button data-confirm @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
};

const GESTAO = {
  status: 'ACTIVE',
  effective_status: 'ACTIVE',
  can_change: true,
  needs_login: false,
};

const mountStatus = (props = {}) =>
  mount(MetaAdsAdStatus, {
    props: {
      adId: '1',
      adName: 'Capa',
      gestao: GESTAO,
      canManage: true,
      ...props,
    },
    global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
  });

describe('Anúncios da Meta · situação do anúncio (#2161)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('shows Running and offers to pause; confirming pauses and tells the page', async () => {
    mudarStatus.mockResolvedValue({ status: 'PAUSED' });
    const wrapper = mountStatus();

    expect(wrapper.find('[data-ad-status-badge]').text()).toBe(`${KEY}.ACTIVE`);
    expect(wrapper.find('[data-ad-status-toggle]').text()).toBe(`${KEY}.PAUSE`);

    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(mudarStatus).toHaveBeenCalledWith('1', 'PAUSED');
    expect(wrapper.emitted('changed')).toEqual([
      ['PAUSED', { status: 'PAUSED' }],
    ]);
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.PAUSE_DONE`);
  });

  it('an active ad whose ad set is paused is Not running, and pausing still applies', () => {
    const wrapper = mountStatus({
      gestao: { ...GESTAO, effective_status: 'ADSET_PAUSED' },
    });

    expect(wrapper.find('[data-status]').attributes('data-status')).toBe('OFF');
    expect(wrapper.find('[data-ad-status-toggle]').text()).toBe(`${KEY}.PAUSE`);
  });

  it('an archived ad is Not running and has no button', () => {
    const wrapper = mountStatus({ gestao: { ...GESTAO, status: 'ARCHIVED' } });

    expect(wrapper.find('[data-status]').attributes('data-status')).toBe('OFF');
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(false);
  });

  it('a paused ad offers to turn on', () => {
    const wrapper = mountStatus({ gestao: { ...GESTAO, status: 'PAUSED' } });

    expect(wrapper.find('[data-ad-status-badge]').text()).toBe(`${KEY}.PAUSED`);
    expect(wrapper.find('[data-ad-status-toggle]').text()).toBe(
      `${KEY}.ACTIVATE`
    );
  });

  it('without meta_ads_manage, or in partner mode, shows the status without the button', () => {
    expect(
      mountStatus({ canManage: false }).find('[data-ad-status-toggle]').exists()
    ).toBe(false);
    expect(
      mountStatus({ gestao: { ...GESTAO, can_change: false } })
        .find('[data-ad-status-toggle]')
        .exists()
    ).toBe(false);
  });

  it('a token without permission says how to unlock it instead of hiding the reason', () => {
    const wrapper = mountStatus({
      gestao: { ...GESTAO, can_change: false, needs_login: true },
    });

    expect(wrapper.find('[data-ad-status-login]').text()).toBe(
      `${KEY}.NEEDS_LOGIN`
    );
  });

  it('activating says it started when nothing holds the ad (#2198)', async () => {
    mudarStatus.mockResolvedValue({ status: 'ACTIVE', held_by: null });
    const wrapper = mountStatus({ gestao: { ...GESTAO, status: 'PAUSED' } });

    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.ACTIVATE_DONE`);
  });

  it('activating warns when the campaign or the ad set paused at Meta still holds the ad (#2198)', async () => {
    mudarStatus.mockResolvedValue({ status: 'ACTIVE', held_by: 'campaign' });
    const wrapper = mountStatus({ gestao: { ...GESTAO, status: 'PAUSED' } });

    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.HELD.CAMPAIGN`);
    expect(useAlert).not.toHaveBeenCalledWith(`${KEY}.ACTIVATE_DONE`);
    expect(wrapper.emitted('changed')).toEqual([
      ['ACTIVE', { status: 'ACTIVE', held_by: 'campaign' }],
    ]);

    mudarStatus.mockResolvedValue({ status: 'ACTIVE', held_by: 'adset' });
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.HELD.ADSET`);
  });

  it('with the budget read, activating says how much it will spend (#2198)', () => {
    const wrapper = mountStatus({
      gestao: { ...GESTAO, status: 'PAUSED' },
      budget: { kind: 'daily', amount: 20, currency: 'BRL', end_time: null },
      budgetState: 'ok',
    });

    expect(wrapper.find('[data-confirm]').text()).toBe(
      `${KEY}.ACTIVATE_SPEND_BUTTON`
    );
  });

  it('activating waits for the budget, and a failed read offers to try again (#2198)', async () => {
    const loading = mountStatus({
      gestao: { ...GESTAO, status: 'PAUSED' },
      budgetState: 'loading',
    });
    expect(
      loading.find('[data-ad-status-toggle]').attributes('disabled')
    ).toBeDefined();
    expect(loading.find('[data-ad-status-budget-pending]').exists()).toBe(true);

    const failed = mountStatus({
      gestao: { ...GESTAO, status: 'PAUSED' },
      budgetState: 'failed',
    });
    expect(failed.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(failed.find('[data-ad-status-budget-failed]').text()).toBe(
      `${KEY}.BUDGET_FAILED`
    );
    await failed.find('[data-ad-status-budget-retry]').trigger('click');
    expect(failed.emitted('retryBudget')).toHaveLength(1);
  });

  // #2354: anúncio pausado em análise da Meta. O servidor recusaria o ligar: no lugar do botão, a mesma frase da lista.
  it('a paused ad under Meta review shows the review note instead of the turn-on button', () => {
    const wrapper = mountStatus({
      gestao: {
        ...GESTAO,
        status: 'PAUSED',
        effective_status: 'IN_PROCESS',
        in_review: true,
      },
    });

    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-review]').text().split(/\s+/)).toEqual(
      [`${KEY}.IN_REVIEW_NOTE`, `${KEY}.IN_REVIEW_NOTE_HINT`]
    );
  });

  it('an ad that is on while Meta reviews a change can still be paused', () => {
    const wrapper = mountStatus({
      gestao: { ...GESTAO, effective_status: 'IN_PROCESS', in_review: false },
    });

    expect(wrapper.find('[data-ad-status-toggle]').text()).toBe(`${KEY}.PAUSE`);
    expect(wrapper.find('[data-ad-status-review]').exists()).toBe(false);
  });

  // #2354: o servidor recusa ligar um anúncio que a Meta ainda analisa.
  it('Meta still reviewing the ad: says so instead of a generic error', async () => {
    mudarStatus.mockRejectedValue({
      response: { data: { error: 'in_review' } },
    });
    const wrapper = mountStatus({
      gestao: { ...GESTAO, status: 'PAUSED', effective_status: 'PAUSED' },
    });

    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.IN_REVIEW`);
  });

  it('a refusal from Meta keeps the status and warns', async () => {
    mudarStatus.mockRejectedValue({
      response: { data: { error: 'meta_refused' } },
    });
    const wrapper = mountStatus();

    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.ERROR`);
  });
});
