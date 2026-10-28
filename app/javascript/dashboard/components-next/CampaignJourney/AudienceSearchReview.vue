<script setup>
// Step "Revise" of the search by conversation (#2277): one screen that fills up while the conversations are
// read and becomes the review at the end. One number on top (who will receive), then the people in three
// groups (all with the same switch), who matches but cannot receive, and the audience name right before the
// save bar, which stays in sight. A search stopped by the cost or by the AI can still be saved as it is.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import AudienceSearchStatus from './AudienceSearchStatus.vue';
import AudienceFoundSection from './AudienceFoundSection.vue';
import AudienceSearchExtras from './AudienceSearchExtras.vue';
import { formatMoney, formatNumber } from './localeTag';

const props = defineProps({
  state: { type: String, required: true },
  progress: { type: Object, required: true },
  leftOut: { type: Object, required: true },
  busy: { type: Boolean, default: false },
});
const emit = defineEmits([
  'toggle',
  'set-all',
  'peek',
  'stop',
  'resume',
  'connect-key',
  'cancel',
  'save',
  'restart',
]);
const name = defineModel('name', { type: String, default: '' });

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const LEVELS = ['certeza', 'provavel', 'fora'];
// Only long lists get a name search; short ones read at a glance.
const SEARCH_FROM = 20;
const { t, locale } = useI18n();
const query = ref('');

const isRunning = computed(() => ['fila', 'lendo'].includes(props.state));
// Stopped by the cost or by the AI: the block above asks the main question, so saving steps back.
const isPaused = computed(() => ['teto', 'erro'].includes(props.state));
const isNobody = computed(
  () => props.state === 'pronto' && !props.progress.people.length
);
const canDecide = computed(
  () => !isRunning.value && props.progress.people.length > 0
);
const kept = computed(() =>
  props.progress.people.filter(person => !props.leftOut.has(person.id))
);
const countIn = level =>
  kept.value.filter(person => person.confidence === level).length;
// "6 com certeza · 3 prováveis · 1 que você pôs", without the groups that have nobody in the list.
const composition = computed(() =>
  [
    ['COMPOSITION_SURE', countIn('certeza')],
    ['COMPOSITION_LIKELY', countIn('provavel')],
    ['COMPOSITION_ADDED', countIn('fora')],
  ]
    .filter(([, count]) => count > 0)
    .map(([key, count]) => t(`${NS}.${key}`, { count }, count))
);
const canSave = computed(
  () => kept.value.length > 0 && Boolean(name.value.trim())
);
const visible = computed(() => {
  const term = query.value.trim().toLocaleLowerCase();
  if (!term) return props.progress.people;
  return props.progress.people.filter(person =>
    person.name.toLocaleLowerCase().includes(term)
  );
});
const groups = computed(() =>
  LEVELS.map(level => ({
    level,
    people: visible.value.filter(person => person.confidence === level),
  })).filter(group => group.people.length)
);
const nobodyText = computed(() =>
  t(`${NS}.NOBODY_TEXT`, {
    read: formatNumber(props.progress.read, locale.value),
    brl: formatMoney(props.progress.cost?.brl, 'BRL', locale.value),
  })
);
</script>

