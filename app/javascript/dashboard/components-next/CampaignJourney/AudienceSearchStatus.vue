<script setup>
// The top of the "Revise" screen while the list fills up (#2277). One block per moment: waiting in line
// (nothing paid yet, can give up), reading (progress and "Parar e ver quem já achamos"), stopped by the
// account's AI (continue from where it stopped), stopped at the agreed cost (never above it; asks before going
// on, and the save bar below is the way to stop there) and the result, with one number: who will receive.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { formatMoney, formatNumber } from './localeTag';

const props = defineProps({
  state: { type: String, required: true },
  progress: { type: Object, required: true },
  keptCount: { type: Number, required: true },
});
const emit = defineEmits([
  'stop',
  'resume',
  'connect-key',
  'cancel',
  'restart',
]);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const BUTTON = '!min-h-12 !rounded-xl !px-6 !text-base';
// Secondary buttons over a tinted block keep a solid background, so they never look disabled.
const SECONDARY = `${BUTTON} !bg-n-solid-1`;
const { t, locale } = useI18n();
const n = value => formatNumber(value, locale.value);
const brl = value => formatMoney(value, 'BRL', locale.value);
const usd = value => formatMoney(value, 'USD', locale.value);

const percent = computed(() =>
  props.progress.total
    ? Math.round((props.progress.read / props.progress.total) * 100)
    : 0
);
const counts = computed(() => ({
  read: n(props.progress.read),
  total: n(props.progress.total),
}));
// At the agreed cost: what the rest should cost, at the price paid so far per conversation.
const remaining = computed(() => {
  const { read, total, cost } = props.progress;
  return read ? (cost.brl / read) * (total - read) : 0;
});
const costText = computed(() =>
  t(`${NS}.COST_SO_FAR`, {
    brl: brl(props.progress.cost.brl),
    usd: usd(props.progress.cost.usd),
  })
);
</script>

