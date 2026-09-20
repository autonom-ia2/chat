// Guia da Plataforma — LOCAL message store for the global guide widget.
//
// Self-contained reactive store (NOT a Vuex module → no store/index.js change, update-safe). The
// thread is global (not conversation-scoped) and ephemeral. Records mirror the components-next
// copilot bubble shape; assistant records also carry `navigation` (the screen the guide suggests).
import { reactive, readonly } from 'vue';

const state = reactive({
  messages: [],
});

let nextId = 1;

const addUserMessage = content => {
  const record = { id: nextId, message_type: 'user', message: { content } };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const addAssistantMessage = ({
  content,
  navigation = null,
  acao = null,
} = {}) => {
  const record = {
    id: nextId,
    message_type: 'assistant',
    message: { content },
    navigation,
    // Ação proposta: fica aguardando confirmação e guarda o desfecho depois.
    acao,
    acaoEstado: acao ? 'aguardando' : null,
    acaoResultado: null,
  };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const reset = () => {
  state.messages.splice(0, state.messages.length);
};

// History for the backend chat call: [{ role: 'user' | 'assistant', content }].
const toHistory = () =>
  state.messages
    .filter(m => m.message?.content)
    .map(m => ({
      role: m.message_type === 'assistant' ? 'assistant' : 'user',
      content: m.message.content,
    }));

export const useAutonomiaGuideStore = () => ({
  messages: readonly(state).messages,
  addUserMessage,
  addAssistantMessage,
  marcarAcao: (id, estado, resultado = null) => {
    const registro = state.messages.find(m => m.id === id);
    if (!registro) return;
    registro.acaoEstado = estado;
    registro.acaoResultado = resultado;
  },
  reset,
  toHistory,
});

export default useAutonomiaGuideStore;
