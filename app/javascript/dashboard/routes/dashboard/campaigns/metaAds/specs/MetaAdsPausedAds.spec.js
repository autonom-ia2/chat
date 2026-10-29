import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsPausedAds from '../components/MetaAdsPausedAds.vue';
import MetaAdsBudget from '../components/MetaAdsBudget.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { pausedAds: vi.fn(), updateAdBudget: vi.fn(), adBudget: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const AD = {
  ad_id: '120000000000990001',
  name: 'Bolo',
  created_at: '2026-10-27T10:00:00-03:00',
  budget: { kind: 'daily', amount: 20, currency: 'BRL', active_ads_count: 0 },
};

// A situação do anúncio fica de fora: aqui só o que ela conta à lista.
const StatusStub = {
  props: ['adId'],
  emits: ['changed'],
  template:
    "<button data-status-stub @click=\"$emit('changed', 'ACTIVE', { status: 'ACTIVE' })\" />",
};

// Conta as aberturas: a confirmação de ativar só abre com o orçamento de agora lido.
const dialogs = { opened: 0 };
const DialogStub = {
  props: ['confirmButtonLabel', 'description'],
  emits: ['confirm'],
  methods: {
    open() {
      dialogs.opened += 1;
    },
    close() {},
  },
  template:
    '<div data-dialog :data-description="description"><slot /><button data-confirm @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
};