<template>
  <div aria-live="polite" data-test="search-status">
    <!-- Na fila: ainda não custou nada -->
    <div
      v-if="state === 'fila'"
      class="flex flex-col items-start gap-4"
      data-test="status-queued"
    >
      <span
        class="grid size-14 place-items-center rounded-2xl bg-n-blue-3 text-n-blue-11"
        aria-hidden="true"
      >
        <span class="i-lucide-hourglass size-7 motion-safe:animate-pulse" />
      </span>
      <h3 class="m-0 text-xl font-semibold text-n-slate-12">
        {{ t(`${NS}.QUEUED_TITLE`) }}
      </h3>
      <p class="m-0 text-base leading-relaxed text-n-slate-11">
        {{ t(`${NS}.QUEUED_TEXT`, { count: progress.aheadMinutes }) }}
      </p>
      <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.CAN_LEAVE`) }}</p>
      <Button
        :label="t(`${NS}.CANCEL_QUEUED`)"
        variant="outline"
        color="slate"
        :class="SECONDARY"
        data-test="cancel-queued"
        @click="emit('cancel')"
      />
    </div>

    <!-- Lendo -->
    <div v-else-if="state === 'lendo'" class="flex flex-col gap-3">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h3 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t(`${NS}.READING`, counts) }}
        </h3>
        <span class="text-base font-medium text-n-teal-11">
          {{ t(`${NS}.FOUND_SO_FAR`, { count: progress.people.length }) }}
        </span>
      </div>
      <div
        class="h-2.5 overflow-hidden rounded-full bg-n-slate-3"
        role="progressbar"
        :aria-valuenow="percent"
        aria-valuemin="0"
        aria-valuemax="100"
        :aria-label="t(`${NS}.READING`, counts)"
      >
        <div
          class="h-full rounded-full bg-n-blue-9 transition-all duration-500"
          :style="{ width: `${percent}%` }"
        />
      </div>
      <div
        class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <p class="m-0 text-sm text-n-slate-11">{{ t(`${NS}.CAN_LEAVE`) }}</p>
        <Button
          :label="t(`${NS}.STOP`)"
          variant="outline"
          color="slate"
          :class="BUTTON"
          data-test="stop"
          @click="emit('stop')"
        />
      </div>
    </div>

    <!-- A IA da conta parou de responder: tenta de novo, ou fica com quem já achou -->
    <div
      v-else-if="state === 'erro'"
      class="flex flex-col gap-3 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-5"
      role="alert"
      data-test="status-error"
    >
      <h3 class="m-0 text-lg font-semibold text-n-ruby-11">
        {{ t(`${NS}.ERROR_TITLE`) }}
      </h3>
      <p class="m-0 text-base leading-relaxed text-n-slate-12">
        {{ t(`${NS}.ERROR_TEXT`, counts) }}
      </p>
      <p class="m-0 text-base leading-relaxed text-n-slate-12">
        {{ t(`${NS}.ERROR_KEEP`, { count: progress.people.length }) }}
      </p>
      <div class="flex flex-col-reverse gap-3 sm:flex-row">
        <Button
          :label="t(`${NS}.ERROR_FIX`)"
          variant="outline"
          color="slate"
          :class="SECONDARY"
          @click="emit('connect-key')"
        />
        <Button
          :label="t(`${NS}.ERROR_RETRY`)"
          :class="BUTTON"
          data-test="resume"
          @click="emit('resume')"
        />
      </div>
    </div>

    <!-- Chegou no valor aprovado: nunca passa dele sem perguntar -->
    <div
      v-else-if="state === 'teto'"
      class="flex flex-col gap-3 rounded-2xl border border-n-amber-6 bg-n-amber-2 p-5"
      role="alert"
      data-test="status-ceiling"
    >
      <h3 class="m-0 text-lg font-semibold text-n-slate-12">
        {{ t(`${NS}.CEILING_TITLE`, { spent: brl(progress.cost.brl) }) }}
      </h3>
      <p class="m-0 text-base leading-relaxed text-n-slate-12">
        {{ t(`${NS}.CEILING_WHY`) }}
        {{
          t(`${NS}.CEILING_TEXT`, {
            ...counts,
            more: brl(remaining),
            sum: brl(progress.cost.brl + remaining),
          })
        }}
      </p>
      <div class="flex flex-col gap-3 sm:flex-row">
        <Button
          :label="
            t(`${NS}.CEILING_GO`, { sum: brl(progress.cost.brl + remaining) })
          "
          :class="`${BUTTON} !h-auto !whitespace-normal !py-2`"
          data-test="resume"
          @click="emit('resume')"
        />
      </div>
    </div>

    <!-- Resultado (pronto ou parado pela pessoa): um número só -->
    <div
      v-else
      class="flex items-start justify-between gap-3"
      data-test="status-done"
    >
      <div class="flex flex-col gap-1">
        <h3 class="m-0 text-2xl font-bold text-n-slate-12">
          {{ t(`${NS}.RESULT_TITLE`, { count: keptCount }) }}
        </h3>
        <p class="m-0 text-sm leading-6 text-n-slate-11">
          {{
            state === 'parado'
              ? t(`${NS}.STOPPED_LINE`, counts)
              : t(`${NS}.RESULT_LINE`, { read: counts.read })
          }}
          {{ costText }}
        </p>
        <p
          v-if="progress.skipped"
          class="m-0 text-sm leading-6 text-n-amber-11"
          data-test="status-skipped"
        >
          {{ t(`${NS}.SKIPPED_LINE`, { count: n(progress.skipped) }) }}
        </p>
      </div>
      <button
        type="button"
        class="inline-flex min-h-11 min-w-11 shrink-0 items-center justify-center gap-2 self-start rounded-xl px-3 text-sm font-medium text-n-slate-12 ring-1 ring-inset ring-n-weak hover:bg-n-slate-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-label="t(`${NS}.CHANGE_REQUEST`)"
        data-test="restart"
        @click="emit('restart')"
      >
        <span class="i-lucide-pencil size-4" aria-hidden="true" />
        <span class="sm:hidden">{{ t(`${NS}.CHANGE_SHORT`) }}</span>
        <span class="hidden sm:inline">{{ t(`${NS}.CHANGE_REQUEST`) }}</span>
      </button>
    </div>
  </div>
</template>
