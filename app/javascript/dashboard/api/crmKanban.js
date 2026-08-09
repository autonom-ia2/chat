/* global axios */
import ApiClient from './ApiClient';

class CrmKanbanAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

  getPipelines() {
    return axios.get(`${this.url}/pipelines`);
  }

  createPipeline(payload) {
    return axios.post(`${this.url}/pipelines`, { pipeline: payload });
  }

  updatePipeline(id, payload) {
    return axios.patch(`${this.url}/pipelines/${id}`, { pipeline: payload });
  }

  archivePipeline(id) {
    return axios.delete(`${this.url}/pipelines/${id}`);
  }

  getPipelineInboxes(pipelineId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/inboxes`);
  }

  createPipelineInbox(pipelineId, payload) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/inboxes`, {
      pipeline_inbox: payload,
    });
  }

  deletePipelineInbox(pipelineId, inboxId) {
    return axios.delete(
      `${this.url}/pipelines/${pipelineId}/inboxes/${inboxId}`
    );
  }

  getInboxSettings() {
    return axios.get(`${this.url}/inbox_settings`);
  }

  updateInboxSetting(inboxId, payload) {
    return axios.patch(`${this.url}/inbox_settings/${inboxId}`, {
      inbox_setting: payload,
    });
  }

  // Public booking profiles (S6) — admin only.
  getBookingProfiles() {
    return axios.get(`${this.url}/booking_profiles`);
  }

  createBookingProfile(payload) {
    return axios.post(`${this.url}/booking_profiles`, {
      booking_profile: payload,
    });
  }

  updateBookingProfile(id, payload) {
    return axios.patch(`${this.url}/booking_profiles/${id}`, {
      booking_profile: payload,
    });
  }

  deleteBookingProfile(id) {
    return axios.delete(`${this.url}/booking_profiles/${id}`);
  }

  // Per-agent booking links (per_agent mode).
  getBookingAgentLinks(id) {
    return axios.get(`${this.url}/booking_profiles/${id}/agent_links`);
  }

  upsertBookingAgentLink(id, payload) {
    return axios.post(`${this.url}/booking_profiles/${id}/agent_links`, {
      agent_link: payload,
    });
  }

  deleteBookingAgentLink(id, linkId) {
    return axios.delete(
      `${this.url}/booking_profiles/${id}/agent_links/${linkId}`
    );
  }

  getStages(pipelineId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/stages`);
  }

  createStage(pipelineId, payload) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages`, {
      stage: payload,
    });
  }

  updateStage(stageId, payload) {
    return axios.patch(`${this.url}/stages/${stageId}`, { stage: payload });
  }

  deleteStage(stageId, targetStageId = null) {
    const url = `${this.url}/stages/${stageId}`;
    // No-target call keeps the exact single-arg signature callers/tests already expect.
    return targetStageId
      ? axios.delete(url, { params: { target_stage_id: targetStageId } })
      : axios.delete(url);
  }

  reorderStages(stageIds) {
    return axios.post(`${this.url}/stages/reorder`, { stage_ids: stageIds });
  }

  getStageAutomations(stageId) {
    return axios.get(`${this.url}/stages/${stageId}/stage_automations`);
  }

  createStageAutomation(stageId, payload) {
    return axios.post(`${this.url}/stages/${stageId}/stage_automations`, {
      stage_automation: payload,
    });
  }

  updateStageAutomation(id, payload) {
    return axios.patch(`${this.url}/stage_automations/${id}`, {
      stage_automation: payload,
    });
  }

  deleteStageAutomation(id) {
    return axios.delete(`${this.url}/stage_automations/${id}`);
  }

  getBoard(params = {}) {
    return axios.get(`${this.url}/kanban`, { params });
  }

  getCards(params = {}) {
    return axios.get(`${this.url}/cards`, { params });
  }

  createCard(payload) {
    return axios.post(`${this.url}/cards`, { card: payload });
  }

  createCardFromConversation(payload) {
    return axios.post(`${this.url}/cards/from_conversation`, {
      card: payload,
      conversation_id: payload.conversation_id,
      conversation_display_id: payload.conversation_display_id,
    });
  }

  showCard(id) {
    return axios.get(`${this.url}/cards/${id}`);
  }

  updateCard(id, payload) {
    return axios.patch(`${this.url}/cards/${id}`, { card: payload });
  }

  archiveCard(id) {
    return axios.delete(`${this.url}/cards/${id}`);
  }

  moveCard(id, stageId) {
    return axios.post(`${this.url}/cards/${id}/move`, { stage_id: stageId });
  }

  getFollowUps(params = {}) {
    return axios.get(`${this.url}/follow_ups`, { params });
  }

  getFollowUpReminders() {
    return axios.get(`${this.url}/follow_ups/reminders`);
  }

  dismissFollowUpReminder(id) {
    return axios.post(`${this.url}/follow_ups/${id}/dismiss_reminder`);
  }

  // Account-explicit variants for the global cross-account reminder popup:
  // the reminder may belong to an account other than the current route's,
  // so target the reminder's OWN account instead of accountIdFromRoute.
  completeFollowUpForAccount(accountId, id) {
    return axios.post(
      `${this.apiVersion}/accounts/${accountId}/crm/follow_ups/${id}/complete`
    );
  }

  dismissFollowUpReminderForAccount(accountId, id) {
    return axios.post(
      `${this.apiVersion}/accounts/${accountId}/crm/follow_ups/${id}/dismiss_reminder`
    );
  }

  getFollowUpMessagingWindow(conversationId, at) {
    return axios.get(`${this.url}/follow_ups/messaging_window`, {
      params: { conversation_id: conversationId, at: at || undefined },
    });
  }

  createFollowUp(payload) {
    return axios.post(`${this.url}/follow_ups`, { follow_up: payload });
  }

  updateFollowUp(id, payload) {
    return axios.patch(`${this.url}/follow_ups/${id}`, { follow_up: payload });
  }

  completeFollowUp(id) {
    return axios.post(`${this.url}/follow_ups/${id}/complete`);
  }

  cancelFollowUp(id) {
    return axios.post(`${this.url}/follow_ups/${id}/cancel`);
  }

  getCalendarEvents(params = {}) {
    return axios.get(`${this.url}/calendar/events`, { params });
  }

  getConversationCard(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/card`);
  }

  getConversationCardStages(conversationIds) {
    return axios.get(`${this.url}/conversations/card_stages`, {
      params: { conversation_ids: conversationIds },
    });
  }

  getAiSettings(pipelineId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/ai_settings`);
  }

  updateAiSettings(pipelineId, payload) {
    return axios.patch(
      `${this.url}/pipelines/${pipelineId}/ai_settings`,
      payload
    );
  }

  getCurrentAiSuggestion(cardId) {
    return axios.get(`${this.url}/cards/${cardId}/current_ai_suggestion`);
  }

  evaluateCardAi(cardId) {
    return axios.post(`${this.url}/cards/${cardId}/evaluate_ai`);
  }

  summarizeCardConversation(cardId) {
    return axios.post(`${this.url}/cards/${cardId}/summarize`);
  }

  // POST /crm/cards/:id/reset_auto_followup — re-arms the AI auto-follow-up
  // cadence for a card (clears the spent/exhausted state). Authorized as
  // update? server-side; renders the updated card (:show).
  resetAutoFollowup(cardId) {
    return axios.post(`${this.url}/cards/${cardId}/reset_auto_followup`);
  }

  acceptAiSuggestion(suggestionId) {
    return axios.post(`${this.url}/ai_suggestions/${suggestionId}/accept`);
  }

  dismissAiSuggestion(suggestionId) {
    return axios.post(`${this.url}/ai_suggestions/${suggestionId}/dismiss`);
  }

  closeCard(cardId, payload) {
    return axios.post(`${this.url}/cards/${cardId}/close`, payload);
  }

  // List "Lista & Calendário v2" — bulk actions, group summary, saved views,
  // and follow-up reschedule. See docs/crm_list_calendar_v2_prd.md.

  // POST /crm/cards/bulk — { ids, action, payload }. NOTE: the Rails routing
  // param `action` is reserved, so the bulk verb is sent as `action_name`
  // (the namespaced Cards::BulkController reads action_name/bulk_action).
  bulkAction({ ids, action, payload } = {}) {
    return axios.post(`${this.url}/cards/bulk`, {
      ids,
      action_name: action,
      payload,
    });
  }

  // GET /crm/cards/summaries — { pipeline_id, group_by, ...filters }.
  cardsGroupSummary(params = {}) {
    return axios.get(`${this.url}/cards/summaries`, { params });
  }

  getSavedViews(params = {}) {
    return axios.get(`${this.url}/saved_views`, { params });
  }

  createSavedView(payload) {
    return axios.post(`${this.url}/saved_views`, { saved_view: payload });
  }

  updateSavedView(id, payload) {
    return axios.patch(`${this.url}/saved_views/${id}`, {
      saved_view: payload,
    });
  }

  deleteSavedView(id) {
    return axios.delete(`${this.url}/saved_views/${id}`);
  }

  // POST /crm/follow_ups/:id/reschedule — { due_at }. Past-guard for
  // auto_send_message mode is enforced server-side.
  rescheduleFollowUp(id, dueAt) {
    return axios.post(`${this.url}/follow_ups/${id}/reschedule`, {
      due_at: dueAt,
    });
  }

  // CRM reports (Dashboard). `params` accepts { pipeline_id, since, until, group_by }.
  getReportPipelines() {
    return axios.get(`${this.url}/reports/pipelines`);
  }

  getReportSummary(params) {
    return axios.get(`${this.url}/reports/summary`, { params });
  }

  getReportFunnel(params) {
    return axios.get(`${this.url}/reports/funnel`, { params });
  }

  getReportAiVsHuman(params) {
    return axios.get(`${this.url}/reports/ai_vs_human`, { params });
  }

  getReportThroughput(params) {
    return axios.get(`${this.url}/reports/throughput`, { params });
  }

  getReportFollowUps(params) {
    return axios.get(`${this.url}/reports/follow_ups`, { params });
  }

  getReportWorkload(params) {
    return axios.get(`${this.url}/reports/workload`, { params });
  }

  getReportMeetings(params) {
    return axios.get(`${this.url}/reports/meetings`, { params });
  }
}

export default new CrmKanbanAPI();
