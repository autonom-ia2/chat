import { mount, flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { notifyCrmSubjectsChanged } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import CrmReplySubject from './CrmReplySubject.vue';

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getConversationSubjects: vi.fn(),
    focusConversationSubject: vi.fn(),
  },
}));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmConversationStages',
  async () => {
    const { ref } = await import('vue');
    return {
      crmSubjectsChange: ref({ conversationId: null, version: 0 }),
      notifyCrmSubjectsChanged: vi.fn(),
    };
  }
);
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const permissions = vi.hoisted(() => ({ canManageCards: null }));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { ref } = await import('vue');
    permissions.canManageCards = ref(true);
    return {
      useCrmPermissions: () => ({
        canViewCrm: ref(true),
        canManageCards: permissions.canManageCards,
      }),
    };
  }
);

const subject = (id, title, extra = {}) => ({
  id,
  title,
  status: 'open',
  current: false,
  pipeline_name: 'Comercial',
  stage_name: 'Novo',
  ...extra,
});

const wrappers = [];
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

const mountReply = (subjects, { canManageCards = true } = {}) => {
  permissions.canManageCards.value = canManageCards;
  CrmKanbanAPI.getConversationSubjects.mockResolvedValue({
    data: { payload: subjects },
  });
  const wrapper = mount(CrmReplySubject, { props: { conversationId: 9 } });
  wrappers.push(wrapper);
  return wrapper;
};

beforeEach(() => {
  vi.clearAllMocks();
  CrmKanbanAPI.focusConversationSubject.mockResolvedValue({});
});

it('stays hidden and sends no subject when the conversation has a single open subject', async () => {
  const wrapper = mountReply([
    subject(1, 'Chat2You', { current: true }),
    subject(2, 'Plano antigo', { status: 'won' }),
  ]);
  await flushPromises();

  expect(wrapper.find('[data-crm-reply-subject]').exists()).toBe(false);
  const sentCards = (wrapper.emitted('update:cardId') || []).flat();
  expect(sentCards.filter(Boolean)).toEqual([]);
});

it('shows the current subject and sends it with the reply', async () => {
  const wrapper = mountReply([
    subject(2, 'Chat2You', { current: true }),
    subject(1, 'Agentes de IA'),
  ]);
  await flushPromises();

  expect(wrapper.find('[data-crm-reply-subject]').text()).toContain('Chat2You');
  expect(wrapper.emitted('update:cardId').at(-1)).toEqual([2]);
});

it('switching the subject here makes it the current one right away', async () => {
  const wrapper = mountReply([
    subject(2, 'Chat2You', { current: true }),
    subject(1, 'Agentes de IA'),
  ]);
  await flushPromises();

  await wrapper.find('[data-crm-reply-subject] > button').trigger('click');
  const options = wrapper.findAll('[data-crm-reply-subject] li button');
  await options[1].trigger('click');
  await flushPromises();

  expect(CrmKanbanAPI.focusConversationSubject).toHaveBeenCalledWith(9, 1);
  expect(notifyCrmSubjectsChanged).toHaveBeenCalledWith(9);
});

it('does not switch for someone who cannot manage cards', async () => {
  const wrapper = mountReply(
    [subject(2, 'Chat2You', { current: true }), subject(1, 'Agentes de IA')],
    { canManageCards: false }
  );
  await flushPromises();

  const toggle = wrapper.find('[data-crm-reply-subject] > button');
  expect(toggle.attributes('disabled')).toBeDefined();
  expect(CrmKanbanAPI.focusConversationSubject).not.toHaveBeenCalled();
});