describe('Anúncios da Meta · pausados esperando ativar (#2198)', () => {
  const mountList = () =>
    mount(MetaAdsPausedAds, {
      global: {
        mocks: { $t: key => key },
        stubs: { MetaAdsAdStatus: StatusStub },
      },
    });

  it('lists the paused ads created here and tells the panel how many', async () => {
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [AD] },
    });
    const wrapper = mountList();
    await flushPromises();

    expect(wrapper.find(`[data-panel-paused-ad="${AD.ad_id}"]`).exists()).toBe(
      true
    );
    expect(wrapper.emitted('count')).toEqual([[1]]);
  });

  // Com a situação de verdade: o "Ativar" de cada linha.
  const mountWithStatus = () =>
    mount(MetaAdsPausedAds, {
      global: { mocks: { $t: key => key }, stubs: { Dialog: DialogStub } },
    });
  const STATUS = 'CRM_KANBAN.META_ADS_HUB.GESTAO.STATUS';
  // Orçamento de agora diferente do de quando foi criado: total, não por dia.
  const NOW = {
    level: 'adset',
    object_name: 'Bolo',
    kind: 'lifetime',
    amount: 900,
    currency: 'BRL',
    start_time: '2026-10-27T00:00:00-0300',
    end_time: '2026-11-30T23:59:00-0300',
    ads_count: 1,
    active_ads_count: 0,
  };

  // #2354: anúncio pausado que a Meta ainda analisa. A linha diz isso e não oferece ativar; a mesma regra do detalhe.
  it('an ad under Meta review shows the review note instead of the turn-on button', async () => {
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [{ ...AD, in_review: true }] },
    });
    const wrapper = mountWithStatus();
    await flushPromises();

    const row = wrapper.find(`[data-panel-paused-ad="${AD.ad_id}"]`);
    expect(row.find('[data-ad-status-review]').exists()).toBe(true);
    expect(row.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(wrapper.emitted('count')).toEqual([[1]]);
  });

  it('a ready ad keeps the turn-on button and no review note', async () => {
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [{ ...AD, in_review: false }] },
    });
    const wrapper = mountWithStatus();
    await flushPromises();

    const row = wrapper.find(`[data-panel-paused-ad="${AD.ad_id}"]`);
    expect(row.find('[data-ad-status-toggle]').exists()).toBe(true);
    expect(row.find('[data-ad-status-review]').exists()).toBe(false);
  });

  it('opening the list reads no budget and shows the amount from when it was created', async () => {
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [AD, { ...AD, ad_id: '120000000000990002' }] },
    });
    const wrapper = mountWithStatus();
    await flushPromises();

    expect(wrapper.findAll('[data-panel-paused-ad]')).toHaveLength(2);
    expect(wrapper.text()).toContain(
      'CRM_KANBAN.META_ADS_HUB.CRIAR.PAUSED_LIST.LINE'
    );
    expect(CrmMetaAdsConnectionAPI.adBudget).not.toHaveBeenCalled();
  });

  it('tapping "Activate" reads the budget now, waits, then confirms with it', async () => {
    dialogs.opened = 0;
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [AD] },
    });
    let answer;
    CrmMetaAdsConnectionAPI.adBudget.mockReturnValue(
      new Promise(resolve => {
        answer = resolve;
      })
    );
    const wrapper = mountWithStatus();
    await flushPromises();

    await wrapper.find('[data-ad-status-toggle]').trigger('click');
    expect(CrmMetaAdsConnectionAPI.adBudget).toHaveBeenCalledTimes(1);
    expect(CrmMetaAdsConnectionAPI.adBudget).toHaveBeenCalledWith(AD.ad_id);
    const toggle = wrapper.find('[data-ad-status-toggle]');
    expect(toggle.attributes('disabled')).toBeDefined();
    expect(toggle.attributes('aria-busy')).toBe('true');
    expect(wrapper.find('[data-ad-status-budget-pending]').exists()).toBe(true);
    expect(dialogs.opened).toBe(0);

    answer({ data: { budget: NOW } });
    await flushPromises();

    expect(dialogs.opened).toBe(1);
    expect(wrapper.find('[data-dialog]').attributes('data-description')).toBe(
      `${STATUS}.ACTIVATE_SPEND_TOTAL`
    );
    expect(wrapper.find('[data-confirm]').text()).toBe(
      `${STATUS}.ACTIVATE_SPEND_BUTTON`
    );
  });

  it('a failed read does not open the confirmation and offers to try again', async () => {
    dialogs.opened = 0;
    CrmMetaAdsConnectionAPI.pausedAds.mockResolvedValue({
      data: { ads: [AD] },
    });
    CrmMetaAdsConnectionAPI.adBudget
      .mockRejectedValueOnce({ response: { status: 422 } })
      .mockResolvedValueOnce({ data: { budget: NOW } });
    const wrapper = mountWithStatus();
    await flushPromises();

    await wrapper.find('[data-ad-status-toggle]').trigger('click');
    await flushPromises();

    expect(dialogs.opened).toBe(0);
    expect(wrapper.find('[data-ad-status-toggle]').exists()).toBe(false);
    expect(wrapper.find('[data-ad-status-budget-failed]').text()).toBe(
      `${STATUS}.BUDGET_FAILED`
    );

    await wrapper.find('[data-ad-status-budget-retry]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.adBudget).toHaveBeenCalledTimes(2);
    expect(dialogs.opened).toBe(1);
  });

  it('after activating, reads the list again and the ad leaves it', async () => {
    CrmMetaAdsConnectionAPI.pausedAds
      .mockResolvedValueOnce({ data: { ads: [AD] } })
      .mockResolvedValueOnce({ data: { ads: [] } });
    const wrapper = mountList();
    await flushPromises();

    await wrapper.find('[data-status-stub]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.pausedAds).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-panel-paused-ad]').exists()).toBe(false);
    expect(wrapper.emitted('count')).toEqual([[1], [0]]);
  });

  it('a failed read says so and lets the person try again', async () => {
    CrmMetaAdsConnectionAPI.pausedAds
      .mockRejectedValueOnce(new Error('meta_unavailable'))
      .mockResolvedValueOnce({ data: { ads: [AD] } });
    const wrapper = mountList();
    await flushPromises();

    await wrapper.find('[data-panel-paused-retry]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-panel-paused-ad]').exists()).toBe(true);
  });
});

