<script setup>
// Step "Conte" of the search by conversation (#2277). Same entrance as Automações (AutomacaoHeroi): a dark
// hero with one question and a white card with everything that is needed before searching: the request, the
// period (each option says how many conversations it has; an empty one cannot be picked) and the button last.
// The ideas fill the field. Enter sends, Shift+Enter breaks the line.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTextareaAutosize } from '@vueuse/core';
import { formatNumber } from './localeTag';

const props = defineProps({
  busy: { type: Boolean, default: false },
  periods: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['ask']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const PERIODS = ['7d', '30d', '3m', '12m', 'all'];
const IDEAS = ['EXAMPLE_1', 'EXAMPLE_2', 'EXAMPLE_3'];
const MAX_CHARACTERS = 400;
const MIN_CHARACTERS = 8;

const { t, locale } = useI18n();
// The request and the period live in the parent: "Mudar o pedido" comes back with them filled.
const request = defineModel('request', { type: String, default: '' });
const period = defineModel('period', { type: String, default: '12m' });
const { textarea } = useTextareaAutosize({ input: request });

const options = computed(() =>
  PERIODS.map(key => ({
    key,
    count: props.periods[key],
    isEmpty: props.periods[key] === 0,
  }))
);
const canAsk = computed(
  () =>
    (request.value || '').trim().length >= MIN_CHARACTERS &&
    props.periods[period.value] !== 0
);

const send = () => {
  if (!canAsk.value) return;
  emit('ask');
};

const onKey = event => {
  if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
  event.preventDefault();
  send();
};

const useIdea = key => {
  request.value = t(`${NS}.${key}`);
  textarea.value?.focus();
};
</script>

<template>
  <section
    class="relative overflow-hidden rounded-3xl bg-[#0D2344] px-5 py-8 text-white md:px-10 md:py-10"
    data-test="search-ask"
  >
    <span
      aria-hidden="true"
      class="pointer-events-none absolute -end-16 -top-24 size-80 rounded-full border-[3rem] border-n-blue-9 opacity-15"
    />
    <div class="relative flex max-w-3xl flex-col gap-5">
      <h2
        class="m-0 text-2xl font-bold leading-tight tracking-tight text-white md:text-[2rem]"
      >
        {{ t(`${NS}.HERO_TITLE`) }}
      </h2>
      <p class="m-0 text-base leading-relaxed text-white/75">
        {{ t(`${NS}.HERO_TEXT`) }}
      </p>
      <form
        class="flex flex-col gap-3 rounded-2xl bg-white p-3 shadow-2xl dark:bg-n-solid-1"
        @submit.prevent="send"
      >
        <label for="audience-request" class="sr-only">
          {{ t(`${NS}.REQUEST_LABEL`) }}
        </label>
        <textarea
          id="audience-request"
          ref="textarea"
          v-model="request"
          rows="2"
          :maxlength="MAX_CHARACTERS"
          :disabled="busy"
          :placeholder="t(`${NS}.REQUEST_PLACEHOLDER`)"
          class="!mb-0 max-h-48 min-h-[4.5rem] w-full resize-none overflow-y-auto rounded-none !border-0 !border-b !border-solid !border-n-weak bg-transparent px-2 pb-3 pt-2 text-base leading-relaxed text-n-slate-12 !outline-none placeholder:text-n-slate-10"
          data-test="request"
          @keydown="onKey"
        />
        <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
          <legend class="mb-2 px-2 text-sm font-medium text-n-slate-11">
            {{ t(`${NS}.PERIOD_LABEL`) }}
            <span class="font-normal sm:hidden">
              {{ t(`${NS}.PERIOD_COUNT_BELOW`) }}
            </span>
          </legend>
          <div
            class="grid grid-cols-5 gap-1 rounded-xl bg-n-slate-3 p-1"
            role="radiogroup"
            :aria-label="t(`${NS}.PERIOD_LABEL`)"
          >
            <button
              v-for="option in options"
              :key="option.key"
              type="button"
              role="radio"
              :aria-checked="period === option.key"
              :disabled="busy || option.isEmpty"
              :aria-disabled="option.isEmpty"
              :title="option.isEmpty ? t(`${NS}.PERIOD_EMPTY`) : undefined"
              class="flex min-h-12 flex-col items-center justify-center rounded-lg px-0.5 text-[0.8125rem] font-medium leading-tight sm:px-1 sm:text-sm transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-60"
              :class="
                period === option.key
                  ? 'bg-n-solid-1 text-n-slate-12 shadow'
                  : 'text-n-slate-11 hover:bg-n-slate-4'
              "
              :data-test="`period-${option.key}`"
              @click="period = option.key"
            >
              <span class="whitespace-nowrap">
                {{ t(`${NS}.PERIOD.${option.key.toUpperCase()}`) }}
              </span>
              <span
                v-if="option.count !== undefined"
                class="text-xs font-normal tabular-nums"
                :class="option.isEmpty ? 'text-n-slate-9' : 'text-n-slate-10'"
              >
                <span class="sm:hidden">{{
                  formatNumber(option.count, locale)
                }}</span>
                <span class="hidden sm:inline">
                  {{
                    option.isEmpty
                      ? t(`${NS}.PERIOD_NONE`)
                      : t(`${NS}.PERIOD_COUNT`, {
                          count: formatNumber(option.count, locale),
                        })
                  }}
                </span>
              </span>
            </button>
          </div>
        </fieldset>
        <button
          type="submit"
          :disabled="busy || !canAsk"
          class="inline-flex min-h-12 items-center justify-center gap-2 rounded-xl bg-n-brand px-6 text-base font-semibold text-white transition hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand disabled:cursor-not-allowed disabled:opacity-50 sm:self-end"
          data-test="find"
        >
          <span
            v-if="busy"
            class="i-lucide-loader-circle size-5 animate-spin"
            aria-hidden="true"
          />
          {{ busy ? t(`${NS}.THINKING`) : t(`${NS}.FIND`) }}
          <span
            v-if="!busy"
            class="i-lucide-arrow-right size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
      </form>
      <div class="flex flex-col gap-2">
        <span class="text-sm text-white/60">{{ t(`${NS}.IDEAS_LABEL`) }}</span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="key in IDEAS"
            :key="key"
            type="button"
            :disabled="busy"
            class="inline-flex min-h-11 items-center gap-2 rounded-xl bg-white/10 px-4 text-start text-sm text-white/90 ring-1 ring-inset ring-white/20 transition hover:bg-white/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-white"
            @click="useIdea(key)"
          >
            <span
              class="i-lucide-corner-down-left size-4 shrink-0 text-white/60"
              aria-hidden="true"
            />
            {{ t(`${NS}.${key}`) }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>
