/* global axios */
import ApiClient from '../ApiClient';
import { pollAiRequest } from '../../helper/aiRequestPolling';

class AutonomiaAgentsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  // The list page owns cancellation of its account-scoped GET. Keep the
  // inherited call shape when no signal is supplied so older callers and
  // their request assertions remain unchanged.
  get({ signal } = {}) {
    return signal ? axios.get(this.url, { signal }) : axios.get(this.url);
  }

  update(id, data, { signal } = {}) {
    return signal
      ? axios.patch(`${this.url}/${id}`, data, { signal })
      : axios.patch(`${this.url}/${id}`, data);
  }

  delete(id, { signal } = {}) {
    return signal
      ? axios.delete(`${this.url}/${id}`, { signal })
      : axios.delete(`${this.url}/${id}`);
  }

  // `images` (optional) are base64 data-urls read inline by the model in this
  // turn only (multimodal). Empty/absent → identical to the text-only request.
  test(agentId, { message, history, images = [] }, { signal } = {}) {
    const payload = { message, history, images };
    return pollAiRequest(
      signal
        ? axios.post(`${this.url}/${agentId}/test`, payload, { signal })
        : axios.post(`${this.url}/${agentId}/test`, payload),
      { signal }
    );
  }

  publish(agentId, { inboxId, inboxIds, responseWindow = 'always' } = {}) {
    return axios.post(`${this.url}/${agentId}/publish`, {
      ...(inboxIds?.length ? { inbox_ids: inboxIds } : {}),
      ...(inboxId ? { inbox_id: inboxId } : {}),
      agent: { config: { response_window: responseWindow } },
    });
  }

  updateAvatar(agentId, avatar) {
    const formData = new FormData();
    formData.append('avatar', avatar);
    return axios.patch(`${this.url}/${agentId}/avatar`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  deleteAvatar(agentId) {
    return axios.delete(`${this.url}/${agentId}/avatar`);
  }

  suggest(agentId, { message, history }) {
    return pollAiRequest(
      axios.post(`${this.url}/${agentId}/suggest`, { message, history })
    );
  }

  analytics(agentId, { range = '7d', signal } = {}) {
    return axios.get(`${this.url}/${agentId}/analytics`, {
      params: { range },
      ...(signal ? { signal } : {}),
    });
  }

  // #284 — conversations behind one Performance outcome (handled, handed_off, ...).
  // Same `{ meta, payload }` envelope as the reports drilldown.
  analyticsConversations(agentId, { range = '7d', metric, signal } = {}) {
    return axios.get(`${this.url}/${agentId}/analytics/conversations`, {
      params: { range, metric },
      ...(signal ? { signal } : {}),
    });
  }

  // G2 — instruction version history (metadata always; instruction text only for manual agents).
  getInstructionVersions(agentId, { signal } = {}) {
    const endpoint = `${this.url}/${agentId}/instruction_versions`;
    return signal ? axios.get(endpoint, { signal }) : axios.get(endpoint);
  }

  restoreInstructionVersion(agentId, versionId) {
    return axios.post(
      `${this.url}/${agentId}/instruction_versions/${versionId}/restore`
    );
  }

  getHandoffTargets(agentId, { signal } = {}) {
    const endpoint = `${this.url}/${agentId}/handoff_targets`;
    return signal ? axios.get(endpoint, { signal }) : axios.get(endpoint);
  }

  updateQuoteChoices(agentId, choices) {
    return axios.patch(`${this.url}/${agentId}/quote_choices`, choices);
  }

  getTools(agentId, { signal } = {}) {
    const endpoint = `${this.url}/${agentId}/tools`;
    return signal ? axios.get(endpoint, { signal }) : axios.get(endpoint);
  }

  createTool(agentId, tool) {
    return axios.post(`${this.url}/${agentId}/tools`, { tool });
  }

  updateTool(agentId, toolId, tool) {
    return axios.patch(`${this.url}/${agentId}/tools/${toolId}`, { tool });
  }

  deleteTool(agentId, toolId) {
    return axios.delete(`${this.url}/${agentId}/tools/${toolId}`);
  }

  testTool(agentId, toolId, params = {}) {
    return axios.post(`${this.url}/${agentId}/tools/${toolId}/test`, {
      params,
    });
  }
}

export default new AutonomiaAgentsAPI();
