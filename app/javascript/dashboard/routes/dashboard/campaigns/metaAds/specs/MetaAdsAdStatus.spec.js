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
    expect(wrapper.emitted('changed')).toEqual([['PAUSED']]);
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
