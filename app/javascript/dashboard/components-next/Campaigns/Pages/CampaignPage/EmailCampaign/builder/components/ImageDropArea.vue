<script setup>
// Shown over the canvas while a file is dragged over the editor page (#2908). It lets every pointer
// event through, so the drop still lands on the canvas or the page below it.
import { useI18n } from 'vue-i18n';

import { fileDragActive } from '../composables/fileDragState';

const { t } = useI18n();
</script>

<template>
  <Transition
    enter-active-class="transition-opacity duration-150"
    enter-from-class="opacity-0"
    leave-active-class="transition-opacity duration-150"
    leave-to-class="opacity-0"
  >
    <div
      v-if="fileDragActive"
      class="pointer-events-none absolute inset-3 z-20 flex flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-n-brand bg-n-brand/10"
    >
      <span
        class="flex size-14 items-center justify-center rounded-full bg-n-solid-1 shadow-md"
      >
        <span class="i-lucide-image-plus size-7 text-n-brand" />
      </span>
      <p
        class="m-0 rounded-xl bg-n-solid-1 px-4 py-2 text-base font-medium text-n-slate-12 shadow-md"
      >
        {{ t('CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.IMAGE_DROP.DROP_HERE') }}
      </p>
    </div>
  </Transition>
</template>
