import { ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { flushPromises, mount } from '@vue/test-utils';
import CrmCardDrawer from './CrmCardDrawer.vue';

const { keyboard, alertSpy, storeGetters } = vi.hoisted(() => ({
  keyboard: { handlers: null },
  alertSpy: vi.fn(),
  storeGetters: {},
}));
const recordPermission = ref(true);
vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({
    canManageRelationshipRecords: recordPermission,
  }),
}));
beforeEach(() => {
  recordPermission.value = true;
});

// Stub the store/router/composables/APIs the drawer reaches for, so we can mount
// it in isolation and assert the form-reset reactivity that the realtime-churn
// fix changed (props.stages dropped from the reset watcher, props.card kept).
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ getters: storeGetters, dispatch: vi.fn() }),
}));
const navigate = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: navigate }),
}));
vi.mock('dashboard/composables', () => ({
  useAlert: alertSpy,
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: handlers => {
    keyboard.handlers = handlers;
  },
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    search: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    update: vi.fn().mockResolvedValue({}),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getFollowUpMessagingWindow: vi.fn().mockResolvedValue({ data: {} }),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: [] }) },
}));

const makeStages = () => [
  { id: 10, name: 'Novo', color: '#2563eb' },
  { id: 11, name: 'Em atendimento', color: '#0891b2' },
];

const mountDrawer = (props = {}) =>
  mount(CrmCardDrawer, {
    props: {
      show: true,
      mode: 'edit',
      card: { id: 5, title: 'Card A', stage_id: 10 },
      stages: makeStages(),
      pipelineId: 1,
      ...props,
    },
    global: {
      stubs: {
        Dialog: {
          template: '<div />',
          methods: { open: vi.fn(), close: vi.fn() },
        },
        CrmCardRelationshipPanel: {
          name: 'CrmCardRelationshipPanel',
          template: '<div />',
          data: () => ({ companyAction: null, dirty: false, saving: false }),
          methods: { reset: vi.fn() },
        },
        CrmCardAiPanel: true,
        CrmCardSummaryPanel: true,
        CrmCardAutoFollowupStatus: true,
        PhoneNumberInput: true,
        CrmOpportunityContactPicker: true,
      },
    },
  });

describe('CrmCardDrawer form reset vs realtime churn', () => {
  it('keeps in-progress card edits when props.stages churns (realtime/poll)', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.form.title = 'Card A editado';
    await wrapper.vm.$nextTick();

    // Realtime event rebuilds board.stages into a new array; the selected card
    // is NOT rebound, so editing must survive.
    await wrapper.setProps({ stages: makeStages() });

    expect(wrapper.vm.form.title).toBe('Card A editado');
  });

  it('resets the form when a different card is opened', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.form.title = 'dirty';

    await wrapper.setProps({ card: { id: 6, title: 'Card B', stage_id: 11 } });

    expect(wrapper.vm.form.title).toBe('Card B');
  });

  it('re-hydrates when the shallow card is replaced by its detailed payload (same id)', async () => {
    const wrapper = mountDrawer();
    expect(wrapper.vm.form.description).toBe('');

    // Parent opens with a shallow card, then swaps in the detailed object
    // (same id, fuller data). The reset watcher must pick this up.
    await wrapper.setProps({
      card: { id: 5, title: 'Card A', stage_id: 10, description: 'detalhe' },
    });

    expect(wrapper.vm.form.description).toBe('detalhe');
  });
});

describe('CrmCardDrawer contextual opportunity', () => {
  it('returns to the source contact without a discard prompt for an untouched contextual form', async () => {
    navigate.mockClear();
    const wrapper = mountDrawer({
      mode: 'create',
      card: null,
      initialContact: { id: 42, name: 'Mariana' },
      pipelines: [{ id: 1, name: 'Comercial' }],
      canManageCards: true,
    });
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CRM_KANBAN.OPPORTUNITY.CONTEXT.BACK')
      .trigger('click');
    expect(navigate).toHaveBeenCalledWith({
      name: 'contacts_edit',
      params: { accountId: '1', contactId: 42 },
    });
    expect(wrapper.vm.discardOpen).toBe(false);
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.unmount();
  });
  it('requires discarding commercial changes before returning to the source contact', async () => {
    navigate.mockClear();
    const wrapper = mountDrawer({
      mode: 'create',
      card: null,
      initialContact: { id: 42, name: 'Mariana' },
      pipelines: [{ id: 1, name: 'Comercial' }],
      canManageCards: true,
    });
    wrapper.findComponent({ name: 'CrmOpportunityForm' }).vm.form.title =
      'Não perder';
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CRM_KANBAN.OPPORTUNITY.CONTEXT.BACK')
      .trigger('click');
    expect(navigate).not.toHaveBeenCalled();
    expect(wrapper.vm.discardOpen).toBe(true);
    wrapper.vm.confirmDiscard();
    expect(navigate).toHaveBeenCalledWith({
      name: 'contacts_edit',
      params: { accountId: '1', contactId: 42 },
    });
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.unmount();
  });
});

