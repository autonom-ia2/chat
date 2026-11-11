<script setup>
// What happens to an image dropped or pasted on the canvas (#2908): uploading, failed (with "Tentar de
// novo" when retrying helps) or a warning. State lives in useImageDrop.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

import { useImageDrop } from '../composables/useImageDrop';

const { t } = useI18n();
const { uploadingCount, notice, dismissNotice } = useImageDrop();

const PREFIX = 'CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.IMAGE_DROP';

const message = computed(() => {
  if (!notice.value) return '';
  const count = notice.value.count || 1;
  return t(`${PREFIX}.${notice.value.key}`, { count }, count);
});
const uploadingMessage = computed(() =>
  t(
    `${PREFIX}.UPLOADING`,
    { count: uploadingCount.value },
    uploadingCount.value
  )
);
</script>

<template>
  <div
    v-if="uploadingCount > 0 || notice"
    class="pointer-events-none absolute inset-x-0 top-3 z-10 flex flex-col items-center gap-2 px-4"
  >
    <p
      v-if="uploadingCount > 0"
      role="status"
      class="pointer-events-auto m-0 flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-4 py-2.5 text-sm text-n-slate-12 shadow-md"
    >
      <span class="i-lucide-loader-circle size-4 animate-spin" />
      {{ uploadingMessage }}
    </p>
    <div
      v-if="notice"
      role="alert"
      class="pointer-events-auto flex max-w-xl flex-wrap items-center gap-3 rounded-xl border border-n-amber-6 bg-n-amber-3 px-4 py-2.5 text-sm text-n-amber-12 shadow-md"
    >
      <span class="i-lucide-circle-alert size-4 shrink-0" />
      <span class="min-w-0 flex-1">{{ message }}</span>
      <Button
        v-if="notice.retry"
        :label="t(`${PREFIX}.RETRY`)"
        size="sm"
        class="!min-h-11"
        @click="notice.retry()"
      />
      <Button
        :label="t(`${PREFIX}.CLOSE`)"
        size="sm"
        variant="ghost"
        color="slate"
        class="!min-h-11"
        @click="dismissNotice"
      />
    </div>
  </div>
</template>
