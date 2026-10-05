<script setup>
// Passo 1 — Quem vai receber (#993, PRD §6.2, J1, J2, F3). Only saved audiences, with
// channel badges and counts. No audience at all: one sentence and one button. Creating an
// audience from here keeps the draft and comes back with it selected (J3).
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AudienceChannelBadges from './AudienceChannelBadges.vue';
import { searchAudiences } from './audienceChannels';

const props = defineProps({
  rows: { type: Array, default: () => [] },
  selectedId: { type: Number, default: null },
  isLoading: { type: Boolean, default: false },
  hasLoadError: { type: Boolean, default: false },
  returnedName: { type: String, default: '' },
  showLiveChat: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'create', 'continue', 'liveChat']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.AUDIENCE';
const { t, n, locale } = useI18n();

const search = ref('');
const visibleRows = computed(() => searchAudiences(props.rows, search.value));
const isEmpty = computed(
  () => !props.isLoading && !props.hasLoadError && !props.rows.length
);

const formatDate = value =>
  value
    ? new Date(value).toLocaleDateString(locale.value, { dateStyle: 'short' })
    : '';
</script>

<template>
  <section
    v-if="isEmpty"
    class="flex flex-col items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 px-6 py-10 text-center shadow-sm"
    data-test="audience-step-empty"
  >
    <span
      class="flex size-14 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"
      aria-hidden="true"
    >
      <span class="i-lucide-file-up size-7" />
    </span>
    <h2 class="m-0 text-xl font-semibold text-n-slate-12">
      {{ t(`${NS}.EMPTY_TITLE`) }}
    </h2>
    <p class="m-0 max-w-lg text-sm text-n-slate-11">
      {{ t(`${NS}.EMPTY_TEXT`) }}
    </p>
    <Button
      :label="t(`${NS}.EMPTY_ACTION`)"
      class="!min-h-11 min-w-56 !rounded-xl"
      data-test="create-audience"
      @click="emit('create')"
    />
    <span class="text-xs text-n-slate-11">{{ t(`${NS}.EMPTY_NOTE`) }}</span>
  </section>

  <template v-else>
    <p
      v-if="returnedName"
      class="mb-4 rounded-2xl border border-n-teal-6 bg-n-teal-2 px-4 py-3 text-sm text-n-slate-12"
      role="status"
      data-test="returned"
    >
      {{ t(`${NS}.RETURNED`, { name: returnedName }) }}
    </p>
    <section
      class="flex flex-col gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:p-5"
      data-test="audience-step"
    >
      <div>
        <h2 class="m-0 text-lg font-semibold text-n-slate-12">
          {{ t(`${NS}.TITLE`) }}
        </h2>
        <p class="m-0 mt-1 text-sm text-n-slate-11">{{ t(`${NS}.HINT`) }}</p>
      </div>
      <label
        class="flex min-h-11 w-full items-center gap-2 rounded-xl border border-n-weak px-3 focus-within:ring-2 focus-within:ring-n-brand sm:max-w-sm"
      >
        <span
          class="i-lucide-search size-4 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <input
          v-model="search"
          type="search"
          :aria-label="t(`${NS}.SEARCH`)"
          :placeholder="t(`${NS}.SEARCH`)"
          class="m-0 w-full min-w-0 !border-0 !bg-transparent !p-0 text-sm !shadow-none !outline-none focus:!ring-0"
        />
      </label>
      <p v-if="hasLoadError" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ t(`${NS}.LOAD_ERROR`) }}
      </p>
      <div v-if="isLoading && !rows.length" class="flex justify-center p-8">
        <Spinner />
      </div>
      <p
        v-else-if="!visibleRows.length && rows.length"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t(`${NS}.NO_MATCH`) }}
      </p>
      <ul v-else class="m-0 flex list-none flex-col gap-2 p-0">
        <li v-for="row in visibleRows" :key="row.id">
          <button
            type="button"
            class="flex min-h-[4.5rem] w-full items-center justify-between gap-3 rounded-xl border px-4 py-3 text-start focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :class="
              row.id === selectedId
                ? 'border-n-blue-8 bg-n-blue-2'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
            :aria-pressed="row.id === selectedId"
            :data-audience-option="row.id"
            @click="emit('select', row.id)"
          >
            <span class="flex min-w-0 flex-col gap-1.5">
              <strong class="truncate text-sm text-n-slate-12">
                {{ row.name }}
              </strong>
              <span class="flex flex-wrap items-center gap-2">
                <AudienceChannelBadges :badges="row.badges" />
                <span class="text-xs text-n-slate-11">
                  · {{ t(`${NS}.PEOPLE`, { count: n(row.people) }, row.people) }}
                  · {{ formatDate(row.createdAt) }}
                </span>
              </span>
            </span>
            <span
              v-if="row.id === selectedId"
              class="i-lucide-check size-5 shrink-0 text-n-blue-11"
              aria-hidden="true"
            />
          </button>
        </li>
      </ul>
      <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-dashed border-n-slate-7 px-4 py-3"
      >
        <p class="m-0 text-sm">
          <strong class="text-n-slate-12">{{ t(`${NS}.NOT_FOUND`) }}</strong>
          <span class="text-n-slate-11"> {{ t(`${NS}.NOT_FOUND_HINT`) }}</span>
        </p>
        <Button
          :label="t(`${NS}.CREATE_NEW`)"
          variant="outline"
          color="slate"
          size="sm"
          class="!min-h-11"
          data-test="create-new-audience"
          @click="emit('create')"
        />
      </div>
      <div
        v-if="showLiveChat"
        class="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-n-alpha-1 px-4 py-2"
      >
        <span class="text-xs text-n-slate-11">{{ t(`${NS}.LIVE_CHAT`) }}</span>
        <Button
          :label="t(`${NS}.LIVE_CHAT_ACTION`)"
          variant="ghost"
          size="sm"
          class="!min-h-11"
          @click="emit('liveChat')"
        />
      </div>
    </section>
    <div class="mt-5 flex justify-end">
      <Button
        :label="t(`${NS}.CONTINUE`)"
        :disabled="!selectedId"
        class="!min-h-11 !rounded-xl"
        data-test="continue-message"
        @click="emit('continue')"
      />
    </div>
  </template>
</template>
