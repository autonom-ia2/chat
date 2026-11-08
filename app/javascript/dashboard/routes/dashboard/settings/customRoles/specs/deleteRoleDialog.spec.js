import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { h } from 'vue';
import DeleteRoleDialog from '../component/DeleteRoleDialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2185: excluir uma função com gente pergunta para onde as pessoas vão, e só confirma com a escolha feita.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const dialogCalls = { open: 0, close: 0 };
const DialogStub = {
  props: {
    title: { type: String, default: '' },
    disableConfirmButton: { type: Boolean, default: false },
  },
  emits: ['confirm'],
  setup(props, { expose, emit, slots }) {
    expose({
      open: () => {
        dialogCalls.open += 1;
      },
      close: () => {
        dialogCalls.close += 1;
      },
    });
    return () =>
      h('div', { class: 'dialog-stub' }, [
        h('span', props.title),
        slots.default?.(),
        h('button', {
          class: 'dialog-confirm',
          disabled: props.disableConfirmButton,
          onClick: () => emit('confirm'),
        }),
      ]);
  },
};

const ROLES = [
  { id: 1, name: 'Vendas', permissions: ['crm_view'] },
  { id: 2, name: 'Suporte', permissions: ['conversation_view'] },
  { id: 3, name: 'Caixas', permissions: ['inbox_manage'] },
];

const buildStore = ({ role = 'administrator', permissions = [] } = {}) =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => role,
      getCurrentCustomRoleId: () => (role === 'administrator' ? null : 9),
      getCurrentUser: () => ({
        id: 2,
        accounts: [{ id: 1, custom_role_id: null, permissions }],
      }),
      'customRole/getCustomRoles': () => ROLES,
    },
  });

const mountDialog = async seat => {
  const wrapper = mount(DeleteRoleDialog, {
    global: { plugins: [buildStore(seat)], stubs: { Dialog: DialogStub } },
  });
  wrapper.vm.open(ROLES[0], 2);
  await flushPromises();
  return wrapper;
};

const optionValues = wrapper =>
  wrapper
    .findComponent(ChoiceSelect)
    .props('options')
    .map(option => option.value);

beforeEach(() => {
  dialogCalls.open = 0;
  dialogCalls.close = 0;
});

describe('DeleteRoleDialog', () => {
  it('asks where the people go and blocks the confirmation until a choice', async () => {
    const wrapper = await mountDialog();

    expect(dialogCalls.open).toBe(1);
    expect(wrapper.text()).toContain('CUSTOM_ROLE.DELETE.MOVE.TITLE');
    expect(
      wrapper.find('.dialog-confirm').attributes('disabled')
    ).toBeDefined();

    await wrapper.find('.dialog-confirm').trigger('click');
    expect(wrapper.emitted('confirm')).toBeUndefined();
  });

  it('offers the other roles and no role, never the role being deleted', async () => {
    const wrapper = await mountDialog();

    expect(optionValues(wrapper)).toEqual([2, 3, 'none']);
  });

  it('offers only the roles the person could hand out', async () => {
    const wrapper = await mountDialog({
      role: 'agent',
      permissions: ['custom_role_manage', 'conversation_view'],
    });

    expect(optionValues(wrapper)).toEqual([2, 'none']);
  });

  it('warns what no role means and sends the choice', async () => {
    const wrapper = await mountDialog();

    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'CUSTOM_ROLE.DELETE.MOVE.NO_ROLE_WARNING'
    );
    expect(
      wrapper.find('.dialog-confirm').attributes('disabled')
    ).toBeUndefined();

    await wrapper.find('.dialog-confirm').trigger('click');

    expect(wrapper.emitted('confirm')[0][0]).toEqual({
      role: ROLES[0],
      destinationRoleId: 'none',
    });
  });

  it('sends another role as the destination', async () => {
    const wrapper = await mountDialog();

    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 2);
    await flushPromises();
    await wrapper.find('.dialog-confirm').trigger('click');

    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(wrapper.emitted('confirm')[0][0].destinationRoleId).toBe(2);
  });
});
