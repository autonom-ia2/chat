import { ref } from 'vue';
import { shallowMount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import ConversationAction from './ConversationAction.vue';

const canView = ref(true);
const canManage = ref(false);
vi.mock('dashboard/routes/dashboard/crm/composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canViewCrm: canView, canManageCards: canManage }),
}));
vi.mock('dashboard/composables/useAgentsList', () => ({
  useAgentsList: () => ({ agentsList: ref([]) }),
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
      'labels/getLabels': () => [],
      'contactLabels/getContactLabels': () => () => [],
    },
  });
  const dispatch = vi.spyOn(store, 'dispatch').mockResolvedValue([]);
  const wrapper = shallowMount(ConversationAction, {
    props: { conversationId: 9 },
    global: { plugins: [store] },
  });
  wrappers.push(wrapper);
  return { wrapper, dispatch };
}

const subjectsPanel = wrapper =>
  wrapper.findComponent({ name: 'CrmConversationSubjects' });

beforeEach(() => {
  canView.value = true;
  canManage.value = false;
});
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

it('shows the conversation subjects read-only without loading CRM choices', async () => {
  const { wrapper, dispatch } = setup();
  await flushPromises();

  expect(subjectsPanel(wrapper).exists()).toBe(true);
  expect(subjectsPanel(wrapper).props('canManage')).toBe(false);
  expect(dispatch).not.toHaveBeenCalledWith('crmKanban/fetchPipelines');
});

it('lets an agent who manages cards create and switch subjects, and stops when access is revoked', async () => {
  canManage.value = true;
  const { wrapper } = setup();
  await flushPromises();
  expect(subjectsPanel(wrapper).props('canManage')).toBe(true);

  canManage.value = false;
  await flushPromises();
  expect(subjectsPanel(wrapper).props('canManage')).toBe(false);
});

it('does not expose the CRM section without CRM access', async () => {
  canView.value = false;
  const { wrapper, dispatch } = setup();
  await flushPromises();

  expect(wrapper.text()).not.toContain('CRM_KANBAN.CONVERSATION.TITLE');
  expect(subjectsPanel(wrapper).exists()).toBe(false);
  expect(dispatch).not.toHaveBeenCalledWith('crmKanban/fetchPipelines');
});
