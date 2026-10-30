<script setup>
// One group of the people found (#2277): "Com certeza", "Provável" or "Ficaram de fora". The header says what
// the group means and how many are in the list; the first two put or take everyone at once. "Ficaram de fora"
// starts closed and out of the list and has no "Pôr todos": the person puts in one by one, after looking.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AudienceFoundPerson from './AudienceFoundPerson.vue';

const props = defineProps({
  level: { type: String, required: true },
  people: { type: Array, required: true },
  leftOut: { type: Object, required: true },
  startClosed: { type: Boolean, default: false },
  allowAll: { type: Boolean, default: true },
});
const emit = defineEmits(['toggle', 'set-all', 'peek']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.FROM_CONVERSATIONS';
const DOTS = {
  certeza: 'bg-n-teal-9',
  provavel: 'bg-n-blue-9',
  fora: 'bg-n-slate-8',
};
const { t } = useI18n();
const isOpen = ref(!props.startClosed);
const key = computed(() => props.level.toUpperCase());
const inList = computed(
  () => props.people.filter(person => !props.leftOut.has(person.id)).length
);
const allIn = computed(() => inList.value === props.people.length);
const listId = computed(() => `found-${props.level}`);
</script>

<template>
  <section class="flex flex-col" :data-test="`section-${level}`">
    <header
      class="flex items-center justify-between gap-3 border-b border-n-weak pb-2"
    >
      <button
        type="button"
        class="flex min-h-11 min-w-0 items-center gap-2 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :aria-expanded="isOpen"
        :aria-controls="listId"
        @click="isOpen = !isOpen"
      >
        <span
          class="i-lucide-chevron-down size-5 shrink-0 text-n-slate-11 transition-transform"
          :class="{ '-rotate-90 rtl:rotate-90': !isOpen }"
          aria-hidden="true"
        />
        <span class="size-2.5 shrink-0 rounded-full" :class="DOTS[level]" />
        <span
          class="flex min-w-0 flex-col sm:flex-row sm:items-baseline sm:gap-2"
        >
          <span class="truncate text-base font-semibold text-n-slate-12">
            {{ t(`${NS}.SECTIONS.${key}.TITLE`) }}
          </span>
          <span class="text-sm tabular-nums text-n-slate-11">
            {{
              t(`${NS}.IN_LIST_COUNT`, { count: inList, total: people.length })
            }}
          </span>
        </span>
      </button>
      <button
        v-if="allowAll"
        type="button"
        class="min-h-11 shrink-0 rounded-xl px-3 text-sm font-medium text-n-blue-11 hover:bg-n-blue-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :data-test="`set-all-${level}`"
        @click="emit('set-all', !allIn)"
      >
        {{ allIn ? t(`${NS}.ALL_OUT`) : t(`${NS}.ALL_IN`) }}
      </button>
    </header>
    <p class="m-0 mt-2 text-sm text-n-slate-11">
      {{ t(`${NS}.SECTIONS.${key}.HINT`) }}
    </p>
    <ul
      v-show="isOpen"
      :id="listId"
      class="m-0 flex list-none flex-col divide-y divide-n-weak p-0"
    >
      <AudienceFoundPerson
        v-for="person in people"
        :key="person.id"
        :person="person"
        :included="!leftOut.has(person.id)"
        @toggle="emit('toggle', person)"
        @peek="emit('peek', person)"
      />
    </ul>
  </section>
</template>
