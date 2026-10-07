<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { chipSegments } from './chipSegments';
import { fieldLabelKey } from './importRows';

defineProps({
  rows: { type: Array, required: true },
});

const emit = defineEmits(['act']);

const { t, locale } = useI18n();

const TONES = {
  warn: {
    row: 'border-n-amber-6 bg-n-amber-2',
    icon: 'bg-n-amber-4 text-n-amber-11',
  },
  ok: { row: 'border-n-weak bg-n-solid-1', icon: 'bg-n-teal-3 text-n-teal-11' },
  info: {
    row: 'border-n-weak bg-n-solid-1',
    icon: 'bg-n-slate-3 text-n-slate-11',
  },
};

// The text of a row: plural count, params, a field label and chips (fields shown as code).
const segments = text => {
  const params = { ...(text.params || {}) };
  if (text.fieldChoice) params.choice = t(fieldLabelKey(text.fieldChoice));
  const translate = (key, values) =>
    text.count === undefined
      ? t(key, values)
      : t(key, { count: text.count, ...values }, text.count);
  return chipSegments(translate, text.key, text.chips || {}, params);
};

const chipClass = row => [
  'mx-0.5 rounded-md px-1.5 py-0.5 font-mono text-xs',
  row.tone === 'warn'
    ? 'bg-n-ruby-3 text-n-ruby-11'
    : 'bg-n-teal-3 text-n-teal-11',
];

const capitalize = value => value.charAt(0).toUpperCase() + value.slice(1);

const hintText = hint => {
  if (hint.list) {
    const items = hint.list.map(key => t(key));
    return `${capitalize(new Intl.ListFormat(locale.value.replace('_', '-'), { type: 'conjunction' }).format(items))}.`;
  }
  return hint.count === undefined
    ? t(hint.key, hint.params || {})
    : t(hint.key, { count: hint.count }, hint.count);
};
</script>

<template>
  <ul class="m-0 flex list-none flex-col gap-2.5 p-0">
    <li
      v-for="row in rows"
      :key="row.id"
      class="flex min-h-14 flex-wrap items-center gap-3 rounded-2xl border px-3 py-2.5 sm:flex-nowrap"
      :class="TONES[row.tone].row"
      :data-tone="row.tone"
    >
      <span
        class="flex size-8 shrink-0 items-center justify-center rounded-full"
        :class="TONES[row.tone].icon"
      >
        <span :class="row.icon" class="size-4" />
      </span>
      <div
        class="min-w-0 flex-1 basis-[calc(100%-2.75rem)] text-sm leading-5 text-n-slate-12 sm:basis-auto sm:text-base"
      >
        <p class="mb-0">
          <template v-for="(part, index) in segments(row.text)" :key="index">
            <code v-if="part.chip" :class="chipClass(row)">{{
              part.text
            }}</code>
            <template v-else>{{ part.text }}</template>
          </template>
        </p>
        <p v-if="row.hint" class="mb-0 text-xs text-n-slate-11 sm:text-sm">
          {{ hintText(row.hint) }}
        </p>
      </div>
      <Button
        v-if="row.action"
        :label="t(row.action.label)"
        :icon="row.action.icon || ''"
        slate
        outline
        class="!min-h-11 !rounded-xl ms-11 sm:ms-0"
        @click="emit('act', row.action.problem)"
      />
    </li>
  </ul>
</template>
