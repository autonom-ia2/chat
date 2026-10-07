<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ImportStepDots from './ImportStepDots.vue';
import { progressLines, progressPercent } from './importProgress';

const props = defineProps({
  progress: { type: Object, default: () => ({}) },
  status: { type: String, default: 'queued' },
});

const emit = defineEmits(['leave', 'see']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN.PREPARING';
const lines = computed(() => progressLines(props.progress, props.status));
const percent = computed(() => progressPercent(props.progress, props.status));
</script>

<template>
  <div class="mx-auto w-full max-w-[55rem]">
    <ImportStepDots :current="2" />
    <section
      class="mx-auto mt-8 max-w-[35rem] rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-sm sm:p-8"
      aria-live="polite"
    >
      <h1 class="mb-1 text-2xl font-semibold tracking-tight text-n-slate-12">
        {{ t(`${S}.TITLE`) }}
      </h1>
      <p class="mb-5 text-base text-n-slate-11">{{ t(`${S}.LEAD`) }}</p>
      <ul class="m-0 flex list-none flex-col gap-3 p-0">
        <li
          v-for="line in lines"
          :key="line.key"
          class="flex min-h-9 items-center gap-3 text-base"
          :class="{
            'text-n-slate-12': line.state === 'done',
            'font-semibold text-n-slate-12': line.state === 'now',
            'text-n-slate-10': line.state === 'wait',
          }"
          :data-state="line.state"
        >
          <span
            class="flex size-8 shrink-0 items-center justify-center rounded-full"
            :class="{
              'bg-n-teal-3 text-n-teal-11': line.state === 'done',
              'bg-n-blue-3': line.state === 'now',
              'border-2 border-n-slate-6': line.state === 'wait',
            }"
          >
            <span v-if="line.state === 'done'" class="i-lucide-check size-4" />
            <Spinner v-else-if="line.state === 'now'" class="size-4" />
          </span>
          {{ t(`${S}.${line.key}`, line.params) }}
        </li>
      </ul>
      <div
        class="mt-5 h-2 overflow-hidden rounded-full bg-n-slate-4"
        role="progressbar"
        :aria-valuenow="percent"
        aria-valuemin="0"
        aria-valuemax="100"
      >
        <div
          class="h-full rounded-full bg-n-brand transition-all duration-500"
          :style="{ width: `${percent}%` }"
        />
      </div>
      <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
        <Button
          :label="t(`${S}.LEAVE`)"
          slate
          outline
          class="!min-h-11 !rounded-xl"
          @click="emit('leave')"
        />
        <Button
          :label="t(`${S}.SEE`)"
          icon="i-lucide-arrow-right"
          trailing-icon
          class="!min-h-11 !rounded-xl"
          :disabled="status !== 'ready'"
          @click="emit('see')"
        />
      </div>
    </section>
  </div>
</template>