describe('CrmCardDrawer new opportunity', () => {
  it('asks before discarding the new commercial draft and does not create a record', async () => {
    const wrapper = mountDrawer({
      mode: 'create',
      card: null,
      pipelines: [{ id: 1, name: 'Comercial' }],
      canManageCards: true,
    });
    const form = wrapper.findComponent({ name: 'CrmOpportunityForm' });
    form.vm.form.title = 'Unsaved opportunity';
    await wrapper.vm.$nextTick();
    const cancel = wrapper
      .findAll('button')
      .find(button => button.text() === 'CRM_KANBAN.DRAWER.CANCEL');
    await cancel.trigger('click');
    expect(wrapper.vm.discardOpen).toBe(true);
    expect(wrapper.emitted('close')).toBeUndefined();
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.vm.confirmDiscard();
    expect(wrapper.emitted('close')).toHaveLength(1);
    wrapper.unmount();
  });
  it('keeps the fixed create button bound to the real form and forwards the failure callback', async () => {
    const wrapper = mountDrawer({
      mode: 'create',
      card: null,
      pipelines: [{ id: 1, name: 'Comercial' }],
      canManageCards: true,
    });
    const form = wrapper.findComponent({ name: 'CrmOpportunityForm' });
    const failed = vi.fn();
    form.vm.$emit('save', { title: 'New', idempotencyKey: 'key' }, failed);
    expect(wrapper.emitted('save')[0]).toEqual([
      { title: 'New', idempotencyKey: 'key' },
      failed,
    ]);
    await wrapper.vm.$nextTick();
    expect(wrapper.find('button[type="submit"]').attributes('form')).toBe(
      form.vm.formId
    );
    wrapper.unmount();
  });
  it('cannot close while creation is waiting for the server', async () => {
    const wrapper = mountDrawer({
      mode: 'create',
      card: null,
      pipelines: [{ id: 1, name: 'Comercial' }],
      canManageCards: true,
    });
    wrapper.findComponent({ name: 'CrmOpportunityForm' }).vm.sending = true;
    await wrapper.vm.$nextTick();
    const action = vi.fn();
    wrapper.vm.guardRelationship(action);
    expect(action).not.toHaveBeenCalled();
    expect(wrapper.emitted('close')).toBeUndefined();
    wrapper.unmount();
  });
});

describe('CrmCardDrawer timeline', () => {
  it('mostra por que o follow-up foi cancelado quando o contato recusou mensagens ativas', () => {
    const wrapper = mountDrawer();

    const { detail } = wrapper.vm.describeActivity({
      event_type: 'follow_up_canceled',
      payload: { title: 'Retomar', reason: 'opt_out' },
      created_at: new Date().toISOString(),
    });

    expect(detail).toContain('Retomar');
    expect(detail).toContain(
      'CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_FOLLOW_UP_OPT_OUT'
    );
  });

  it('cancelamento comum continua mostrando só o título', () => {
    const wrapper = mountDrawer();

    const { detail } = wrapper.vm.describeActivity({
      event_type: 'follow_up_canceled',
      payload: { title: 'Retomar' },
      created_at: new Date().toISOString(),
    });

    expect(detail).toBe('Retomar');
  });
});

