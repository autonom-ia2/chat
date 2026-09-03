/* global axios */
import ApiClient from '../ApiClient';

// #284 (2b) — FAQ suggestions extracted from resolved conversations, reviewed per agent.
class AutonomiaFaqSuggestionsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents', { accountScoped: true });
  }

  list(agentId, { status = 'pending', page = 1 } = {}) {
    return axios.get(`${this.url}/${agentId}/faq_suggestions`, {
      params: { status, page },
    });
  }

  // `edits` ({ question, answer }) is optional: when present, the suggestion is saved as `edited`.
  approve(agentId, suggestionId, edits = null) {
    return axios.post(
      `${this.url}/${agentId}/faq_suggestions/${suggestionId}/approve`,
      edits ? { faq_suggestion: edits } : {}
    );
  }

  ignore(agentId, suggestionId) {
    return axios.post(
      `${this.url}/${agentId}/faq_suggestions/${suggestionId}/ignore`
    );
  }
}

export default new AutonomiaFaqSuggestionsAPI();
