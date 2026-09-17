import { onMounted, onBeforeUnmount, watch } from 'vue';
const ACTIVE_DELAY = 60000;
const MAX_IDLE_DELAY = 300000;
// Active work stays fresh. Idle reports still receive late delivery events,
// backing off to five minutes without an arbitrary end to updates.
export function useEmailReportRefresh(refresh, isActive = () => false) {
  let timer;
  let delay = ACTIVE_DELAY;
  let stopped = true;
  let pending = false;
  const schedule = () => {
    if (stopped) return;
    clearTimeout(timer);
    timer = setTimeout(async () => {
      if (document.visibilityState === 'visible') {
        pending = true;
        try {
          await refresh();
        } finally {
          pending = false;
          delay = isActive()
            ? ACTIVE_DELAY
            : Math.min(delay * 2, MAX_IDLE_DELAY);
          schedule();
        }
      } else {
        schedule();
      }
    }, delay);
  };
  watch(isActive, active => {
    if (!active) return;
    delay = ACTIVE_DELAY;
    if (!pending) schedule();
  });
  onMounted(() => {
    stopped = false;
    schedule();
  });
  onBeforeUnmount(() => {
    stopped = true;
    clearTimeout(timer);
  });
}