<template>
  <div class="flex flex-col gap-4" data-test="search-review">
    <section
      class="flex flex-col gap-6 rounded-3xl border border-n-weak bg-n-solid-1 p-5 shadow-sm md:p-8"
    >
      <!-- Ninguém combinou -->
      <div
        v-if="isNobody"
        class="flex flex-col items-center gap-3 py-6 text-center"
        data-test="nobody"
      >
        <span
          class="grid size-14 place-items-center rounded-2xl bg-n-slate-3 text-n-slate-11"
          aria-hidden="true"
        >
          <span class="i-lucide-search-x size-7" />
        </span>
        <h3 class="m-0 text-xl font-semibold text-n-slate-12">
          {{ t(`${NS}.NOBODY_TITLE`) }}
        </h3>
        <p class="m-0 max-w-md text-base text-n-slate-11">{{ nobodyText }}</p>
        <p
          v-if="progress.skipped"
          class="m-0 max-w-md text-sm text-n-amber-11"
          data-test="nobody-skipped"
        >
          {{
            t(`${NS}.SKIPPED_LINE`, {
              count: formatNumber(progress.skipped, locale),
            })
          }}
        </p>
        <Button
          :label="t(`${NS}.CHANGE_REQUEST`)"
          class="!min-h-12 !rounded-xl !px-6 !text-base"
          @click="emit('restart')"
        />
      </div>

      <template v-else>
        <AudienceSearchStatus
          :state="state"
          :progress="progress"
          :kept-count="kept.length"
          @stop="emit('stop')"
          @resume="emit('resume')"
          @connect-key="emit('connect-key')"
          @cancel="emit('cancel')"
          @restart="emit('restart')"
        />
        <Input
          v-if="progress.people.length >= SEARCH_FROM && !isRunning"
          v-model="query"
          type="search"
          :label="t(`${NS}.SEARCH_NAME`)"
          :placeholder="t(`${NS}.SEARCH_NAME_PLACEHOLDER`)"
          custom-input-class="!h-12"
          data-test="search-name"
        />
        <AudienceFoundSection
          v-for="group in groups"
          :key="group.level"
          :level="group.level"
          :people="group.people"
          :left-out="leftOut"
          :start-closed="group.level === 'fora'"
          :allow-all="group.level !== 'fora'"
          @toggle="person => emit('toggle', person)"
          @set-all="value => emit('set-all', group.level, value)"
          @peek="person => emit('peek', person)"
        />
        <AudienceSearchExtras
          v-if="canDecide"
          :left-aside="progress.leftAside"
        />
        <div
          v-if="canDecide"
          class="flex flex-col gap-2 border-t border-n-weak pt-5"
        >
          <Input
            v-model="name"
            :label="t(`${NS}.NAME_LABEL`)"
            :message="t(`${NS}.NAME_HINT`)"
            custom-input-class="!h-12"
            data-test="audience-name"
          />
        </div>
      </template>
    </section>

    <!-- Barra de salvar: sempre à vista, diz o que vai na lista -->
    <!-- ms-[4.5rem]: no celular, o botão do menu fica no canto de baixo; a barra começa depois dele -->
    <footer
      v-if="canDecide"
      class="sticky bottom-3 z-10 ms-[4.5rem] flex flex-col gap-1 rounded-2xl border border-n-weak bg-n-solid-1 p-2 shadow-lg md:ms-0 md:flex-row md:items-center md:justify-between md:gap-3 md:py-3 md:pe-3 md:ps-5"
      data-test="save-bar"
    >
      <p
        class="m-0 truncate px-1 text-xs text-n-slate-11 md:px-0 md:text-sm"
        data-test="composition"
      >
        {{ composition.join(' · ') }}
      </p>
      <Button
        v-if="isPaused"
        :label="t(`${NS}.SAVE_PARTIAL`, { count: kept.length })"
        variant="outline"
        color="blue"
        :disabled="!canSave"
        :is-loading="busy"
        class="!min-h-12 !rounded-xl !bg-n-solid-1 !px-5 !text-base"
        data-test="save-partial"
        @click="emit('save', false)"
      />
      <div
        v-else
        class="flex flex-col-reverse items-stretch md:flex-row md:items-center md:gap-2"
      >
        <Button
          :label="t(`${NS}.JUST_SAVE`)"
          variant="link"
          :disabled="!canSave || busy"
          class="!min-h-10 shrink-0 justify-center px-2 md:!min-h-11"
          data-test="just-save"
          @click="emit('save', false)"
        />
        <Button
          :label="t(`${NS}.SAVE_AND_CAMPAIGN`, { count: kept.length })"
          :disabled="!canSave"
          :is-loading="busy"
          class="!min-h-12 flex-1 !rounded-xl !px-5 !text-base md:flex-none"
          data-test="save"
          @click="emit('save', true)"
        />
      </div>
    </footer>
  </div>
</template>