it('sends no stale custom attributes when editing only native contact details', async () => {
  const wrapper = mountDrawer({
    card: {
      id: 5,
      title: 'Card A',
      stage_id: 10,
      contact: {
        id: 42,
        name: 'Original',
        custom_attributes: { address: 'Old address', job_title: 'Old title' },
      },
    },
  });
  wrapper.vm.contactForm.name = 'Edited name';
  await wrapper.vm.persistContactIfChanged();
  expect(ContactAPI.update.mock.lastCall[1]).not.toHaveProperty(
    'custom_attributes'
  );
  wrapper.unmount();
});
it('sends only the custom attribute actually edited in the CRM drawer', async () => {
  const wrapper = mountDrawer({
    card: {
      id: 5,
      title: 'Card A',
      stage_id: 10,
      contact: {
        id: 42,
        name: 'Original',
        custom_attributes: { address: 'Old address', job_title: 'Old title' },
      },
    },
  });
  wrapper.vm.contactForm.jobTitle = 'Edited title';
  await wrapper.vm.persistContactIfChanged();
  expect(ContactAPI.update.mock.lastCall[1].custom_attributes).toEqual({
    job_title: 'Edited title',
  });
  wrapper.unmount();
});

it('uses the same 40rem width as the pipeline drawer', () => {
  const wrapper = mountDrawer();
  expect(wrapper.find('[data-crm-card-drawer]').classes()).toContain(
    'w-[40rem]'
  );
  expect(wrapper.find('[data-crm-card-drawer]').classes()).toContain(
    'max-w-full'
  );
  wrapper.unmount();
});
it('exposes an accessible drawer shell and keyboard-navigable detail tabs', async () => {
  const wrapper = mountDrawer();
  const drawer = wrapper.find('[data-crm-card-drawer]');
  expect(drawer.attributes('role')).toBe('dialog');
  expect(drawer.attributes('aria-modal')).toBe('true');
  expect(drawer.attributes('aria-labelledby')).toBeTruthy();
  expect(drawer.find('button[aria-label="GENERAL.CLOSE"]').exists()).toBe(true);

  const tabs = drawer.findAll('button[role="tab"]');
  expect(tabs).toHaveLength(5);
  expect(tabs.every(tab => tab.attributes('aria-controls'))).toBe(true);
  await tabs[0].trigger('keydown', { key: 'End' });
  await wrapper.vm.$nextTick();
  expect(wrapper.vm.activeTab).toBe('timeline');
  expect(
    drawer
      .find('section[role="tabpanel"][aria-labelledby$="timeline"]')
      .exists()
  ).toBe(true);
  wrapper.unmount();
});
it('keeps the fixed footer out of the relationship-link subflow', async () => {
  const wrapper = mountDrawer();
  wrapper.vm.relationshipPanel = { linking: true, dirty: false, saving: false };
  await wrapper.vm.$nextTick();
  expect(wrapper.find('[data-crm-drawer-footer]').exists()).toBe(false);
  wrapper.unmount();
});
it('retains the active relationship tab when refreshing the same card', async () => {
  const wrapper = mountDrawer();
  wrapper.vm.activeTab = 'contact';
  await wrapper.setProps({
    card: { id: 5, title: 'Card A', stage_id: 10, contact_id: 42 },
  });
  expect(wrapper.vm.activeTab).toBe('contact');
  wrapper.unmount();
});
it('retains an unsaved opportunity title during a contact refresh', async () => {
  const wrapper = mountDrawer();
  wrapper.vm.form.title = 'Commercial draft';
  await wrapper.setProps({
    card: { id: 5, title: 'Server title', stage_id: 10, contact_id: 42 },
  });
  expect(wrapper.vm.form.title).toBe('Commercial draft');
  wrapper.unmount();
});
it('does not implicitly save a dirty contact from the opportunity save action', () => {
  ContactAPI.update.mockClear();
  const wrapper = mountDrawer({
    canManageCards: true,
    card: {
      id: 5,
      title: 'Card A',
      stage_id: 10,
      contact: { id: 42, name: 'Original' },
    },
  });
  wrapper.vm.contactForm.name = 'Unsaved person';
  wrapper.vm.onSubmit();
  expect(ContactAPI.update).not.toHaveBeenCalled();
  expect(wrapper.emitted('save')).toHaveLength(1);
  wrapper.unmount();
});
it('saves the contact independently and refreshes the card without saving commercial data', async () => {
  const wrapper = mountDrawer({
    card: {
      id: 5,
      title: 'Card A',
      stage_id: 10,
      contact: { id: 42, name: 'Original' },
    },
  });
  wrapper.vm.contactForm.name = 'Updated person';
  await wrapper.vm.saveContact();
  expect(ContactAPI.update.mock.lastCall).toEqual([
    42,
    { name: 'Updated person' },
  ]);
  expect(wrapper.emitted('save')).toBeUndefined();
  expect(wrapper.emitted('refreshCard')).toHaveLength(1);
  wrapper.unmount();
});
it('never updates a company name as a substitute for a canonical company association', () => {
  const wrapper = mountDrawer({
    card: {
      id: 5,
      title: 'Card A',
      stage_id: 10,
      contact: {
        id: 42,
        name: 'Original',
        additional_attributes: { company_name: 'Legacy' },
      },
    },
  });
  wrapper.vm.contactForm.name = 'Updated person';
  wrapper.vm.contactForm.company = 'Not an association';
  expect(wrapper.vm.buildContactPayload()).toEqual({ name: 'Updated person' });
  wrapper.unmount();
});

