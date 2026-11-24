// V2.3 — LOCAL message store for the "Copiloto Autonom.ia" chat widget.
//
// Self-contained reactive store (NOT a registered Vuex module, so it needs no change to
// store/index.js and stays update-safe). The thread is ephemeral and lives only while the
// widget is open. Records:
//   { id, message_type: 'user' | 'assistant', message: { content, reply_suggestion } }
// #3198 — a user record also carries what its bubble shows (GuideUserMessage): `texto`, the
// `anexos` sent with it and, for a voice note, `voz` (audio, transcription state). Files live in
// `arquivos` until the next send; the ready ones go with every question of the thread, like the Guia.
import { reactive, readonly, markRaw } from 'vue';

const state = reactive({
  messages: [],
  arquivos: [],
});

let nextId = 1;
let nextArquivoId = 1;

const revogar = url => {
  if (url) URL.revokeObjectURL(url);
};

const arquivosPendentes = () => state.arquivos.filter(item => !item.turno);

// `content` goes to the backend history; `texto` is what the bubble shows. The ready files that
// were waiting in the field go with this message.
const addUserMessage = (content, { texto = content, voz = null } = {}) => {
  const id = nextId;
  nextId += 1;
  const anexos = arquivosPendentes()
    .filter(item => item.estado === 'pronto')
    .map(item => {
      item.turno = id;
      return {
        id: item.id,
        nome: item.nome,
        tipo: item.tipo,
        previa: item.previa,
      };
    });
  state.messages.push({
    id,
    message_type: 'user',
    message: { content: voz ? '' : content },
    texto: voz ? '' : texto,
    anexos,
    voz: voz
      ? {
          audio: markRaw(voz.audio),
          url: voz.url,
          duracao: voz.duracao || 0,
          estado: 'transcrevendo',
          texto: '',
          erro: '',
        }
      : null,
  });
  return state.messages[state.messages.length - 1];
};

// The voice note's transcription. Ready: the spoken text becomes the message content (what the
// agent reads in the history). `false` when the message is gone ("Novo assunto").
const marcarVoz = (id, estado, { texto = '', erro = '' } = {}) => {
  const registro = state.messages.find(m => m.id === id);
  if (!registro?.voz) return false;
  registro.voz.estado = estado;
  registro.voz.erro = erro;
  if (estado === 'pronta') {
    registro.voz.texto = texto;
    registro.message.content = texto;
  }
  return true;
};

const addAssistantMessage = ({ content, replySuggestion = false } = {}) => {
  const record = {
    id: nextId,
    message_type: 'assistant',
    message: { content, reply_suggestion: replySuggestion },
  };
  nextId += 1;
  state.messages.push(record);
  return record;
};

const addArquivo = (nome, { tipo = 'documento', previa = null } = {}) => {
  const arquivo = {
    id: nextArquivoId,
    nome,
    estado: 'subindo',
    signedId: null,
    tipo,
    previa,
    turno: null,
  };
  nextArquivoId += 1;
  state.arquivos.push(arquivo);
  return arquivo.id;
};

// `false` when the file is gone ("Novo assunto" while it was uploading).
const marcarArquivo = (id, estado, signedId = null) => {
  const arquivo = state.arquivos.find(item => item.id === id);
  if (!arquivo) return false;
  arquivo.estado = estado;
  arquivo.signedId = signedId;
  return true;
};

const removeArquivo = id => {
  const indice = state.arquivos.findIndex(item => item.id === id);
  if (indice < 0) return;
  revogar(state.arquivos[indice].previa);
  state.arquivos.splice(indice, 1);
};

// Every ready file of the thread goes with each question: the agent has no memory of them.
const arquivosProntos = () =>
  state.arquivos
    .filter(item => item.estado === 'pronto')
    .map(item => item.signedId);

const reset = () => {
  state.arquivos.forEach(item => revogar(item.previa));
  state.messages.forEach(item => revogar(item.voz?.url));
  state.messages.splice(0, state.messages.length);
  state.arquivos.splice(0, state.arquivos.length);
};

// History for the backend chat call: [{ role: 'user' | 'assistant', content }].
const toHistory = () =>
  state.messages
    .filter(m => m.message?.content)
    .map(m => ({
      role: m.message_type === 'assistant' ? 'assistant' : 'user',
      content: m.message.content,
    }));

export const useAutonomiaCopilotStore = () => ({
  messages: readonly(state).messages,
  arquivos: readonly(state).arquivos,
  addUserMessage,
  marcarVoz,
  addAssistantMessage,
  addArquivo,
  marcarArquivo,
  removeArquivo,
  arquivosPendentes,
  arquivosProntos,
  reset,
  toHistory,
});

export default useAutonomiaCopilotStore;
