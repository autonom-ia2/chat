import { mount, flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import CrmReplySubject from './CrmReplySubject.vue';

const permissions = vi.hoisted(() => ({ canManageCards: null }));

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
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const subject = (id, title, extra = {}) => ({
  id,
  title,
  status: 'open',
  current: false,
  pipeline_name: 'Comercial',
  stage_name: 'Novo',
  ...extra,
});
const TWO_SUBJECTS = [
  subject(2, 'Chat2You', { current: true }),
  subject(1, 'Agentes de IA'),
];

const wrappers = [];
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

const mountReply = (subjects, { canManageCards = true } = {}) => {
  permissions.canManageCards.value = canManageCards;
  CrmKanbanAPI.getConversationSubjects.mockResolvedValue({
    data: { payload: subjects },
  });
  const wrapper = mount(CrmReplySubject, {
    props: { conversationId: 9 },
    attachTo: document.body,
  });
  wrappers.push(wrapper);
  return wrapper;
};

const lastCardId = wrapper => wrapper.emitted('update:cardId')?.at(-1)?.[0];
const toggle = wrapper => wrapper.find('[data-crm-reply-subject-toggle]');
const openAndPick = async (wrapper, index) => {
  await toggle(wrapper).trigger('click');
  await wrapper.findAll('[role="menuitemradio"]')[index].trigger('click');
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
  expect(lastCardId(wrapper) ?? null).toBeNull();
});

it('shows the current subject and sends it with the reply', async () => {
  const wrapper = mountReply(TWO_SUBJECTS);
  await flushPromises();

  expect(toggle(wrapper).text()).toContain('Chat2You');
  expect(lastCardId(wrapper)).toBe(2);
});

it('uses the newly chosen subject at once, before the switch answers', async () => {
  let finishFocus;
  CrmKanbanAPI.focusConversationSubject.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishFocus = resolve;
      })
  );
  const wrapper = mountReply(TWO_SUBJECTS);
  await flushPromises();

  await openAndPick(wrapper, 1);

  expect(lastCardId(wrapper)).toBe(1);
  expect(CrmKanbanAPI.focusConversationSubject).toHaveBeenCalledWith(9, 1);
  finishFocus({});
  await flushPromises();
  expect(notifyCrmSubjectsChanged).toHaveBeenCalledWith(9);
});

it('goes back to the previous subject when the switch fails', async () => {
  CrmKanbanAPI.focusConversationSubject.mockRejectedValueOnce(new Error('x'));
  const wrapper = mountReply(TWO_SUBJECTS);
  await flushPromises();

  await openAndPick(wrapper, 1);
  await flushPromises();

  expect(lastCardId(wrapper)).toBe(2);
});

it('reloads when the subjects of this conversation change elsewhere', async () => {
  mountReply(TWO_SUBJECTS);
  await flushPromises();
  expect(CrmKanbanAPI.getConversationSubjects).toHaveBeenCalledTimes(1);

  crmSubjectsChange.value = { conversationId: 9, version: 1 };
  await flushPromises();

  expect(CrmKanbanAPI.getConversationSubjects).toHaveBeenCalledTimes(2);
});

it('closes the menu with Escape and gives focus back', async () => {
  const wrapper = mountReply(TWO_SUBJECTS);
  await flushPromises();

  await toggle(wrapper).trigger('click');
  expect(wrapper.find('[role="menu"]').exists()).toBe(true);
  await wrapper.find('[role="menu"]').trigger('keydown', { key: 'Escape' });

  expect(wrapper.find('[role="menu"]').exists()).toBe(false);
  expect(document.activeElement).toBe(toggle(wrapper).element);
});

it('only shows the subject to someone who cannot manage cards', async () => {
  const wrapper = mountReply(TWO_SUBJECTS, { canManageCards: false });
  await flushPromises();

  await toggle(wrapper).trigger('click');

  expect(wrapper.find('[role="menu"]').exists()).toBe(false);
  expect(CrmKanbanAPI.focusConversationSubject).not.toHaveBeenCalled();
});
