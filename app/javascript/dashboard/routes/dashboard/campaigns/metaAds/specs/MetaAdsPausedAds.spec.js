import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsPausedAds from '../components/MetaAdsPausedAds.vue';
import MetaAdsBudget from '../components/MetaAdsBudget.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { pausedAds: vi.fn(), updateAdBudget: vi.fn() },
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

const DialogStub = {
  props: ['confirmButtonLabel'],
  emits: ['confirm'],
  methods: { open() {}, close() {} },
  template:
    '<div data-dialog><slot /><button data-confirm @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
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

    expect(CrmMetaAdsConnectionAPI.updateAdBudget).toHaveBeenCalledWith('5', {
      amount: 45,
      end_time: null,
    });
    expect(wrapper.emitted('changed')).toEqual([[{ ...BUDGET, amount: 45 }]]);
    expect(useAlert).toHaveBeenCalledWith(`${KEY}.DONE`);
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
