import { mount, flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { refreshCrmConversationStage } from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import CrmConversationSubjects from './CrmConversationSubjects.vue';

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getConversationSubjects: vi.fn(),
    focusConversationSubject: vi.fn(),
  },
}));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmConversationStages',
  () => ({ refreshCrmConversationStage: vi.fn() })
);
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const SUBJECTS = [
  {
    id: 2,
    title: 'Chat2You',
    status: 'open',
    current: true,
    pipeline_name: 'Comercial',
    stage_name: 'Proposta',
    owner: { id: 1, name: 'Ana' },
  },
  {
    id: 1,
    title: 'Agentes de IA',
    status: 'open',
    current: false,
    pipeline_name: 'Comercial',
    stage_name: 'Novo',
    owner: null,
  },
  {
    id: 3,
    title: 'Plano anual',
    status: 'won',
    current: false,
    pipeline_name: 'Comercial',
    stage_name: 'Fechamento',
    owner: null,
  },
];

const mountPanel = (props = {}) =>
  mount(CrmConversationSubjects, {
    props: { conversationId: 9, canManage: true, ...props },
    global: {
      stubs: { CrmNewSubjectDialog: true, NextButton: true },
    },
  });

const rows = wrapper => wrapper.findAll('[data-crm-subject]');

beforeEach(() => {
  vi.clearAllMocks();
  CrmKanbanAPI.getConversationSubjects.mockResolvedValue({
    data: { payload: SUBJECTS },
  });
  CrmKanbanAPI.focusConversationSubject.mockResolvedValue({});
});

it('lists every subject and marks the current one', async () => {
  const wrapper = mountPanel();
  await flushPromises();

  expect(CrmKanbanAPI.getConversationSubjects).toHaveBeenCalledWith(9);
  expect(rows(wrapper)).toHaveLength(3);
  expect(rows(wrapper)[0].attributes('aria-current')).toBe('true');
  expect(rows(wrapper)[0].text()).toContain('Chat2You');
  expect(rows(wrapper)[1].text()).toContain('Agentes de IA');
  expect(rows(wrapper)[1].text()).toContain(
    'CRM_KANBAN.CONVERSATION.SUBJECTS.PIPELINE_STAGE'
  );
});

it('makes another open subject current and refreshes the list badge', async () => {
  const wrapper = mountPanel();
  await flushPromises();

  await rows(wrapper)[1].trigger('click');
  await flushPromises();

  expect(CrmKanbanAPI.focusConversationSubject).toHaveBeenCalledWith(9, 1);
  expect(refreshCrmConversationStage).toHaveBeenCalledWith(9);
  expect(CrmKanbanAPI.getConversationSubjects).toHaveBeenCalledTimes(2);
});

it('never switches to a closed subject or without permission', async () => {
  const wrapper = mountPanel();
  await flushPromises();
  expect(rows(wrapper)[2].element.tagName).toBe('DIV');
  expect(rows(wrapper)[0].element.tagName).toBe('DIV');
  expect(rows(wrapper)[1].element.tagName).toBe('BUTTON');

  const readOnly = mountPanel({ canManage: false });
  await flushPromises();
  await rows(readOnly)[1].trigger('click');

  expect(CrmKanbanAPI.focusConversationSubject).not.toHaveBeenCalled();
});

it('shows a retry when the subjects cannot be loaded and loads again on retry', async () => {
  CrmKanbanAPI.getConversationSubjects.mockRejectedValueOnce(new Error('x'));
  const wrapper = mountPanel();
  await flushPromises();

  expect(wrapper.text()).toContain(
    'CRM_KANBAN.CONVERSATION.SUBJECTS.LOAD_ERROR'
  );
  const retry = wrapper
    .findAllComponents({ name: 'NextButton' })
    .find(button => button.props('label')?.endsWith('SUBJECTS.RETRY'));
  await retry.vm.$emit('click');
  await flushPromises();
  expect(rows(wrapper)).toHaveLength(3);
});

it('ignores a late answer from the previous conversation', async () => {
  let resolveOld;
  CrmKanbanAPI.getConversationSubjects
    .mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    )
    .mockResolvedValueOnce({ data: { payload: [SUBJECTS[1]] } });
  const wrapper = mountPanel();
  await wrapper.setProps({ conversationId: 10 });
  await flushPromises();
  resolveOld({ data: { payload: SUBJECTS } });
  await flushPromises();

  expect(rows(wrapper)).toHaveLength(1);
  expect(rows(wrapper)[0].text()).toContain('Agentes de IA');
});
