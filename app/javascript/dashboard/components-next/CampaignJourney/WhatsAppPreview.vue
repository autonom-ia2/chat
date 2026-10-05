<script setup>
// "Como o cliente vê" (#993, PRD §6.3): the message as the first person of the audience
// gets it. Fixed beside the form on desktop, below it on phones (PRD §7).
import { useI18n } from 'vue-i18n';

defineProps({
  text: { type: String, default: '' },
});

const { t } = useI18n();
const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE';
</script>

<template>
  <aside
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4 lg:sticky lg:top-4"
    data-test="whatsapp-preview"
  >
    <h3 class="m-0 text-sm font-medium text-n-slate-12">
      {{ t(`${NS}.PREVIEW_TITLE`) }}
    </h3>
    <div class="rounded-2xl bg-n-teal-2 p-4">
      <p
        v-if="text"
        class="m-0 max-w-xs whitespace-pre-wrap rounded-2xl rounded-tl-sm bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 shadow-sm"
        data-test="preview-text"
      >
        {{ text }}
      </p>
      <p v-else class="m-0 text-sm text-n-slate-11">
        {{ t(`${NS}.PREVIEW_EMPTY`) }}
      </p>
    </div>
    <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.PREVIEW_HINT`) }}</p>
  </aside>
</template>