it('guards archiving when a relationship field has an unsaved draft', async () => {
  const wrapper = mountDrawer({ canManageCards: true });
  wrapper.vm.relationshipPanel = { dirty: true, saving: false, reset: vi.fn() };
  const archive = wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.DRAWER.ARCHIVE');
  await archive.trigger('click');
  expect(wrapper.emitted('archive')).toBeUndefined();
  expect(wrapper.vm.discardOpen).toBe(true);
  wrapper.vm.confirmDiscard();
  expect(wrapper.emitted('archive')).toHaveLength(1);
  wrapper.unmount();
});
it('does not archive while a relationship field write is in progress', async () => {
  const wrapper = mountDrawer({ canManageCards: true });
  wrapper.vm.relationshipPanel = { dirty: true, saving: true, reset: vi.fn() };
  const archive = wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.DRAWER.ARCHIVE');
  await archive.trigger('click');
  expect(wrapper.emitted('archive')).toBeUndefined();
  expect(wrapper.vm.discardOpen).toBe(false);
  wrapper.unmount();
});

it('shows company save in the fixed footer without a commercial save or archive action', async () => {
  const wrapper = mountDrawer();
  wrapper.vm.activeTab = 'contact';
  await wrapper.vm.$nextTick();
  wrapper.vm.relationshipPanel.companyAction = {
    formId: 'company-form',
    label: 'Save company',
    disabled: false,
    saving: false,
  };
  await wrapper.vm.$nextTick();
  const submit = wrapper.find('button[type="submit"][form="company-form"]');
  expect(submit.exists()).toBe(true);
  expect(submit.text()).toBe('Save company');
  expect(
    wrapper
      .findAll('button')
      .some(button => button.text() === 'CRM_KANBAN.DRAWER.ARCHIVE')
  ).toBe(false);
  wrapper.unmount();
});
it('cancels the company editor without closing the opportunity', async () => {
  const wrapper = mountDrawer();
  const reset = vi.fn();
  wrapper.vm.activeTab = 'contact';
  await wrapper.vm.$nextTick();
  wrapper.vm.relationshipPanel.companyAction = {
    formId: 'company-form',
    label: 'Save company',
    disabled: true,
    saving: false,
  };
  wrapper.vm.relationshipPanel.reset = reset;
  await wrapper.vm.$nextTick();
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'CRM_KANBAN.RELATIONSHIP.CANCEL')
    .trigger('click');
  expect(reset).toHaveBeenCalled();
  expect(wrapper.emitted('close')).toBeUndefined();
  wrapper.unmount();
});

it.each([
  ['CRM_KANBAN.DRAWER.WIN_DEAL', 'showWinDialog'],
  ['CRM_KANBAN.DRAWER.LOSE_DEAL', 'showLoseDialog'],
])(
  'guards the %s action while company changes are unsaved',
  async (label, dialog) => {
    const wrapper = mountDrawer({ canManageCards: true });
    wrapper.vm.activeTab = 'contact';
    await wrapper.vm.$nextTick();
    wrapper.vm.relationshipPanel.dirty = true;
    wrapper.vm.relationshipPanel.saving = false;
    await wrapper.vm.$nextTick();
    await wrapper
      .findAll('button')
      .find(button => button.text() === label)
      .trigger('click');
    expect(wrapper.vm[dialog]).toBe(false);
    expect(wrapper.vm.discardOpen).toBe(true);
    wrapper.vm.confirmDiscard();
    expect(wrapper.vm[dialog]).toBe(true);
    wrapper.unmount();
  }
);

