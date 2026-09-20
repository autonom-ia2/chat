// Guia da Plataforma — LOCAL message store for the global guide widget.
//
// Self-contained reactive store (NOT a Vuex module → no store/index.js change, update-safe). The
// thread is global (not conversation-scoped) and ephemeral. Records mirror the components-next
// copilot bubble shape; assistant records also carry `navigation` (the screen the guide suggests)
// and `acao` (the action the guide proposes, which only runs after an explicit confirmation).
import { reactive, readonly } from 'vue';

const state = reactive({
  messages: [],
});

let nextId = 1;

// Acima disso não é recado para quem usa: é dump, stack trace ou corpo de resposta.
const MOTIVO_MAX_CARACTERES = 160;

// Procura uma sequência de EXATAMENTE 3 dígitos cujo valor caia em 100–599, o
// formato de um status HTTP. Varredura caractere a caractere porque regex é
// proibido neste repositório.
const temStatusHttp = texto => {
  let inicio = -1;

  for (let i = 0; i <= texto.length; i += 1) {
    const ehDigito = i < texto.length && texto[i] >= '0' && texto[i] <= '9';

    if (ehDigito) {
      if (inicio === -1) inicio = i;
    } else if (inicio !== -1) {
      const bloco = texto.slice(inicio, i);
      const numero = Number(bloco);
      if (bloco.length === 3 && numero >= 100 && numero <= 599) return true;
      inicio = -1;
    }
  }

  return false;
};

// O erro cru da plataforma às vezes é um recado ("Este funil não existe mais"),
// e às vezes é a tradução de um status para quem nunca vai olhar um log ("A
// plataforma respondeu 422."). Só o primeiro tipo ajuda. Devolve '' quando o
// motivo não serve, e aí quem chama mostra o texto genérico.
export const motivoUtilizavel = motivo => {
  if (typeof motivo !== 'string') return '';

  const texto = motivo.trim();
  if (!texto || texto.length > MOTIVO_MAX_CARACTERES) return '';

  return temStatusHttp(texto) ? '' : texto;
};

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

// Devolve `false` quando o registro não existe mais — troca de conta ou "Nova
// conversa" durante os segundos da execução. Quem chama precisa saber disso:
// a ação já rodou no servidor, e sem esse retorno o desfecho sumia em silêncio.
const marcarAcao = (id, estado, resultado = null) => {
  const registro = state.messages.find(m => m.id === id);
  if (!registro) return false;
  registro.acaoEstado = estado;
  registro.acaoResultado = resultado;
  return true;
};

export const useAutonomiaGuideStore = () => ({
  messages: readonly(state).messages,
  addUserMessage,
  addAssistantMessage,
  marcarAcao,
  reset,
  toHistory,
});

export default useAutonomiaGuideStore;
