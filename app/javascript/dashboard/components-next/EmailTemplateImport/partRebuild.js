// "Refazer para editar" (#1099, entrega D): the AI rebuilds one part that became an image. The
// server keeps the state of each part asked (`rebuilds`: running, done or failed) and what is left
// (`ai_rebuild`: available, left). This says what the screen shows for a part and when to keep
// asking the server for news.
export const RUNNING = 'running';
export const FAILED = 'failed';

const D = 'EMAIL_IMPORT.SCREEN.PART_DIALOG';

export const rebuildOf = (data, partId) => data?.rebuilds?.[partId] || null;

export const isRebuilding = data =>
  Object.values(data?.rebuilds || {}).some(entry => entry?.status === RUNNING);

// The "Refazer para editar" button of a part: { enabled, hint } (hint is an i18n key). Without
// the AI configured here, the product's message stays as it was ("chega em breve").
export const rebuildButton = (data, partId) => {
  const state = rebuildOf(data, partId)?.status;
  const ai = data?.ai_rebuild || {};
  if (state === RUNNING) return { enabled: false, hint: `${D}.RUNNING` };
  if (state === FAILED) return { enabled: false, hint: `${D}.FAILED` };
  if (!ai.available) return { enabled: false, hint: `${D}.SOON` };
  if (!(ai.left > 0)) return { enabled: false, hint: `${D}.USED_UP` };
  return { enabled: true, hint: `${D}.REBUILD_HINT` };
};