describe('Anúncios da Meta · orçamento e datas do anúncio (#2198)', () => {
  const BUDGET = {
    level: 'adset',
    object_name: 'Público 25-45',
    kind: 'daily',
    amount: 30,
    currency: 'BRL',
    start_time: '2026-10-01T09:00:00-0300',
    end_time: null,
    ads_count: 2,
    active_ads_count: 1,
    min_daily: 6,
    max_daily: 500,
    can_change: true,
  };
  const KEY = 'CRM_KANBAN.META_ADS_HUB.GESTAO.BUDGET';
  const mountBudget = (props = {}) =>
    mount(MetaAdsBudget, {
      props: { adId: '5', budget: BUDGET, canManage: true, ...props },
      global: {
        mocks: { $t: key => key },
        stubs: { Dialog: DialogStub, Button: true },
      },
    });

  it('only who can manage, with a token that can change, sees "Change"', () => {
    expect(mountBudget().find('[data-ad-budget-edit]').exists()).toBe(true);
    expect(
      mountBudget({ canManage: false }).find('[data-ad-budget-edit]').exists()
    ).toBe(false);
    expect(
      mountBudget({ budget: { ...BUDGET, can_change: false } })
        .find('[data-ad-budget-edit]')
        .exists()
    ).toBe(false);
  });

  it('confirms the new amount and sends it with the end date to the server', async () => {
    CrmMetaAdsConnectionAPI.updateAdBudget.mockResolvedValue({
      data: { budget: { ...BUDGET, amount: 45 } },
    });
    const wrapper = mountBudget();
    await wrapper.find('[data-ad-budget-edit]').trigger('click');
    await wrapper.find('input[data-ad-budget-input]').setValue('45.00');

    await wrapper.find('[data-confirm]').trigger('click');
    expect(wrapper.find('[data-ad-budget-review]').exists()).toBe(true);
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    // Texto decimal do jeito que a pessoa digitou, sem passar por float.
    expect(CrmMetaAdsConnectionAPI.updateAdBudget).toHaveBeenCalledWith('5', {
      amount: '45.00',
      end_time: null,
    });
    expect(wrapper.emitted('changed')).toEqual([
      [{ ...BUDGET, amount: 45, amount_cents: 4500 }],
    ]);
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.DONE`);
  });

  it('with an end date already set, offers only to change it, never "no end date"', async () => {
    const wrapper = mountBudget({
      budget: { ...BUDGET, end_time: '2099-11-30T23:59:00-0300' },
    });
    await wrapper.find('[data-ad-budget-edit]').trigger('click');

    expect(wrapper.find('[data-end-date-option="NONE"]').exists()).toBe(false);
    expect(wrapper.find('[data-end-date-option="PICK"]').exists()).toBe(true);
    expect(mountBudget().find('[data-end-date-option="NONE"]').exists()).toBe(
      true
    );
  });

  it('a total budget is capped at the daily limit times the days left', async () => {
    const wrapper = mountBudget({
      budget: {
        ...BUDGET,
        kind: 'lifetime',
        amount: 900,
        start_time: '2020-01-01T00:00:00-0300',
        end_time: '2099-01-01T23:59:00-0300',
      },
    });
    await wrapper.find('[data-ad-budget-edit]').trigger('click');
    await wrapper.find('[data-end-date-option="D7"]').trigger('click');
    await wrapper.find('input[data-ad-budget-input]').setValue('3600.00');

    expect(wrapper.text()).toContain(`${KEY}.ERRORS.TOTAL_MAX`);

    await wrapper.find('input[data-ad-budget-input]').setValue('3500.00');
    expect(wrapper.text()).not.toContain(`${KEY}.ERRORS.TOTAL_MAX`);

    // A conta é em centavos inteiros: um centavo acima do teto já passa do "no máximo".
    await wrapper.find('input[data-ad-budget-input]').setValue('3500,01');
    expect(wrapper.text()).toContain(`${KEY}.ERRORS.TOTAL_MAX`);
  });

  it.each([
    ['cannot_clear_end', 'CANNOT_CLEAR_END'],
    ['meta_partial', 'META_PARTIAL'],
    ['invalid_amount', 'INVALID_AMOUNT'],
  ])('a %s refusal says what happened', async (code, message) => {
    CrmMetaAdsConnectionAPI.updateAdBudget.mockRejectedValue({
      response: { status: 422, data: { error: code } },
    });
    const wrapper = mountBudget();
    await wrapper.find('[data-ad-budget-edit]').trigger('click');
    await wrapper.find('input[data-ad-budget-input]').setValue('45.00');
    await wrapper.find('[data-confirm]').trigger('click');
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(`${KEY}.FAILURES.${message}`);
  });

  it('a refusal keeps the budget and warns', async () => {
    CrmMetaAdsConnectionAPI.updateAdBudget.mockRejectedValue({
      response: { status: 422, data: { error: 'meta_refused' } },
    });
    const wrapper = mountBudget();
    await wrapper.find('[data-ad-budget-edit]').trigger('click');
    await wrapper.find('input[data-ad-budget-input]').setValue('45.00');
    await wrapper.find('[data-confirm]').trigger('click');
    await wrapper.find('[data-confirm]').trigger('click');
    await flushPromises();

    expect(wrapper.emitted('changed')).toBeUndefined();
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.ERROR`);
  });
});
