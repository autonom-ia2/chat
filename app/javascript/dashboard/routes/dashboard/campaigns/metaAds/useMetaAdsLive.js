import { onBeforeUnmount } from 'vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// Anúncios da Meta (#1073, #1088): mantém um número vivo enquanto a tela está aberta.
//
// `load` pede o número ao servidor (que só chama a Meta se o de hoje tiver mais de 2 minutos). Depois de cada
// resposta, confere de novo em REFRESH_MS com a aba visível, ou em CHECK_MS enquanto `waiting()` diz que há
// leitura ou carga em andamento — assim o "atualizando…" não fica preso se o aviso em tempo real se perder.
// Voltar para a aba recarrega na hora. O aviso em tempo real (crm.meta_ads.insights_updated) vai para
// `onEvent`, ou recarrega quando não há `onEvent`. Fora da tela não agenda nada: uma resposta que chega depois
// de sair não deixa timer órfão.
export const REFRESH_MS = 2 * 60 * 1000;
export const CHECK_MS = 20 * 1000;

export const useMetaAdsLive = ({ load, waiting = () => false, onEvent }) => {
  let timer = null;
  let stopped = true;

  const pageVisible = () => document.visibilityState !== 'hidden';

  const schedule = next => {
    clearTimeout(timer);
    if (stopped) return;
    timer = setTimeout(
      () => (pageVisible() ? next() : schedule(next)),
      waiting() ? CHECK_MS : REFRESH_MS
    );
  };

  // Falha de rede mantém o último número na tela; a próxima rodada tenta de novo.
  const reload = async () => {
    try {
      await load();
    } catch {
      // mantém o que já estava na tela
    } finally {
      schedule(reload);
    }
  };

  const onVisibility = () => {
    if (!stopped && pageVisible()) reload();
  };

  useEmitter(BUS_EVENTS.CRM_META_ADS_INSIGHTS_UPDATED, data => {
    if (stopped) return;
    if (!onEvent) {
      reload();
      return;
    }
    onEvent(data);
    schedule(reload);
  });

  const start = () => {
    stopped = false;
    document.addEventListener('visibilitychange', onVisibility);
    return reload();
  };

  const stop = () => {
    stopped = true;
    clearTimeout(timer);
    document.removeEventListener('visibilitychange', onVisibility);
  };

  onBeforeUnmount(stop);

  return { start, stop, reload };
};
