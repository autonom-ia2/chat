/* global axios */
import ApiClient from '../ApiClient';

class ConversationApi extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  get(
    {
      inboxId,
      status,
      assigneeType,
      page,
      labels,
      teamId,
      conversationType,
      sortBy,
      updatedWithin,
      crmPipelineId,
      pasta,
      daIa,
      esperandoMin,
      noFunil,
    },
    options = {}
  ) {
    return axios.get(this.url, {
      signal: options.signal,
      params: {
        inbox_id: inboxId,
        team_id: teamId,
        status,
        assignee_type: assigneeType,
        page,
        labels,
        conversation_type: conversationType,
        sort_by: sortBy,
        updated_within: updatedWithin,
        crm_pipeline_id: crmPipelineId,
        // #1809: Spam ou Lixeira da caixa de e-mail (ConversaCanal::ConversationFinderComPastas).
        pasta,
        // #1883: filtros pelo link do Números (Crm::ConversationFinderComFiltrosDoLink).
        da_ia: daIa ? 1 : undefined,
        esperando_min: esperandoMin || undefined,
        no_funil: noFunil ? 1 : undefined,
      },
    });
  }

  filter(payload, options = {}) {
    return axios.post(`${this.url}/filter`, payload.queryData, {
      signal: options.signal,
      params: {
        page: payload.page,
        sort_by: payload.sortBy,
      },
    });
  }

  search({ q }) {
    return axios.get(`${this.url}/search`, {
      params: {
        q,
        page: 1,
      },
    });
  }

  toggleStatus({ conversationId, status, snoozedUntil = null }) {
    return axios.post(`${this.url}/${conversationId}/toggle_status`, {
      status,
      snoozed_until: snoozedUntil,
    });
  }

  togglePriority({ conversationId, priority }) {
    return axios.post(`${this.url}/${conversationId}/toggle_priority`, {
      priority,
    });
  }

  assignAgent({ conversationId, agentId, assigneeType }) {
    return axios.post(`${this.url}/${conversationId}/assignments`, {
      assignee_id: agentId,
      assignee_type: assigneeType,
    });
  }

  assignTeam({ conversationId, teamId }) {
    const params = { team_id: teamId };
    return axios.post(`${this.url}/${conversationId}/assignments`, params);
  }

  // #1702: readReceipt = o atendente abriu a conversa; o servidor marca a última recebida como lida no WhatsApp.
  markMessageRead({ id, readReceipt = false }) {
    const url = `${this.url}/${id}/update_last_seen`;
    if (!readReceipt) return axios.post(url);
    return axios.post(url, { read_receipt: true });
  }

  markMessagesUnread({ id }) {
    return axios.post(`${this.url}/${id}/unread`);
  }

  toggleTyping({ conversationId, status, isPrivate }) {
    return axios.post(`${this.url}/${conversationId}/toggle_typing_status`, {
      typing_status: status,
      is_private: isPrivate,
    });
  }

  mute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/mute`);
  }

  unmute(conversationId) {
    return axios.post(`${this.url}/${conversationId}/unmute`);
  }

  meta({
    inboxId,
    status,
    assigneeType,
    labels,
    teamId,
    conversationType,
    crmPipelineId,
    daIa,
    esperandoMin,
    noFunil,
  }) {
    return axios.get(`${this.url}/meta`, {
      params: {
        inbox_id: inboxId,
        status,
        assignee_type: assigneeType,
        labels,
        team_id: teamId,
        conversation_type: conversationType,
        crm_pipeline_id: crmPipelineId,
        da_ia: daIa ? 1 : undefined,
        esperando_min: esperandoMin || undefined,
        no_funil: noFunil ? 1 : undefined,
      },
    });
  }

  sendEmailTranscript({ conversationId, email }) {
    return axios.post(`${this.url}/${conversationId}/transcript`, { email });
  }

  requestContactInfo(conversationId) {
    return axios.post(`${this.url}/${conversationId}/contact_info_request`);
  }

  updateCustomAttributes({ conversationId, customAttributes }) {
    return axios.post(`${this.url}/${conversationId}/custom_attributes`, {
      custom_attributes: customAttributes,
    });
  }

  fetchParticipants(conversationId) {
    return axios.get(`${this.url}/${conversationId}/participants`);
  }

  updateParticipants({ conversationId, userIds }) {
    return axios.patch(`${this.url}/${conversationId}/participants`, {
      user_ids: userIds,
    });
  }

  getAllAttachments(conversationId) {
    return axios.get(`${this.url}/${conversationId}/attachments`);
  }

  getInboxAssistant(conversationId) {
    return axios.get(`${this.url}/${conversationId}/inbox_assistant`);
  }

  delete(conversationId) {
    return axios.delete(`${this.url}/${conversationId}`);
  }
}

export default new ConversationApi();
