import { mount, flushPromises } from '@vue/test-utils';
import ContactCustomerSection from './ContactCustomerSection.vue';

const dispatch = vi.fn();
const alert = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: message => alert(message),
}));

const DialogStub = {
  name: 'Dialog',
  props: ['title'],
  emits: ['confirm'],
  setup(_props, { expose }) {
    const open = vi.fn();
    const close = vi.fn();
    expose({ open, close });
    return { open, close };
  },
  template:
    '<div data-test="dialog" :data-title="title"><button data-test="confirm" @click="$emit(\'confirm\')" /></div>',
};

const mountSection = (contact, props = {}) =>
  mount(ContactCustomerSection, {
    props: { contact, ...props },
    global: { stubs: { Dialog: DialogStub } },
  });

const PREFIX = 'CONTACTS_LAYOUT.DETAILS.CUSTOMER';

describe('ContactCustomerSection', () => {
  beforeEach(() => {
    dispatch.mockReset();
    alert.mockReset();
  });

  it('lead não mostra o selo e oferece marcar como cliente', () => {
    const wrapper = mountSection({ id: 7, contactType: 'lead' });

    expect(wrapper.find('[data-test="customer-badge"]').exists()).toBe(false);
    expect(wrapper.get('[data-test="customer-action"]').text()).toContain(
      `${PREFIX}.MARK`
    );
    expect(wrapper.get('[data-test="dialog"]').attributes('data-title')).toBe(
      `${PREFIX}.MARK_DIALOG.TITLE`
    );
  });

  it('cliente mostra o selo com a data e oferece desfazer', () => {
    const wrapper = mountSection({
      id: 7,
      contactType: 'customer',
      customerSince: 1790000000,
    });

    expect(wrapper.get('[data-test="customer-badge"]').text()).toContain(
      `${PREFIX}.SINCE`
    );
    expect(wrapper.get('[data-test="customer-action"]').text()).toContain(
      `${PREFIX}.UNDO`
    );
  });

  it('confirmar marca pelo store e avisa', async () => {
    dispatch.mockResolvedValue({ id: 7, contact_type: 'customer' });
    const wrapper = mountSection({ id: 7, contactType: 'lead' });

    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/setCustomer', {
      id: 7,
      customer: true,
    });
    expect(alert).toHaveBeenCalledWith(`${PREFIX}.API.MARK_SUCCESS`);
  });

  it('somente leitura não oferece ação', () => {
    const wrapper = mountSection(
      { id: 7, contactType: 'lead' },
      { readOnly: true }
    );

    expect(wrapper.find('[data-test="customer-action"]').exists()).toBe(false);
  });
});
