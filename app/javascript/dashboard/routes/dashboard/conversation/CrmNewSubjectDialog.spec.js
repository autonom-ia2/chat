import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CrmNewSubjectDialog from './CrmNewSubjectDialog.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const DialogStub = {
  name: 'Dialog',
  props: ['disableConfirmButton'],
  emits: ['confirm'],
  methods: { open: vi.fn(), close: vi.fn() },
  template: '<div><slot /></div>',
};

const PIPELINES = [
  { id: 1, name: 'Comercial' },
  { id: 2, name: 'Pós-venda' },
];

const setup = () => {
  const store = createStore({
    getters: { 'crmKanban/getPipelines': () => PIPELINES },
  });
  const dispatch = vi
    .spyOn(store, 'dispatch')
    .mockImplementation(action =>
      Promise.resolve(
        action === 'crmKanban/fetchPipelines' ? PIPELINES : { id: 99 }
      )
    );
  const wrapper = mount(CrmNewSubjectDialog, {
    props: { conversationId: 9 },
    global: { plugins: [store], stubs: { Dialog: DialogStub } },
  });
  return { wrapper, dispatch };
};

const dialog = wrapper => wrapper.findComponent({ name: 'Dialog' });
const titleInput = wrapper => wrapper.find('input:not([type="radio"])');

it('always asks for a new card, in the chosen funnel, with the typed subject', async () => {
  const { wrapper, dispatch } = setup();
  await wrapper.vm.open();
  await flushPromises();

  expect(dialog(wrapper).props('disableConfirmButton')).toBe(true);
  await wrapper.findAll('input[type="radio"]')[1].setValue(true);
  await titleInput(wrapper).setValue('  Sinistro — Onix  ');
  expect(dialog(wrapper).props('disableConfirmButton')).toBe(false);

  dialog(wrapper).vm.$emit('confirm');
  await flushPromises();

  expect(dispatch).toHaveBeenCalledWith(
    'crmKanban/createCardFromConversation',
    {
      conversation_display_id: 9,
      pipeline_id: 2,
      title: 'Sinistro — Onix',
      new_subject: true,
    }
  );
  expect(wrapper.emitted('created')).toHaveLength(1);
});

it('starts clean every time it opens', async () => {
  const { wrapper } = setup();
  await wrapper.vm.open();
  await flushPromises();
  await wrapper.findAll('input[type="radio"]')[0].setValue(true);
  await titleInput(wrapper).setValue('Algo');

  await wrapper.vm.open();
  await flushPromises();

  expect(titleInput(wrapper).element.value).toBe('');
  expect(dialog(wrapper).props('disableConfirmButton')).toBe(true);
});
