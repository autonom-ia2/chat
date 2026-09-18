import { onActivated, onBeforeUnmount, onDeactivated, watch } from 'vue';
import { useIntervalFn } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import { isRecipientImportActive } from 'dashboard/helper/emailCampaignImport';

const POLL_MS = 5000;

export const useRecipientImportPolling = campaign => {
  const store = useStore();
  let fetching = false;
  const { pause, resume } = useIntervalFn(
    async () => {
      if (fetching || !campaign.value) return;
      fetching = true;
      try {
        await store.dispatch('emailCampaigns/getOne', campaign.value.id);
      } catch {
        // Keep the last known state and retry on the next interval.
      } finally {
        fetching = false;
      }
    },
    POLL_MS,
    { immediate: false }
  );

  onBeforeUnmount(pause);
  onDeactivated(pause);
  onActivated(() => {
    if (isRecipientImportActive(campaign.value)) resume();
  });

  watch(
    () => isRecipientImportActive(campaign.value),
    active => {
      if (active) resume();
      else pause();
    },
    { immediate: true }
  );
};
