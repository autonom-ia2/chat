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

  it('com recusa manual mostra o selo com a origem e oferece desfazer', () => {
    const wrapper = mountSection({
      id: 7,
      optedOutAt: 1790000000,
      optOutSource: 'manual',
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
    expect(wrapper.find('[data-test="opt-out-origin-hint"]').exists()).toBe(
      false
    );
  });

  it.each([
    ['prospecting', 'PROSPECTING'],
    ['email_unsubscribe', 'EMAIL_UNSUBSCRIBE'],
  ])(
    'recusa da origem %s não oferece desfazer aqui e diz onde ela sai',
    (source, key) => {
      const wrapper = mountSection({
        id: 7,
        optedOutAt: 1790000000,
        optOutSource: source,
      });

      expect(wrapper.get('[data-test="opt-out-badge"]').exists()).toBe(true);
      expect(wrapper.find('[data-test="opt-out-action"]').exists()).toBe(false);
      expect(wrapper.find('[data-test="dialog"]').exists()).toBe(false);
      expect(wrapper.get('[data-test="opt-out-origin-hint"]').text()).toBe(
        `${PREFIX}.ORIGIN_HINT.${key}`
      );
    }
  );

  it('desfazer a manual com outra origem ainda valendo avisa que a recusa continua', async () => {
    dispatch.mockResolvedValue({
      id: 7,
      opted_out_at: 1790000000,
      opt_out_source: 'email_unsubscribe',
    });
    const wrapper = mountSection({
      id: 7,
      optedOutAt: 1790000000,
      optOutSource: 'manual',
    });

    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(alert).toHaveBeenCalledWith(`${PREFIX}.API.UNDO_KEPT`);
  });

  it('desfazer a manual sem outra origem avisa que a recusa saiu', async () => {
    dispatch.mockResolvedValue({ id: 7, opted_out_at: null });
    const wrapper = mountSection({
      id: 7,
      optedOutAt: 1790000000,
      optOutSource: 'manual',
    });

    await wrapper.get('[data-test="confirm"]').trigger('click');
    await flushPromises();

    expect(alert).toHaveBeenCalledWith(`${PREFIX}.API.UNDO_SUCCESS`);
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