describe('legacy commercial action permissions', () => {
  it('keeps the summary values readable without save or scheduling controls', async () => {
    const wrapper = mountDrawer({
      canManageCards: false,
      meetingsEnabled: true,
    });
    expect(wrapper.find('input').attributes('readonly')).toBeDefined();
    expect(wrapper.find('textarea').attributes('readonly')).toBeDefined();
    const labels = wrapper.findAll('button').map(button => button.text());
    expect(labels).not.toContain('CRM_KANBAN.DRAWER.SAVE');
    expect(labels).not.toContain('CRM_KANBAN.DRAWER.SCHEDULE_MEETING');
    wrapper.vm.confirmWin();
    wrapper.vm.confirmLose();
    expect(wrapper.emitted('closeDeal')).toBeUndefined();
    wrapper.unmount();
  });
  it('keeps follow-up details readable without archive, create, complete or cancel controls', async () => {
    const wrapper = mountDrawer({
      canManageCards: false,
      followUps: [
        {
          id: 8,
          title: 'Existing reminder',
          status: 'pending',
          due_at: '2026-11-15T12:00:00Z',
        },
      ],
    });
    wrapper.vm.activeTab = 'followups';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain('Existing reminder');
    const buttons = wrapper.findAll('button').map(button => button.text());
    [
      'ARCHIVE',
      'FOLLOW_UP_CREATE',
      'FOLLOW_UP_COMPLETE',
      'FOLLOW_UP_CANCEL',
    ].forEach(key => expect(buttons).not.toContain(`CRM_KANBAN.DRAWER.${key}`));
    wrapper.vm.form.title = 'Forbidden commercial edit';
    wrapper.vm.onSubmit();
    wrapper.vm.followUpForm.title = 'Forbidden reminder';
    wrapper.vm.followUpForm.dueAt = '2026-11-15T12:00';
    wrapper.vm.createFollowUp();
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.emitted('createFollowUp')).toBeUndefined();
    wrapper.unmount();
  });
  it('does not execute a deferred archive after commercial permission is revoked', async () => {
    const wrapper = mountDrawer({ canManageCards: true });
    wrapper.vm.relationshipPanel = {
      dirty: true,
      saving: false,
      reset: vi.fn(),
    };
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'CRM_KANBAN.DRAWER.ARCHIVE')
      .trigger('click');
    expect(wrapper.vm.discardOpen).toBe(true);
    await wrapper.setProps({ canManageCards: false });
    wrapper.vm.confirmDiscard();
    expect(wrapper.emitted('archive')).toBeUndefined();
    wrapper.unmount();
  });
  it('keeps authorized follow-up creation available', async () => {
    const wrapper = mountDrawer({ canManageCards: true });
    wrapper.vm.followUpForm.title = 'Authorized reminder';
    wrapper.vm.followUpForm.dueAt = '2026-11-15T12:00';
    wrapper.vm.createFollowUp();
    expect(wrapper.emitted('createFollowUp')).toHaveLength(1);
    wrapper.unmount();
  });
});

it('never turns CRM card management into permission to edit the shared contact', async () => {
  recordPermission.value = false;
  ContactAPI.update.mockClear();
  const wrapper = mountDrawer({
    canManageCards: true,
    card: {
      id: 5,
      title: 'Allowed deal',
      stage_id: 10,
      contact: { id: 42, name: 'Keep person' },
    },
  });
  wrapper.vm.startContactEdit({ id: 42, name: 'Keep person' });
  expect(wrapper.vm.isEditingContact).toBe(false);
  wrapper.vm.contactForm.name = 'Forbidden';
  await wrapper.vm.saveContact();
  expect(ContactAPI.update).not.toHaveBeenCalled();
  wrapper.vm.form.title = 'Commercial edit';
  wrapper.vm.onSubmit();
  expect(wrapper.emitted('save')).toHaveLength(1);
  wrapper.unmount();
});

