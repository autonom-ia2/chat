/* global axios */
import ApiClient from './ApiClient';
import { pollAiRequest } from '../helper/aiRequestPolling';

// Agent-facing copilot for a live conversation (gated server-side by the kanban key).
class AutonomiaCopilotAPI extends ApiClient {
  constructor() {
    super('autonomia', { accountScoped: true });
  }

  // task: 'summarize' | 'draft' | 'rewrite' | 'refine'
  // draft/tone/instruction are used by rewrite/refine.
  // #1872: polling = { timeoutMs, signal } do pollAiRequest (opcional).
  run(conversationId, { task, draft, tone, instruction } = {}, polling = {}) {
    return pollAiRequest(
      axios.post(`${this.url}/conversations/${conversationId}/copilot`, {
        task,
        draft,
        tone,
        instruction,
      }),
      polling
    );
  }

  // #1872 — o copiloto está disponível para a conta (gates + chave da IA)? → { available }
  status() {
    return axios.get(`${this.url}/copilot/status`);
  }

  // #1872 — só o texto, sem conversa (e-mail novo da gaveta Escrever): task 'rewrite' | 'refine'.
  runText({ task, draft, tone, instruction } = {}, polling = {}) {
    return pollAiRequest(
      axios.post(`${this.url}/copilot/text`, {
        task,
        draft,
        tone,
        instruction,
      }),
      polling
    );
  }

  // V2.3 — list the account's internal/both agents selectable in the chat widget.
  listAgents(conversationId) {
    return axios.get(
      `${this.url}/conversations/${conversationId}/copilot/agents`
    );
  }

  // V2.3 — one chat turn against the selected agent.
  // history: [{ role: 'user' | 'assistant', content }]
  chat(conversationId, { agentId, message, history } = {}) {
    return pollAiRequest(
      axios.post(`${this.url}/conversations/${conversationId}/copilot/chat`, {
        agent_id: agentId,
        message,
        history,
      })
    );
  }
}

export default new AutonomiaCopilotAPI();
