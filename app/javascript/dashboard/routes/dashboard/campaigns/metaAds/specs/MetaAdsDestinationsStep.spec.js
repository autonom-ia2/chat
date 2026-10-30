import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsDestinationsStep from '../components/MetaAdsDestinationsStep.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Destino (#2338): a página do site é ligada ali mesmo, sem ir a Links e QR codes. As páginas vêm de Anúncios
// (meta_ads_view); o resultado por campanha só vem para quem tem campaign_view.
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { sitePages: vi.fn(), updateDestinations: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => false) };
});

const PAGE = {
  id: 9,
  name: 'Site loja.com.br',
  usage: 'website',
  allowed_origins: ['https://loja.com.br'],
  ad_url_params: 'utm_source=meta',
};
const mountStep = async (destinations = { whatsapp: true, site: true }) => {
  const wrapper = mount(MetaAdsDestinationsStep, {
    props: { destinations },
    global: {
      mocks: { $t: key => key },
      stubs: {
        MetaAdsSiteLinkDialog: {
          name: 'MetaAdsSiteLinkDialog',
          emits: ['created'],
          template: '<div data-dialog-stub />',
          methods: { open: vi.fn() },
        },
        MetaAdsSitePage: {
          props: ['page'],
          template: '<li data-site-page-stub>{{ page.name }}</li>',
        },
        MetaAdsDestinationArt: true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('MetaAdsDestinationsStep · página do site', () => {
  beforeEach(() => vi.clearAllMocks());

  it('with no page linked, offers to link one right here', async () => {
    CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
      data: { payload: [] },
    });
    const wrapper = await mountStep();

    expect(wrapper.find('[data-site-empty]').exists()).toBe(true);
    expect(wrapper.find('[data-site-link-open]').exists()).toBe(true);
    expect(wrapper.find('a[href*="links"]').exists()).toBe(false);
  });

  // Uma ação principal por tela (#2338): o principal é "Salvar e continuar"; ligar a página é secundário.
  it('keeps "Save and continue" as the only main button', async () => {
    CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
      data: { payload: [] },
    });
    const wrapper = await mountStep();

    expect(
      wrapper.findComponent('[data-site-link-open]').props('variant')
    ).toBe('outline');
    expect(
      wrapper.findComponent('[data-save-destinations]').props('variant')
    ).not.toBe('outline');
  });

  it('shows the new page in the list and tells the page it was linked', async () => {
    CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
      data: { payload: [] },
    });
    const wrapper = await mountStep();

    wrapper
      .findComponent({ name: 'MetaAdsSiteLinkDialog' })
      .vm.$emit('created', PAGE);
    await flushPromises();

    expect(wrapper.find('[data-site-empty]').exists()).toBe(false);
    expect(wrapper.get('[data-site-page-stub]').text()).toBe(
      'Site loja.com.br'
    );
    expect(wrapper.find('[data-site-link-another]').exists()).toBe(true);
    expect(wrapper.emitted('pageLinked')).toHaveLength(1);
  });

  it('lists the pages that come from Anúncios', async () => {
    CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
      data: { payload: [PAGE] },
    });
    const wrapper = await mountStep();

    expect(CrmMetaAdsConnectionAPI.sitePages).toHaveBeenCalled();
    expect(wrapper.findAll('[data-site-page-stub]')).toHaveLength(1);
  });

  it('does not offer to link a page while the pages are still loading', async () => {
    let finish;
    CrmMetaAdsConnectionAPI.sitePages.mockReturnValue(
      new Promise(resolve => {
        finish = resolve;
      })
    );
    const wrapper = await mountStep();

    expect(wrapper.find('[data-site-empty]').exists()).toBe(false);
    expect(wrapper.find('[data-site-link-open]').exists()).toBe(false);

    finish({ data: { payload: [] } });
    await flushPromises();

    expect(wrapper.find('[data-site-empty]').exists()).toBe(true);
  });

  // Falha ao carregar não é "nenhuma página": oferecer ligar ali criaria uma página repetida.
  it('says the pages did not load and tries again, without offering to link a new one', async () => {
    CrmMetaAdsConnectionAPI.sitePages.mockRejectedValueOnce(new Error('x'));
    const wrapper = await mountStep();

    expect(wrapper.find('[data-site-load-error]').exists()).toBe(true);
    expect(wrapper.find('[data-site-empty]').exists()).toBe(false);
    expect(wrapper.find('[data-site-link-open]').exists()).toBe(false);

    CrmMetaAdsConnectionAPI.sitePages.mockResolvedValue({
      data: { payload: [PAGE] },
    });
    await wrapper.get('[data-site-retry]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-site-load-error]').exists()).toBe(false);
    expect(wrapper.findAll('[data-site-page-stub]')).toHaveLength(1);
  });
});