describe('CrmCardDrawer follow-ups', () => {
  const pending = {
    id: 8,
    title: 'Ligar amanhã',
    status: 'pending',
    due_at: '2026-11-15T12:00:00Z',
  };
  const overdue = {
    id: 9,
    title: 'Enviar proposta',
    status: 'overdue',
    due_at: '2026-11-10T12:00:00Z',
  };
  const done = {
    id: 10,
    title: 'Retorno feito',
    status: 'done',
    due_at: '2026-11-01T12:00:00Z',
  };
  const canceled = {
    id: 11,
    title: 'Retorno cancelado',
    status: 'canceled',
    due_at: '2026-11-02T12:00:00Z',
  };
  const linkedCard = {
    id: 5,
    title: 'Card A',
    stage_id: 10,
    conversation_id: 31,
    inbox_id: 3,
  };

  const mountFollowUps = async (props = {}) => {
    const wrapper = mountDrawer({
      canManageCards: true,
      initialTab: 'followups',
      ...props,
    });
    await flushPromises();
    return wrapper;
  };

  const fillAutoSend = async (wrapper, messageBody = 'Olá, tudo bem?') => {
    wrapper.vm.followUpForm.title = 'Retomar contato';
    wrapper.vm.followUpForm.dueAt = '2026-11-15T12:00';
    wrapper.vm.followUpForm.messageBody = messageBody;
    wrapper.vm.followUpForm.automationMode = 'auto_send_message';
    await flushPromises();
  };

  beforeEach(() => {
    alertSpy.mockClear();
    CrmKanbanAPI.getFollowUpMessagingWindow.mockResolvedValue({ data: {} });
    storeGetters['inboxes/getFilteredWhatsAppTemplates'] = () => [];
  });

  it('emits complete and cancel with the pending follow-up object', async () => {
    const wrapper = await mountFollowUps({ followUps: [pending] });
    const button = label =>
      wrapper.findAll('button').find(item => item.text() === label);

    await button('CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETE').trigger('click');
    await button('CRM_KANBAN.DRAWER.FOLLOW_UP_CANCEL').trigger('click');

    expect(wrapper.emitted('completeFollowUp')).toEqual([[pending]]);
    expect(wrapper.emitted('cancelFollowUp')).toEqual([[pending]]);
    wrapper.unmount();
  });

  it('separates active follow-ups from done/canceled ones without actions on the closed ones', async () => {
    const wrapper = await mountFollowUps({
      followUps: [pending, done, overdue, canceled],
    });

    expect(wrapper.vm.activeFollowUps.map(item => item.id)).toEqual([8, 9]);
    expect(wrapper.vm.completedFollowUps.map(item => item.id)).toEqual([
      10, 11,
    ]);
    const completedSection = wrapper
      .findAll('details')
      .find(item =>
        item.text().includes('CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETED_SECTION')
      );
    expect(completedSection.text()).toContain('Retorno feito');
    expect(completedSection.text()).toContain('Retorno cancelado');
    expect(completedSection.findAll('button')).toHaveLength(0);
    // One complete/cancel pair per active follow-up only.
    const completeButtons = wrapper
      .findAll('button')
      .filter(item => item.text() === 'CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETE');
    expect(completeButtons).toHaveLength(2);
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.DRAWER.NO_FOLLOW_UPS_TITLE'
    );
    wrapper.unmount();
  });

  it('shows the empty state only when there are no follow-ups and nothing is loading', async () => {
    const wrapper = await mountFollowUps({ isFetchingFollowUps: true });
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.DRAWER.NO_FOLLOW_UPS_TITLE'
    );

    await wrapper.setProps({ isFetchingFollowUps: false });
    expect(wrapper.text()).toContain('CRM_KANBAN.DRAWER.NO_FOLLOW_UPS_TITLE');
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.DRAWER.FOLLOW_UP_COMPLETED_SECTION'
    );
    wrapper.unmount();
  });

  it('requires a message body for auto-send and emits nothing without it', async () => {
    const wrapper = await mountFollowUps({ card: linkedCard });
    await fillAutoSend(wrapper, '   ');

    wrapper.vm.createFollowUp();

    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.ALERTS.FOLLOW_UP_MESSAGE_BODY_REQUIRED'
    );
    expect(wrapper.emitted('createFollowUp')).toBeUndefined();
    wrapper.unmount();
  });

  it('requires a template outside the 24h window and emits nothing without it', async () => {
    CrmKanbanAPI.getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_native_inbox: true },
    });
    const wrapper = await mountFollowUps({ card: linkedCard });
    await fillAutoSend(wrapper);

    wrapper.vm.createFollowUp();

    expect(alertSpy).toHaveBeenCalledWith(
      'CRM_KANBAN.ALERTS.FOLLOW_UP_TEMPLATE_REQUIRED'
    );
    expect(wrapper.emitted('createFollowUp')).toBeUndefined();
    wrapper.unmount();
  });

  it('sends the native template name and language outside the 24h window', async () => {
    storeGetters['inboxes/getFilteredWhatsAppTemplates'] = () => [
      { name: 'retomada_contato', language: 'pt_BR' },
    ];
    CrmKanbanAPI.getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_native_inbox: true },
    });
    const wrapper = await mountFollowUps({ card: linkedCard });
    await fillAutoSend(wrapper);
    wrapper.vm.followUpForm.nativeTemplateKey = 'retomada_contato::pt_BR';
    wrapper.vm.onNativeTemplateSelected();

    wrapper.vm.createFollowUp();

    expect(alertSpy).not.toHaveBeenCalled();
    const [[payload]] = wrapper.emitted('createFollowUp');
    expect(payload).toMatchObject({
      card_id: 5,
      conversation_id: 31,
      automation_mode: 'auto_send_message',
      metadata: {
        message_body: 'Olá, tudo bem?',
        template_name: 'retomada_contato',
        template_language: 'pt_BR',
      },
    });
    expect(payload.metadata).not.toHaveProperty(
      'whatsapp_api_message_template_id'
    );
    wrapper.unmount();
  });

  it('sends the WhatsApp API template id outside the 24h window', async () => {
    CrmKanbanAPI.getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_api_inbox: true },
    });
    const wrapper = await mountFollowUps({ card: linkedCard });
    await fillAutoSend(wrapper);
    wrapper.vm.followUpForm.whatsappApiTemplateId = '77';

    wrapper.vm.createFollowUp();

    expect(alertSpy).not.toHaveBeenCalled();
    const [[payload]] = wrapper.emitted('createFollowUp');
    expect(payload.metadata).toEqual({
      message_body: 'Olá, tudo bem?',
      whatsapp_api_message_template_id: 77,
    });
    wrapper.unmount();
  });
});

