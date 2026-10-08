import { reactive, computed, watch, toRef } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';

// Module-level singleton cache + batch queue so every conversation row in the
// list resolves its CRM stage chip through ONE bulk request per tick (no N+1).
//   cache[conversationId] === undefined -> not fetched yet
//   cache[conversationId] === null      -> fetched, conversation has no card
//   cache[conversationId] === { stage_name, stage_color, pipeline_name, multiple_pipelines, subjects_count }
const cache = reactive({});
let queue = new Set();
let timer = null;

const flush = async () => {
  timer = null;
  const ids = [...queue];
  queue = new Set();
  if (!ids.length) return;
  try {
    const { data } = await CrmKanbanAPI.getConversationCardStages(ids);
    const payload = data?.payload || {};
    ids.forEach(id => {
      cache[id] = payload[id] || null;
    });
  } catch {
    // On failure leave entries unset so a later list render can retry.
    ids.forEach(id => {
      if (cache[id] === undefined) cache[id] = null;
    });
  }
};

const enqueue = id => {
  if (!id || cache[id] !== undefined) return;
  cache[id] = null; // mark in-flight to avoid duplicate requests
  queue.add(id);
  if (!timer) timer = setTimeout(flush, 50);
};

// Depois de criar ou trocar o assunto de uma conversa, o selo dela na lista precisa ser buscado de novo.
export function refreshCrmConversationStage(id) {
  if (!id) return;
  delete cache[id];
  enqueue(id);
}

export function useCrmConversationStage(conversationId) {
  const idRef = toRef(conversationId);
  watch(idRef, id => enqueue(id), { immediate: true });
  return computed(() => cache[idRef.value] || null);
}
