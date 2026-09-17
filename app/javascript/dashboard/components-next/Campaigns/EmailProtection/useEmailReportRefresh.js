import { onMounted, onBeforeUnmount } from 'vue';
// Late delivery events can arrive after sending pauses or finishes. One visible
// refresh per minute, at most ten per mount; manual refresh remains available.
export function useEmailReportRefresh(refresh) {
  let timer;
  let remaining = 10;
  let pending = false;
  onMounted(() => {
    timer = setInterval(async () => {
      if (document.visibilityState !== 'visible' || pending || !remaining)
        return;
      remaining -= 1;
      pending = true;
      try {
        await refresh();
      } finally {
        pending = false;
      }
      if (!remaining) clearInterval(timer);
    }, 60000);
  });
  onBeforeUnmount(() => clearInterval(timer));
}