describe('CrmCardDrawer deal close', () => {
  const openCard = {
    id: 5,
    title: 'Card A',
    stage_id: 10,
    status: 'open',
    value_cents: 12345,
    currency: 'BRL',
  };
  const button = (wrapper, label) =>
    wrapper.findAll('button').find(item => item.text() === label);

  it('pre-fills the win value from the card and emits the amount in cents', async () => {
    const wrapper = mountDrawer({ canManageCards: true, card: openCard });
    await button(wrapper, 'CRM_KANBAN.DRAWER.WIN_DEAL').trigger('click');

    expect(wrapper.vm.showWinDialog).toBe(true);
    expect(wrapper.vm.winAmount).toBe(123.45);

    wrapper.vm.winAmount = '1500.5';
    await button(wrapper, 'CRM_KANBAN.DRAWER.WIN_CONFIRM').trigger('click');

    expect(wrapper.emitted('closeDeal')).toEqual([
      [{ result: 'won', value_cents: 150050, currency: 'BRL' }],
    ]);
    expect(wrapper.vm.showWinDialog).toBe(false);
    wrapper.unmount();
  });

  it('emits the lost reason when losing the deal', async () => {
    const wrapper = mountDrawer({ canManageCards: true, card: openCard });
    await button(wrapper, 'CRM_KANBAN.DRAWER.LOSE_DEAL').trigger('click');
    wrapper.vm.loseReason = 'Preço acima do orçamento';
    await button(wrapper, 'CRM_KANBAN.DRAWER.LOSE_CONFIRM').trigger('click');

    expect(wrapper.emitted('closeDeal')).toEqual([
      [{ result: 'lost', lost_reason: 'Preço acima do orçamento' }],
    ]);
    wrapper.unmount();
  });

  it('shows Reopen instead of win/lose on a won card', async () => {
    const wrapper = mountDrawer({
      canManageCards: true,
      card: { ...openCard, status: 'won' },
    });
    expect(button(wrapper, 'CRM_KANBAN.DRAWER.WIN_DEAL')).toBeUndefined();
    expect(button(wrapper, 'CRM_KANBAN.DRAWER.LOSE_DEAL')).toBeUndefined();

    await button(wrapper, 'CRM_KANBAN.DRAWER.REOPEN_DEAL').trigger('click');

    expect(wrapper.emitted('closeDeal')).toEqual([[{ result: 'reopen' }]]);
    wrapper.unmount();
  });

  it.each([
    ['CRM_KANBAN.DRAWER.WIN_DEAL', 'showWinDialog'],
    ['CRM_KANBAN.DRAWER.LOSE_DEAL', 'showLoseDialog'],
  ])(
    'Esc with the %s dialog open closes only the dialog',
    async (label, dialog) => {
      const wrapper = mountDrawer({ canManageCards: true, card: openCard });
      await button(wrapper, label).trigger('click');
      expect(wrapper.vm[dialog]).toBe(true);

      keyboard.handlers.Escape.action();
      await wrapper.vm.$nextTick();

      expect(wrapper.vm[dialog]).toBe(false);
      expect(wrapper.emitted('close')).toBeUndefined();

      keyboard.handlers.Escape.action();
      expect(wrapper.emitted('close')).toHaveLength(1);
      wrapper.unmount();
    }
  );
});

