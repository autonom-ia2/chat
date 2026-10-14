import { reactive, computed, watch, toRef, ref } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// Module-level singleton cache + batch queue so every conversation row in the
// list resolves its CRM stage chip through ONE bulk request per tick (no N+1).
//   cache[conversationId] === undefined -> not fetched yet
//   cache[conversationId] === null      -> fetched, conversation has no card
//   cache[conversationId] === { stage_name, stage_color, pipeline_name, multiple_pipelines, subjects_count }
const cache = reactive({});
// Versão do pedido por conversa: uma resposta mais antiga que um refresh não sobrescreve o selo novo.
const versions = {};
let queue = new Set();
let timer = null;

const flush = async () => {
  timer = null;
  const ids = [...queue];
  queue = new Set();
  if (!ids.length) return;
  const requested = Object.fromEntries(ids.map(id => [id, versions[id]]));
  const isLatest = id => versions[id] === requested[id];
  try {
    const { data } = await CrmKanbanAPI.getConversationCardStages(ids);
    const payload = data?.payload || {};
    ids.filter(isLatest).forEach(id => {
      cache[id] = payload[id] || null;
    });
  } catch {
    // On failure leave entries unset so a later list render can retry.
    ids.filter(isLatest).forEach(id => {
      if (cache[id] === undefined) cache[id] = null;
    });
  }
};

const enqueue = id => {
  if (!id || cache[id] !== undefined) return;
  cache[id] = null; // mark in-flight to avoid duplicate requests
  versions[id] = (versions[id] || 0) + 1;
  queue.add(id);
  if (!timer) timer = setTimeout(flush, 50);
};

// Depois de criar ou trocar o assunto de uma conversa, o selo dela na lista precisa ser buscado de novo.
// O selo atual continua na tela até a resposta nova chegar, em vez de sumir e voltar.
export function refreshCrmConversationStage(id) {
  if (!id) return;
  versions[id] = (versions[id] || 0) + 1;
  queue.add(id);
  if (!timer) timer = setTimeout(flush, 50);
}

// Os assuntos de uma conversa mudaram (criado ou trocado o atual): painel, caixa de resposta e selo leem de novo.
export const crmSubjectsChange = ref({ conversationId: null, version: 0 });

export function notifyCrmSubjectsChanged(conversationId) {
  crmSubjectsChange.value = {
    conversationId,
    version: crmSubjectsChange.value.version + 1,
  };
  refreshCrmConversationStage(conversationId);
}

// Aviso em tempo real (#1145): o painel aberto lê de novo; o selo da lista só para conversa que já está na tela,
// para não pedir o selo de toda conversa da caixa a cada mensagem.
export function onCrmSubjectsChangedRemotely(conversationId) {
  crmSubjectsChange.value = {
    conversationId,
    version: crmSubjectsChange.value.version + 1,
  };
  if (cache[conversationId] !== undefined) {
    refreshCrmConversationStage(conversationId);
  }
}

export function useCrmConversationStage(conversationId) {
  const idRef = toRef(conversationId);
  watch(idRef, id => enqueue(id), { immediate: true });
  return computed(() => cache[idRef.value] || null);
}
