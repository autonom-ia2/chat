import { computed, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import MetaAdsSiteLinkDialog from '../components/MetaAdsSiteLinkDialog.vue';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';

// Destino (#2338): ligar a página do site ali mesmo. A pessoa só cola o endereço; o nome sai do endereço e o WhatsApp
// é o da conta (com mais de um, ela escolhe).
const whatsapps = ref([{ id: 38, name: 'WhatsApp Vendas' }]);
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => computed(() => whatsapps.value),
}));
vi.mock('dashboard/api/crmMetaAdsConnection', () => ({
  default: { createSitePage: vi.fn() },
}));

const KEY = 'CRM_KANBAN.META_ADS_HUB.DESTINATIONS.LINK_DIALOG';
const mountDialog = async () => {
  const wrapper = mount(MetaAdsSiteLinkDialog, {
    attachTo: document.body,
    global: {
      mocks: { $t: key => key },
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        ChoiceSelect: {
          props: ['modelValue'],
          emits: ['update:modelValue'],
          template:
            '<button type="button" class="choice" @click="$emit(\'update:modelValue\', 39)" />',
        },
      },
    },
  });
  wrapper.vm.open();
  await flushPromises();
  return wrapper;
};
const confirm = wrapper =>
  wrapper
    .findAll('button')
    .find(button => button.text().includes(`${KEY}.SAVE`));

describe('MetaAdsSiteLinkDialog', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  beforeEach(() => {
    vi.clearAllMocks();
    whatsapps.value = [{ id: 38, name: 'WhatsApp Vendas' }];
  });

  it('links the page from an address without https, named after the site, on the only WhatsApp', async () => {
    const page = { id: 9, name: 'Site loja.com.br', usage: 'website' };
    CrmMetaAdsConnectionAPI.createSitePage.mockResolvedValue({
      data: { payload: page },
    });
    const wrapper = await mountDialog();

    await wrapper
      .get('[data-site-link-address]')
      .setValue('loja.com.br/promocao');
    expect(wrapper.find('.choice').exists()).toBe(false);
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.createSitePage).toHaveBeenCalledWith({
      name: `${KEY}.NAME`,
      inbox_id: 38,
      allowed_origins: ['https://loja.com.br'],
    });
    expect(wrapper.emitted('created')).toEqual([[page]]);
    wrapper.unmount();
  });

  it('asks which WhatsApp when the account has more than one', async () => {
    whatsapps.value = [
      { id: 38, name: 'WhatsApp Vendas' },
      { id: 39, name: 'WhatsApp Loja' },
    ];
    CrmMetaAdsConnectionAPI.createSitePage.mockResolvedValue({
      data: { payload: { id: 9 } },
    });
    const wrapper = await mountDialog();
    await wrapper.get('[data-site-link-address]').setValue('loja.com.br');

    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
    await wrapper.get('.choice').trigger('click');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(CrmMetaAdsConnectionAPI.createSitePage).toHaveBeenCalledWith(
      expect.objectContaining({ inbox_id: 39 })
    );
    wrapper.unmount();
  });

  it('says so when the address is not a site and does not save', async () => {
    const wrapper = await mountDialog();
    const field = wrapper.get('[data-site-link-address]');

    await field.setValue('não sei');
    await field.trigger('blur');

    expect(wrapper.text()).toContain(`${KEY}.ADDRESS_ERROR`);
    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
    expect(CrmMetaAdsConnectionAPI.createSitePage).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('keeps the window open with a message when linking fails', async () => {
    CrmMetaAdsConnectionAPI.createSitePage.mockRejectedValue(new Error('x'));
    const wrapper = await mountDialog();
    await wrapper.get('[data-site-link-address]').setValue('loja.com.br');
    await confirm(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain(`${KEY}.ERROR`);
    expect(wrapper.emitted('created')).toBeUndefined();
    wrapper.unmount();
  });

  it('says a WhatsApp is needed first when the account has none, and does not save', async () => {
    whatsapps.value = [];
    const wrapper = await mountDialog();
    await wrapper.get('[data-site-link-address]').setValue('loja.com.br');

    expect(wrapper.get('[data-site-link-no-whatsapp]').text()).toContain(
      `${KEY}.NO_WHATSAPP`
    );
    expect(confirm(wrapper).attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });
});