describe('CrmCardDrawer unsaved drafts when leaving', () => {
  const card = {
    id: 5,
    title: 'Card A',
    stage_id: 10,
    conversation: { id: 31, display_id: 77 },
  };
  const conversationRoute = {
    name: 'inbox_conversation',
    params: { accountId: '1', conversation_id: 77 },
  };
  const exits = {
    X: wrapper =>
      wrapper.find('button[aria-label="GENERAL.CLOSE"]').trigger('click'),
    Esc: async () => keyboard.handlers.Escape.action(),
    'Open conversation': wrapper =>
      wrapper
        .findAll('button')
        .find(button => button.text() === 'CRM_KANBAN.DRAWER.OPEN_CONVERSATION')
        .trigger('click'),
  };
  const drafts = {
    'changed title': wrapper => {
      wrapper.vm.form.title = 'Título não salvo';
    },
    'changed value': wrapper => {
      wrapper.vm.form.valueAmount = '999';
    },
    'follow-up draft': wrapper => {
      wrapper.vm.followUpForm.title = 'Retorno em rascunho';
    },
  };
  const left = wrapper =>
    Boolean(wrapper.emitted('close')) || navigate.mock.calls.length > 0;

  beforeEach(() => navigate.mockClear());

  Object.entries(exits).forEach(([exitName, exit]) => {
    Object.entries(drafts).forEach(([draftName, makeDirty]) => {
      it(`${exitName} with a ${draftName} asks to discard and stays open`, async () => {
        const wrapper = mountDrawer({ canManageCards: true, card });
        makeDirty(wrapper);
        await wrapper.vm.$nextTick();

        await exit(wrapper);

        expect(wrapper.vm.discardOpen).toBe(true);
        expect(left(wrapper)).toBe(false);

        wrapper.vm.confirmDiscard();
        expect(left(wrapper)).toBe(true);
        wrapper.unmount();
      });
    });

    it(`${exitName} without changes leaves directly`, async () => {
      const wrapper = mountDrawer({ canManageCards: true, card });

      await exit(wrapper);

      expect(wrapper.vm.discardOpen).toBe(false);
      expect(left(wrapper)).toBe(true);
      wrapper.unmount();
    });
  });

  it('confirming the discard on Open conversation navigates to it', async () => {
    const wrapper = mountDrawer({ canManageCards: true, card });
    wrapper.vm.form.title = 'Título não salvo';
    await exits['Open conversation'](wrapper);
    expect(navigate).not.toHaveBeenCalled();

    wrapper.vm.confirmDiscard();

    expect(navigate).toHaveBeenCalledWith(conversationRoute);
    wrapper.unmount();
  });

  it('keeps switching tabs free while a commercial draft is pending', async () => {
    const wrapper = mountDrawer({ canManageCards: true, card });
    wrapper.vm.form.title = 'Título não salvo';
    await wrapper.vm.$nextTick();

    await wrapper.findAll('button[role="tab"]').at(1).trigger('click');

    expect(wrapper.vm.discardOpen).toBe(false);
    expect(wrapper.vm.activeTab).not.toBe('summary');
    expect(wrapper.vm.form.title).toBe('Título não salvo');
    wrapper.unmount();
  });
});
