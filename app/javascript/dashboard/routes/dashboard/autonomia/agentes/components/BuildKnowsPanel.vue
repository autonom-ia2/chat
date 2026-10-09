<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  knows: { type: Object, default: () => ({}) },
  isInternal: { type: Boolean, default: false },
});

const { t } = useI18n();
const KNOW_KEYS = ['negocio', 'publico', 'quando_chama', 'nome'];
const rows = computed(() =>
  KNOW_KEYS.map(key => ({
    key,
    label: t(`AGENTS.CREATION.tell.knowLabels.${key}`),
    value: props.knows[key],
    answered:
      props.knows[key] !== null &&
      props.knows[key] !== undefined &&
      String(props.knows[key]).trim().length > 0,
  }))
);
const title = computed(() =>
  t(
    props.isInternal
      ? 'AGENTS.CREATION.tell.knowsInternalTitle'
      : 'AGENTS.CREATION.tell.knowsTitle'
  )
);
</script>

<template>
  <section
    class="flex flex-col gap-4 p-4 border rounded-2xl border-n-weak bg-n-solid-1"
    :aria-label="title"
  >
    <div class="flex items-start justify-between gap-3">
      <div>
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ title }}
        </h2>
        <p class="mt-1 text-xs leading-5 text-n-slate-11">
          {{ t('AGENTS.CREATION.tell.knowsDescription') }}
        </p>
      </div>
      <span
        v-if="rows.length"
        class="px-2 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ rows.filter(row => row.answered).length }}/{{ rows.length }}
      </span>
    </div>

    <ul v-if="rows.length" class="flex flex-col gap-2" role="list">
      <li
        v-for="row in rows"
        :key="row.key"
        class="flex items-start gap-3 px-3 py-2.5 rounded-xl bg-n-alpha-1"
      >
        <span
          class="flex items-center justify-center mt-0.5 rounded-full size-5 shrink-0"
          :class="
            row.answered
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-alpha-2 text-n-slate-10'
          "
          aria-hidden="true"
        >
          <i v-if="row.answered" class="i-lucide-check size-3.5" />
          <span v-else class="size-1.5 rounded-full bg-current" />
        </span>
        <span class="flex flex-col min-w-0 gap-0.5">
          <strong class="text-xs font-medium text-n-slate-12">{{
            row.label
          }}</strong>
          <span class="text-xs leading-5 text-n-slate-11">
            {{ row.value || t('AGENTS.CREATION.tell.notAnswered') }}
          </span>
        </span>
      </li>
    </ul>

    <p v-else class="text-xs leading-5 text-n-slate-11">
      {{ t('AGENTS.CREATION.tell.waitingForAnswers') }}
    </p>
  </section>
</template>
