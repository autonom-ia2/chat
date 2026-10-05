<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  origin: { type: String, default: '' },
  inboxName: { type: String, default: '' },
});
const { t } = useI18n();
const NS = 'CRM_KANBAN.TRACKED_LINKS.PAGE';
const domain = computed(() => {
  if (!props.origin) return t(`${NS}.WEBSITE_PREVIEW_DOMAIN`);
  try {
    return new URL(props.origin).host;
  } catch {
    return t(`${NS}.WEBSITE_PREVIEW_DOMAIN`);
  }
});
</script>

<template>
  <div>
    <div
      aria-hidden="true"
      class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
    >
      <div
        class="flex items-center gap-2 border-b border-n-weak bg-n-alpha-1 px-3 py-2"
      >
        <span class="flex gap-1">
          <span class="size-2 rounded-full bg-n-slate-6" />
          <span class="size-2 rounded-full bg-n-slate-6" />
          <span class="size-2 rounded-full bg-n-slate-6" />
        </span>
        <span
          class="min-w-0 flex-1 truncate rounded-md bg-n-alpha-2 px-2 py-0.5 text-center text-xs text-n-slate-11"
        >
          {{ domain }}
        </span>
      </div>
      <div class="grid gap-2 p-4">
        <span class="h-2.5 w-3/4 rounded-full bg-n-alpha-3" />
        <span class="h-2 w-full rounded-full bg-n-alpha-2" />
        <span class="h-2 w-2/3 rounded-full bg-n-alpha-2" />
        <span
          class="mt-2 inline-flex items-center justify-center gap-2 rounded-lg bg-n-teal-9 px-3 py-2 text-xs font-semibold text-white"
        >
          <span class="i-lucide-message-circle size-4" />
          {{ t(`${NS}.WEBSITE_PREVIEW_BUTTON`) }}
        </span>
      </div>
    </div>
    <span
      aria-hidden="true"
      class="i-lucide-arrow-down mx-auto my-2 block size-4 text-n-slate-10"
    />
    <div class="rounded-xl bg-n-teal-3 p-4">
      <p class="m-0 mb-3 text-xs font-medium text-n-teal-11">
        {{ inboxName || t(`${NS}.DESTINATION`) }}
      </p>
      <p
        class="m-0 break-words rounded-lg rounded-ss-none bg-n-solid-1 p-3 text-sm text-n-slate-12"
      >
        {{ t(`${NS}.WEBSITE_PREVIEW_MESSAGE`) }}
        <span class="mt-1 block font-mono text-xs text-n-slate-11">
          {{ t(`${NS}.WEBSITE_PREVIEW_CODE`) }}
        </span>
      </p>
      <p class="m-0 mt-3 text-xs text-n-slate-11">
        {{ t(`${NS}.WEBSITE_PREVIEW_HINT`) }}
      </p>
    </div>
  </div>
</template>
