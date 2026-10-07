<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ImportStepDots from './ImportStepDots.vue';
import ImportEmailFrame from './ImportEmailFrame.vue';
import ImportRows from './ImportRows.vue';
import { problemsOf, rowsOf } from './importRows';

const props = defineProps({
  data: { type: Object, required: true },
  resultHtml: { type: String, default: '' },
  isCompiling: { type: Boolean, default: false },
});

const emit = defineEmits(['act', 'continue', 'another']);

const { t } = useI18n();
const S = 'EMAIL_IMPORT.SCREEN.RESULT';
const device = ref('desktop');
const tab = ref('after');

const problems = computed(() => problemsOf(props.data));
const rows = computed(() => rowsOf(props.data));
const pending = computed(() => problems.value.length);
const hasBefore = computed(() => Boolean(props.data.preview_html));
const solvedSome = computed(() => (props.data.fixes || []).length > 0);

const sideTitle = computed(() => {
  if (pending.value)
    return t(
      `${S}.SIDE_PENDING_TITLE`,
      { count: pending.value },
      pending.value
    );
  return t(`${S}.${solvedSome.value ? 'SIDE_DONE_TITLE' : 'SIDE_READY_TITLE'}`);
});

const panes = computed(() => [
  {
    id: 'before',
    title: t(`${S}.BEFORE_TITLE`),
    note: t(`${S}.BEFORE_NOTE`),
    html: props.data.preview_html || '',
  },
  {
    id: 'after',
    title: t(`${S}.AFTER_TITLE`),
    note: t(`${S}.${pending.value ? 'AFTER_NOTE_PENDING' : 'AFTER_NOTE'}`),
    html: props.resultHtml,
  },
]);
const shownPanes = computed(() =>
  hasBefore.value
    ? panes.value
    : panes.value.filter(pane => pane.id === 'after')
);

const DEVICES = [
  { value: 'desktop', icon: 'i-lucide-monitor', key: 'DESKTOP' },
  { value: 'mobile', icon: 'i-lucide-smartphone', key: 'MOBILE' },
];
</script>

<template>
  <div class="w-full">
    <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
      <div>
        <ImportStepDots :current="3" class="mb-1.5" />
        <h1 class="mb-0 text-2xl font-semibold tracking-tight text-n-slate-12">
          {{
            pending
              ? t(`${S}.TITLE_PENDING`, { count: pending }, pending)
              : t(`${S}.TITLE_READY`)
          }}
        </h1>
      </div>
      <div class="flex flex-wrap gap-2">
        <div
          v-if="hasBefore"
          class="flex gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1 md:hidden"
          role="group"
        >
          <button
            v-for="option in ['before', 'after']"
            :key="option"
            type="button"
            class="min-h-11 rounded-lg px-4 text-sm font-medium"
            :class="
              tab === option ? 'bg-n-blue-3 text-n-blue-11' : 'text-n-slate-11'
            "
            :aria-pressed="tab === option"
            @click="tab = option"
          >
            {{ t(`${S}.${option === 'before' ? 'BEFORE' : 'AFTER'}`) }}
          </button>
        </div>
        <div
          class="hidden gap-1 rounded-xl border border-n-weak bg-n-solid-1 p-1 md:flex"
          role="group"
        >
          <button
            v-for="option in DEVICES"
            :key="option.value"
            type="button"
            class="flex min-h-11 items-center gap-2 rounded-lg px-4 text-sm font-medium"
            :class="
              device === option.value
                ? 'bg-n-blue-3 text-n-blue-11'
                : 'text-n-slate-11'
            "
            :aria-pressed="device === option.value"
            @click="device = option.value"
          >
            <span :class="option.icon" class="size-4" />
            {{ t(`${S}.${option.key}`) }}
          </button>
        </div>
      </div>
    </div>

    <div
      class="grid grid-cols-1 gap-4"
      :class="hasBefore ? 'md:grid-cols-2' : ''"
    >
      <section
        v-for="pane in shownPanes"
        :key="pane.id"
        class="min-w-0 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1"
        :class="hasBefore && tab !== pane.id ? 'hidden md:block' : ''"
        :data-pane="pane.id"
      >
        <header
          class="flex items-center justify-between gap-2 border-b border-n-weak px-4 py-3"
        >
          <b class="text-sm font-semibold text-n-slate-12">{{ pane.title }}</b>
          <small class="text-xs text-n-slate-11">{{ pane.note }}</small>
        </header>
        <div class="h-[26rem] overflow-y-auto bg-n-alpha-1 p-3 md:h-[30rem]">
          <div
            v-if="pane.id === 'after' && isCompiling"
            class="flex h-full items-center justify-center"
          >
            <Spinner />
          </div>
          <ImportEmailFrame
            v-else
            :html="pane.html"
            :title="pane.title"
            :device="device"
            class="mx-auto"
            :class="
              device === 'mobile' ? 'max-w-[23.4375rem]' : 'max-w-[37.5rem]'
            "
          />
        </div>
      </section>
    </div>

    <div
      class="mt-4 grid grid-cols-1 items-start gap-4 lg:grid-cols-[1fr_20rem]"
    >
      <ImportRows :rows="rows" @act="problem => emit('act', problem)" />
      <aside
        class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 lg:sticky lg:top-4"
      >
        <b class="block text-base font-semibold text-n-slate-12">{{
          sideTitle
        }}</b>
        <p class="mb-4 mt-1 text-sm text-n-slate-11">
          {{ t(`${S}.${pending ? 'SIDE_PENDING_TEXT' : 'SIDE_READY_TEXT'}`) }}
        </p>
        <div class="flex flex-col gap-2">
          <Button
            v-if="pending"
            :label="t(`${S}.SOLVE`)"
            size="lg"
            class="!min-h-12 w-full !rounded-xl"
            @click="emit('act', problems[0])"
          />
          <Button
            v-else
            :label="t(`${S}.CONTINUE`)"
            icon="i-lucide-arrow-right"
            trailing-icon
            size="lg"
            class="!min-h-12 w-full !rounded-xl"
            @click="emit('continue')"
          />
          <Button
            :label="t(`${S}.ANOTHER`)"
            slate
            outline
            class="!min-h-11 w-full !rounded-xl"
            @click="emit('another')"
          />
        </div>
      </aside>
    </div>
  </div>
</template>
