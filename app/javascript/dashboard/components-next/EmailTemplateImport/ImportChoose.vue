<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ImportStepDots from './ImportStepDots.vue';

const emit = defineEmits(['choose', 'cancel']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN.CHOOSE';
const isDragging = ref(false);

const OPTIONS = [
  { mode: 'file', icon: 'i-lucide-upload', key: 'FILE' },
  { mode: 'paste', icon: 'i-lucide-clipboard', key: 'PASTE' },
  { mode: 'url', icon: 'i-lucide-link', key: 'URL' },
];

const onDrop = event => {
  isDragging.value = false;
  const file = event.dataTransfer?.files?.[0];
  if (file) emit('choose', 'file', file);
};
</script>

<template>
  <div class="mx-auto w-full max-w-[55rem]">
    <div class="mb-4 flex items-center justify-between gap-3">
      <ImportStepDots :current="1" />
      <Button
        :label="t('EMAIL_IMPORT.SCREEN.CANCEL')"
        icon="i-lucide-x"
        ghost
        class="!min-h-11"
        @click="emit('cancel')"
      />
    </div>
    <h1
      class="mb-2 text-2xl font-semibold tracking-tight text-n-slate-12 sm:text-[1.75rem]"
    >
      {{ t(`${S}.TITLE`) }}
    </h1>
    <p class="mb-6 text-base text-n-slate-11">{{ t(`${S}.LEAD`) }}</p>
    <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
      <button
        v-for="option in OPTIONS"
        :key="option.mode"
        type="button"
        class="flex min-h-44 flex-col items-start gap-2 rounded-2xl border bg-n-solid-1 p-5 text-start shadow-sm transition-colors hover:border-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          option.mode === 'file' && isDragging
            ? 'border-n-brand bg-n-blue-2'
            : 'border-n-weak'
        "
        :data-mode="option.mode"
        @click="emit('choose', option.mode)"
        @dragover.prevent="isDragging = option.mode === 'file'"
        @dragleave="isDragging = false"
        @drop.prevent="onDrop"
      >
        <span
          class="mb-2 flex size-14 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
        >
          <span :class="option.icon" class="size-6" />
        </span>
        <b class="text-lg font-semibold text-n-slate-12">
          {{ t(`${S}.${option.key}_TITLE`) }}
        </b>
        <span class="text-sm leading-6 text-n-slate-11">
          {{ t(`${S}.${option.key}_TEXT`) }}
        </span>
        <span
          class="mt-auto flex items-center gap-1.5 pt-1 text-sm font-semibold text-n-blue-11"
        >
          {{ t(`${S}.${option.key}_GO`) }}
          <span class="i-lucide-arrow-right size-4" />
        </span>
      </button>
    </div>
    <div
      class="mt-5 flex gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-sm leading-6 text-n-slate-11"
    >
      <span class="i-lucide-info mt-1 size-4 shrink-0 text-n-blue-11" />
      <p class="mb-0">
        <b class="text-n-slate-12">{{ t(`${S}.HELP_TITLE`) }}</b>
        {{ t(`${S}.HELP_TEXT`) }}
        <br />
        {{ t(`${S}.HELP_RIGHTS`) }}
      </p>
    </div>
  </div>
</template>
