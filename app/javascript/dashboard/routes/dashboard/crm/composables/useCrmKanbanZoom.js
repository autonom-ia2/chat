import { computed, ref, watch } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { LocalStorage } from 'shared/helpers/localStorage';
import {
  KANBAN_ZOOM_CLASSES,
  KANBAN_ZOOM_DEFAULT,
  KANBAN_ZOOM_MIN,
  KANBAN_ZOOM_MAX,
  KANBAN_ZOOM_STORAGE_KEY,
  normalizeKanbanZoom,
} from '../helpers/kanbanZoom';

// Reuse the CRM layout/sidebar storage convention. Scope by browser, user and
// account, not by funnel. No CRM data request is needed to adjust presentation.
export function useCrmKanbanZoom() {
  const currentUser = useMapGetter('getCurrentUser');
  const accountId = useMapGetter('getCurrentAccountId');
  const zoom = ref(KANBAN_ZOOM_DEFAULT);
  const persistenceFailed = ref(false);
  const storageKey = computed(() => {
    const userId = currentUser.value?.id;
    return userId && accountId.value
      ? `${KANBAN_ZOOM_STORAGE_KEY}:${userId}:${accountId.value}`
      : null;
  });

  const restore = () => {
    zoom.value = normalizeKanbanZoom(
      storageKey.value ? LocalStorage.get(storageKey.value) : null
    );
    persistenceFailed.value = false;
  };
  watch(storageKey, restore, { immediate: true, flush: 'sync' });

  const setZoom = value => {
    if (!Number.isInteger(value)) return;
    const next = Math.max(KANBAN_ZOOM_MIN, Math.min(KANBAN_ZOOM_MAX, value));
    if (next === zoom.value) return;
    zoom.value = next;
    if (!storageKey.value) return;
    try {
      LocalStorage.set(storageKey.value, next);
      persistenceFailed.value = false;
    } catch {
      // Storage may be blocked; never claim an unsaved choice was saved.
      persistenceFailed.value = true;
    }
  };

  useEventListener(window, 'storage', event => {
    if (event.key === storageKey.value || event.key === null) restore();
  });

  return {
    zoom,
    zoomClass: computed(() => KANBAN_ZOOM_CLASSES[zoom.value]),
    setZoom,
    persistenceFailed,
  };
}
