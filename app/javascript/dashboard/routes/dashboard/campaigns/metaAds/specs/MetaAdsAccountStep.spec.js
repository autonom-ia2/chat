import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsAccountStep from '../components/MetaAdsAccountStep.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { adAccounts: vi.fn(), pixels: vi.fn(), select: vi.fn() },
}));

const ACCOUNTS = [
  {
    id: '1',
    name: 'Testes',
    currency: 'BRL',
    active: true,
    ready: true,
    spend_30d: 0,
    recommended: false,
  },
  {
    id: '2',
    name: 'CA - Placement',
    currency: 'BRL',
    active: true,
    ready: true,
    spend_30d: 1720,
    recommended: true,
  },
  {
    id: '3',
    name: 'Nova',
    currency: 'BRL',
    active: true,
    ready: false,
    spend_30d: null,
    recommended: false,
  },
];
const PIXELS = [
  { id: '90', name: 'Pixel antigo', last_fired_time: null },
  { id: '91', name: 'Pixel do site', last_fired_time: '2026-10-06T10:00:00Z' },
];

const mountStep = async () => {
  const wrapper = mount(MetaAdsAccountStep, {
    props: { mode: 'partner' },
    global: {
      mocks: { $t: key => key },
      stubs: {
        Button: {
          template: '<button><slot /></button>',
        },
        Spinner: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('Anúncios da Meta · escolher a conta (#1047)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    CrmMetaAdsConnectionAPI.adAccounts.mockResolvedValue({
      data: { ad_accounts: ACCOUNTS },
    });
    CrmMetaAdsConnectionAPI.pixels.mockResolvedValue({
      data: { pixels: PIXELS },
    });
  });

  it('comes with the recommended account and its most recent Pixel chosen', async () => {
    const wrapper = await mountStep();

    expect(wrapper.get('[data-ad-account="2"] input').element.checked).toBe(
      true
    );
    expect(CrmMetaAdsConnectionAPI.pixels).toHaveBeenCalledWith('partner', '2');
    await wrapper.get('[data-pixel-change]').trigger('click');
    expect(wrapper.get('[data-pixel="91"] input').element.checked).toBe(true);
  });

  it('saves the chosen account with the chosen Pixel', async () => {
    CrmMetaAdsConnectionAPI.select.mockResolvedValue({
      data: { configured: true },
    });
    const wrapper = await mountStep();

    await wrapper.get('[data-use-account]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'partner',
      adAccountId: '2',
      pixelId: '91',
    });
    expect(wrapper.emitted('saved')).toHaveLength(1);
  });

  it('an account Meta has not released yet is released first, then its Pixels show up', async () => {
    CrmMetaAdsConnectionAPI.select.mockResolvedValue({
      data: { configured: true },
    });
    const wrapper = await mountStep();

    await wrapper.get('[data-ad-account="3"] input').setValue();
    await flushPromises();
    expect(wrapper.find('[data-pixels]').exists()).toBe(false);

    await wrapper.get('[data-use-account]').trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.select).toHaveBeenCalledWith({
      mode: 'partner',
      adAccountId: '3',
      pixelId: null,
    });
    expect(CrmMetaAdsConnectionAPI.pixels).toHaveBeenLastCalledWith(
      'partner',
      '3'
    );
    expect(wrapper.find('[data-pixels]').exists()).toBe(true);
    expect(wrapper.emitted('saved')).toBeUndefined();
  });

  it('keeps the save error on screen and says which way the account is read (#1068)', async () => {
    CrmMetaAdsConnectionAPI.select.mockRejectedValue({
      response: { data: { error: 'platform_access_pending' } },
    });
    const wrapper = await mountStep();

    expect(wrapper.get('[data-account-mode]').text()).toContain(
      'CRM_KANBAN.META_ADS_HUB.ACCOUNT.VIA_PARTNER'
    );
    await wrapper.get('[data-use-account]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-account-error]').text()).toContain(
      'PLATFORM_ACCESS_PENDING'
    );
    expect(wrapper.emitted('saved')).toBeUndefined();
  });
});
