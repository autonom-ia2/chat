import { onActivated, onBeforeUnmount, onDeactivated, onMounted } from 'vue';
import { RESULT_POLL_MS } from './resultMetrics';

// E2 (#1007): while the campaign is still sending, the result refreshes by itself every
// RESULT_POLL_MS (15s), only with the tab visible. Campaign pages live under <keep-alive>,
// so polling stops when the page is left and starts again when it comes back.
export function useResultPolling(refresh, isActive, delay = RESULT_POLL_MS) {
  let timer;
  let running = false;

  const stop = () => {
    running = false;
    clearTimeout(timer);
  };

  const tick = async () => {
    if (!running) return;
    if (isActive() && document.visibilityState === 'visible') {
      try {
        await refresh();
      } catch {
        // A failed refresh keeps the last numbers; the page shows its own error.
      }
    }
    if (running) timer = setTimeout(tick, delay);
  };

  const start = () => {
    stop();
    running = true;
    timer = setTimeout(tick, delay);
  };

  onMounted(start);
  onActivated(start);
  onDeactivated(stop);
  onBeforeUnmount(stop);

  return { start, stop };
}
