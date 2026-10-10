<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { sizeLabel } from './importErrors';

const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value =>
      ['not_email', 'too_big', 'failed', 'other'].includes(value),
  },
  code: { type: String, default: '' },
  // How the model came in: the sentences speak of a file, a pasted code or an address.
  source: {
    type: String,
    default: 'file',
    validator: value => ['file', 'paste', 'url'].includes(value),
  },
  fileName: { type: String, default: '' },
  fileSize: { type: Number, default: 0 },
});

const emit = defineEmits(['other', 'retry']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN.ERROR';

const LOOKS = {
  not_email: { icon: 'i-lucide-file-x', tone: 'bg-n-ruby-3 text-n-ruby-11' },
  too_big: { icon: 'i-lucide-file-up', tone: 'bg-n-amber-3 text-n-amber-11' },
  failed: { icon: 'i-lucide-refresh-cw', tone: 'bg-n-ruby-3 text-n-ruby-11' },
  other: {
    icon: 'i-lucide-circle-alert',
    tone: 'bg-n-amber-3 text-n-amber-11',
  },
};

const look = computed(() => LOOKS[props.kind]);
const title = computed(() => {
  if (props.kind === 'other')
    return t(`EMAIL_IMPORT.ERRORS.${props.code.toUpperCase()}`);
  return t(
    `${S}.${props.kind.toUpperCase()}.${props.source.toUpperCase()}_TITLE`
  );
});
const text = computed(() =>
  props.kind === 'other'
    ? ''
    : t(`${S}.${props.kind.toUpperCase()}.${props.source.toUpperCase()}_TEXT`)
);
const retry = computed(() => props.kind === 'failed');
const chip = computed(() =>
  props.fileName
    ? [props.fileName, props.fileSize ? sizeLabel(props.fileSize) : '']
        .filter(Boolean)
        .join(' · ')
    : ''
);
</script>

<template>
  <section
    class="mx-auto mt-6 flex max-w-[35rem] flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-6 py-9 text-center shadow-sm"
    role="alert"
  >
    <span
      class="flex size-[4.5rem] items-center justify-center rounded-2xl"
      :class="look.tone"
    >
      <span :class="look.icon" class="size-8" />
    </span>
    <span
      v-if="chip"
      class="flex max-w-full items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-1.5 text-sm text-n-slate-11"
    >
      <span class="i-lucide-file size-4 shrink-0" />
      <span class="truncate">{{ chip }}</span>
    </span>
    <h1 class="mb-0 text-xl font-semibold text-n-slate-12 sm:text-[1.375rem]">
      {{ title }}
    </h1>
    <p v-if="text" class="mb-0 text-base text-n-slate-11">{{ text }}</p>
    <Button
      :label="t(`${S}.${retry ? 'TRY_AGAIN' : 'TRY_OTHER'}`)"
      :icon="retry ? 'i-lucide-refresh-cw' : ''"
      size="lg"
      class="mt-2 !min-h-12 !rounded-xl"
      @click="retry ? emit('retry') : emit('other')"
    />
  </section>
</template>
