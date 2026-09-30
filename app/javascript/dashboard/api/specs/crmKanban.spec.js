import crmKanban from '../crmKanban';
import ApiClient from '../ApiClient';

describe('#CrmKanbanAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
    patch: vi.fn(() => Promise.resolve()),
    delete: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.history.pushState({}, '', '/app/accounts/85/crm');
    window.axios = axiosMock;
  });

  afterEach(() => {
    vi.clearAllMocks();
    window.axios = originalAxios;
  });

  it('creates correct instance', () => {
    expect(crmKanban).toBeInstanceOf(ApiClient);
    expect(crmKanban).toHaveProperty('getPipelines');
    expect(crmKanban).toHaveProperty('createPipeline');
    expect(crmKanban).toHaveProperty('updatePipeline');
    expect(crmKanban).toHaveProperty('archivePipeline');
    expect(crmKanban).toHaveProperty('getPipelineInboxes');
    expect(crmKanban).toHaveProperty('createPipelineInbox');
    expect(crmKanban).toHaveProperty('deletePipelineInbox');
    expect(crmKanban).toHaveProperty('getInboxSettings');
    expect(crmKanban).toHaveProperty('updateInboxSetting');
    expect(crmKanban).toHaveProperty('createStage');
    expect(crmKanban).toHaveProperty('updateStage');
    expect(crmKanban).toHaveProperty('deleteStage');
    expect(crmKanban).toHaveProperty('reorderStages');
    expect(crmKanban).toHaveProperty('getStageAutomations');
    expect(crmKanban).toHaveProperty('createStageAutomation');
    expect(crmKanban).toHaveProperty('updateStageAutomation');
    expect(crmKanban).toHaveProperty('deleteStageAutomation');
    expect(crmKanban).toHaveProperty('getBoard');
    expect(crmKanban).toHaveProperty('getCards');
    expect(crmKanban).toHaveProperty('createCard');
    expect(crmKanban).toHaveProperty('createCardFromConversation');
    expect(crmKanban).toHaveProperty('showCard');
    expect(crmKanban).toHaveProperty('moveCard');
    expect(crmKanban).toHaveProperty('getFollowUps');
    expect(crmKanban).toHaveProperty('getFollowUpReminders');
    expect(crmKanban).toHaveProperty('dismissFollowUpReminder');
    expect(crmKanban).toHaveProperty('getFollowUpMessagingWindow');
    expect(crmKanban).toHaveProperty('createFollowUp');
    expect(crmKanban).toHaveProperty('updateFollowUp');
    expect(crmKanban).toHaveProperty('completeFollowUp');
    expect(crmKanban).toHaveProperty('cancelFollowUp');
    expect(crmKanban).toHaveProperty('getCalendarEvents');
  });

  it('fetches only the requested contact opportunities with account scope and abort signal', () => {
    const signal = new AbortController().signal;
    crmKanban.getContactOpportunities(
      42,
      { page: 2, result: 'won' },
      { signal }
    );
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/contacts/42/opportunities',
      {
        params: { page: 2, result: 'won' },
        signal,
      }
    );
  });

  it('fetches pipelines with account scope', () => {
    crmKanban.getPipelines();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines'
    );
  });

  it('fetches kanban board with filters and cursor payload', () => {
    const params = {
      pipeline_id: 7,
      limit_per_stage: 30,
      cursor_by_stage: { 3: 42 },
      stage_ids: [3],
    };
    crmKanban.getBoard(params);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/kanban',
      { params }
    );
  });

  it('creates and moves cards using CRM endpoints', () => {
    crmKanban.getCards({ pipeline_id: 7, page: 1 });
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards',
      { params: { pipeline_id: 7, page: 1 } }
    );

    crmKanban.showCard(10);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards/10'
    );

    crmKanban.createCard({ title: 'Novo lead' });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards',
      { card: { title: 'Novo lead' } }
    );

    crmKanban.createCardFromConversation({
      conversation_display_id: 22,
      pipeline_id: 7,
      stage_id: 3,
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards/from_conversation',
      {
        card: {
          conversation_display_id: 22,
          pipeline_id: 7,
          stage_id: 3,
        },
        conversation_id: undefined,
        conversation_display_id: 22,
      }
    );

    crmKanban.moveCard(10, 3);
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards/10/move',
      { stage_id: 3 }
    );
  });

  it('sends an optional idempotency header without adding it to card attributes', () => {
    crmKanban.createCard({ title: 'Opportunity' }, 'test-opportunity-key');
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/cards',
      { card: { title: 'Opportunity' } },
      { headers: { 'Idempotency-Key': 'test-opportunity-key' } }
    );
  });

  it('manages follow-ups and calendar using account scoped CRM endpoints', () => {
    crmKanban.getFollowUps({ card_id: 10 });
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups',
      { params: { card_id: 10 } }
    );

    crmKanban.getFollowUpMessagingWindow(42);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/messaging_window',
      { params: { conversation_id: 42 } }
    );

    crmKanban.createFollowUp({ card_id: 10, title: 'Retornar' });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups',
      { follow_up: { card_id: 10, title: 'Retornar' } }
    );

    crmKanban.updateFollowUp(5, { title: 'Novo título' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/5',
      { follow_up: { title: 'Novo título' } }
    );

    crmKanban.completeFollowUp(5);
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/5/complete'
    );

    crmKanban.cancelFollowUp(5);
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/5/cancel'
    );

    crmKanban.getFollowUpReminders();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/reminders'
    );

    crmKanban.dismissFollowUpReminder(5);
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/follow_ups/5/dismiss_reminder'
    );

    crmKanban.getCalendarEvents({ pipeline_id: 7 });
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/calendar/events',
      { params: { pipeline_id: 7 } }
    );
  });

  it('updates and archives pipelines using CRM endpoints', () => {
    crmKanban.updatePipeline(7, { name: 'Renovações' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7',
      { pipeline: { name: 'Renovações' } }
    );

    crmKanban.archivePipeline(7);
    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7'
    );
  });

  it('manages pipeline inbox links using CRM endpoints', () => {
    crmKanban.getPipelineInboxes(7);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7/inboxes'
    );

    crmKanban.createPipelineInbox(7, {
      inbox_id: 12,
      default_stage_id: 3,
      auto_create_card: true,
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7/inboxes',
      {
        pipeline_inbox: {
          inbox_id: 12,
          default_stage_id: 3,
          auto_create_card: true,
        },
      }
    );

    crmKanban.deletePipelineInbox(7, 12);
    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7/inboxes/12'
    );
  });

  it('manages CRM inbox settings using account scoped endpoints', () => {
    crmKanban.getInboxSettings();
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/inbox_settings'
    );

    crmKanban.updateInboxSetting(12, {
      crm_enabled: true,
      visibility_mode: 'assigned_only',
      auto_create_card: true,
      default_pipeline_id: 7,
      default_stage_id: 3,
    });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/inbox_settings/12',
      {
        inbox_setting: {
          crm_enabled: true,
          visibility_mode: 'assigned_only',
          auto_create_card: true,
          default_pipeline_id: 7,
          default_stage_id: 3,
        },
      }
    );
  });

  it('manages pipeline stages using CRM endpoints', () => {
    crmKanban.createStage(7, { name: 'Qualificação' });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/pipelines/7/stages',
      { stage: { name: 'Qualificação' } }
    );

    crmKanban.updateStage(10, { name: 'Proposta enviada' });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stages/10',
      { stage: { name: 'Proposta enviada' } }
    );

    crmKanban.reorderStages([10, 11]);
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stages/reorder',
      { stage_ids: [10, 11] }
    );

    crmKanban.deleteStage(10);
    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stages/10'
    );
  });

  it('manages stage automations using CRM endpoints', () => {
    crmKanban.getStageAutomations(10);
    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stages/10/stage_automations'
    );

    crmKanban.createStageAutomation(10, {
      name: 'On enter follow-up',
      trigger_event: 'on_enter',
      steps: [],
    });
    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stages/10/stage_automations',
      {
        stage_automation: {
          name: 'On enter follow-up',
          trigger_event: 'on_enter',
          steps: [],
        },
      }
    );

    crmKanban.updateStageAutomation(22, { enabled: false });
    expect(axiosMock.patch).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stage_automations/22',
      { stage_automation: { enabled: false } }
    );

    crmKanban.deleteStageAutomation(22);
    expect(axiosMock.delete).toHaveBeenCalledWith(
      '/api/v1/accounts/85/crm/stage_automations/22'
    );
  });
});
