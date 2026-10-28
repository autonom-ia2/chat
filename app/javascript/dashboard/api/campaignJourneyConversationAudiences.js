/* global axios */
import ApiClient from './ApiClient';

// "Novo público pedindo em palavras" (#2277): the account's own AI reads the conversations and builds the list.
// GET  .../campaign_journey/conversation_audiences/status            { has_own_key, periods, open_search_id }
// POST .../campaign_journey/conversation_audiences                   { request, period } → search (planning)
// GET  .../campaign_journey/conversation_audiences/:id               ?since= → search: plan, progress, cost, people
//                                                                     (with since: only who changed after that cursor)
// POST .../campaign_journey/conversation_audiences/:id/answer        { answer } → planning again
// POST .../campaign_journey/conversation_audiences/:id/start|stop|resume
// GET  .../campaign_journey/conversation_audiences/:id/conversation  ?person_id= → { payload: [message] }
// POST .../campaign_journey/conversation_audiences/:id/save          { name, person_ids } → { id, name, count }
class ConversationAudiencesAPI extends ApiClient {
  constructor() {
    super('campaign_journey/conversation_audiences', { accountScoped: true });
  }

  status() {
    return axios.get(`${this.url}/status`);
  }

  show(id, since) {
    return axios.get(`${this.url}/${id}`, { params: since ? { since } : {} });
  }

  answer(id, answer) {
    return axios.post(`${this.url}/${id}/answer`, { answer });
  }

  start(id) {
    return axios.post(`${this.url}/${id}/start`);
  }

  stop(id) {
    return axios.post(`${this.url}/${id}/stop`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  conversation(id, personId) {
    return axios.get(`${this.url}/${id}/conversation`, {
      params: { person_id: personId },
    });
  }

  save(id, { name, personIds }) {
    return axios.post(`${this.url}/${id}/save`, {
      name,
      person_ids: personIds,
    });
  }
}

export default new ConversationAudiencesAPI();
