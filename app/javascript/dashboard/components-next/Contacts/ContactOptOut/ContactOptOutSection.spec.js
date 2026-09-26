import { mount, flushPromises } from '@vue/test-utils';
import ContactOptOutSection from './ContactOptOutSection.vue';

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
  props: ['title', 'description', 'confirmButtonLabel'],
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

const mountSection = contact =>
  mount(ContactOptOutSection, {
    props: { contact },
    global: { stubs: { Dialog: DialogStub } },
  });

const PREFIX = 'CONTACTS_LAYOUT.DETAILS.OPT_OUT';

describe('ContactOptOutSection', () => {
  beforeEach(() => {
    dispatch.mockReset();
    alert.mockReset();
  });

  it('sem recusa não mostra o selo e oferece marcar', () => {
    const wrapper = mountSection({ id: 7, optedOutAt: null });

    expect(wrapper.find('[data-test="opt-out-badge"]').exists()).toBe(false);
    expect(wrapper.get('[data-test="opt-out-action"]').text()).toContain(
      `${PREFIX}.MARK`
    );
    expect(wrapper.get('[data-test="dialog"]').attributes('data-title')).toBe(
      `${PREFIX}.MARK_DIALOG.TITLE`
    );
  });

  it('com recusa mostra o selo com a origem e oferece desfazer', () => {
    const wrapper = mountSection({
      id: 7,
      optedOutAt: 1790000000,
      optOutSource: 'email_unsubscribe',
    });

    expect(wrapper.get('[data-test="opt-out-badge"]').text()).toContain(
      `${PREFIX}.BADGE`
    );
    expect(wrapper.get('[data-test="opt-out-details"]').exists()).toBe(true);
    expect(wrapper.get('[data-test="opt-out-action"]').text()).toContain(
      `${PREFIX}.UNDO`
    );
    expect(wrapper.get('[data-test="dialog"]').attributes('data-title')).toBe(
      `${PREFIX}.UNDO_DIALOG.TITLE`
    );
  });

  it('confirmar marca a recusa pelo store e avisa', async () => {
    dispatch.mockResolvedValue();
    const wrapper = mountSection({ id: 7, optedOutAt: null });

    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/setOptOut', {
      id: 7,
      optedOut: true,
    });
    expect(alert).toHaveBeenCalledWith(`${PREFIX}.API.MARK_SUCCESS`);
  });

  it('confirmar o desfazer tira a recusa e, se falhar, avisa o erro', async () => {
    dispatch.mockRejectedValue(new Error('falhou'));
    const wrapper = mountSection({
      id: 7,
      optedOutAt: 1790000000,
      optOutSource: 'manual',
    });

    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('contacts/setOptOut', {
      id: 7,
      optedOut: false,
    });
    expect(alert).toHaveBeenCalledWith(`${PREFIX}.API.ERROR`);
  });
});
