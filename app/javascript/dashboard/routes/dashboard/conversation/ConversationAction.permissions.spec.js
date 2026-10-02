import { ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ConversationAction from './ConversationAction.vue';
const canView = ref(true);
const canManage = ref(false);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canViewCrm: canView, canManageCards: canManage }),
}));
vi.mock('dashboard/composables/useAgentsList', () => ({
  useAgentsList: () => ({ agentsList: ref([]) }),
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getStages: vi
      .fn()
      .mockResolvedValue({ data: { payload: [{ id: 2, name: 'New' }] } }),
  },
}));
const wrappers = [];
function setup() {
  const store = createStore({
    getters: {
      getSelectedChat: () => ({
        id: 9,
        account_id: 1,
        meta: { sender: { id: 12 } },
      }),
      getCurrentUser: () => ({ id: 1 }),
      'teams/getTeams': () => [],
      'globalConfig/get': () => ({ crmKanbanEnabled: true }),
      'crmKanban/getPipelines': () => [{ id: 1, name: 'Commercial' }],
      'labels/getLabels': () => [],
      'contactLabels/getContactLabels': () => () => [],
    },
  });
  const dispatch = vi
    .spyOn(store, 'dispatch')
    .mockResolvedValue([{ id: 1, name: 'Commercial' }]);
  const wrapper = shallowMount(ConversationAction, {
    props: { conversationId: 9 },
    global: { plugins: [store] },
  });
  wrappers.push(wrapper);
  return { wrapper, dispatch };
}
beforeEach(() => {
  canView.value = true;
  canManage.value = false;
  CrmKanbanAPI.getStages.mockResolvedValue({
    data: { payload: [{ id: 2, name: 'New' }] },
  });
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));
it('keeps the CRM stage readable without offering creation or fetching its edit choices', async () => {
  const { wrapper, dispatch } = setup();
  await flushPromises();
  expect(
    wrapper.findComponent({ name: 'CrmConversationStageBadge' }).exists()
  ).toBe(true);
  expect(wrapper.findAllComponents({ name: 'ChoiceSelect' })).toHaveLength(0);
  expect(dispatch).not.toHaveBeenCalledWith('crmKanban/fetchPipelines');
  wrapper.vm.crmPipelineId = 1;
  wrapper.vm.crmStageId = 2;
  dispatch.mockClear();
  await wrapper.vm.createCrmCardFromConversation();
  expect(dispatch).not.toHaveBeenCalled();
});
it('preserves authorized CRM creation and blocks a callback after revocation', async () => {
  canManage.value = true;
  const { wrapper, dispatch } = setup();
  await flushPromises();
  expect(CrmKanbanAPI.getStages).toHaveBeenCalledWith(1);
  await flushPromises();
  expect(wrapper.vm.crmStageId).toBe(2);
  expect(wrapper.findAllComponents({ name: 'ChoiceSelect' })).toHaveLength(2);
  await wrapper.vm.createCrmCardFromConversation();
  expect(dispatch).toHaveBeenCalledWith(
    'crmKanban/createCardFromConversation',
    { conversation_display_id: 9, pipeline_id: 1, stage_id: 2 }
  );
  canManage.value = false;
  await flushPromises();
  dispatch.mockClear();
  await wrapper.vm.createCrmCardFromConversation();
  expect(dispatch).not.toHaveBeenCalled();
});
it('does not load CRM choices or expose the CRM section without CRM access', async () => {
  canView.value = false;
  const { wrapper, dispatch } = setup();
  await flushPromises();
  expect(wrapper.text()).not.toContain('CRM_KANBAN.CONVERSATION.TITLE');
  expect(dispatch).not.toHaveBeenCalledWith('crmKanban/fetchPipelines');
});
