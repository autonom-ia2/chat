<script setup>
// "Empresas" of Novo público (#993, PRD §6.6-4, D10, C4–C6). Shown only when the backend
// says companies are available for this audience (api-992.md §9).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import JourneySwitch from './JourneySwitch.vue';

const props = defineProps({
  // companiesBlock() result
  block: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.COMPANIES';
const { t, n } = useI18n();

const numbers = computed(() => {
  const source = props.block.result || props.block.preview;
  if (!source) return [];
  return [
    { key: 'NEW', value: source.created },
    { key: 'EXISTING', value: source.reused },
    { key: 'LINKED', value: source.linked },
    { key: 'KEPT', value: source.kept, warn: true },
  ].filter(
    item =>
      item.value !== null &&
      item.value !== undefined &&
      Number.isFinite(Number(item.value))
  );
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak p-4"
    data-test="audience-companies"
  >
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ t(`${NS}.TITLE`) }}
        </h2>
        <p v-if="block.column" class="m-0 mt-1 text-xs text-n-slate-11">
          {{ t(`${NS}.HINT`, { column: block.column }) }}
        </p>
      </div>
      <JourneySwitch
        :checked="block.create"
        :disabled="disabled"
        :label="block.create ? t(`${NS}.SWITCH_ON`) : t(`${NS}.SWITCH_OFF`)"
        :aria-label="t(`${NS}.SWITCH_ARIA`)"
        data-test="companies-switch"
        @toggle="emit('toggle', !block.create)"
      />
    </div>
    <p v-if="!block.create" class="m-0 text-xs text-n-slate-11">
      {{ t(`${NS}.OFF_HINT`) }}
    </p>
    <dl
      v-else-if="numbers.length"
      class="m-0 grid grid-cols-2 gap-3 md:grid-cols-4"
    >
      <div
        v-for="item in numbers"
        :key="item.key"
        class="flex flex-col-reverse rounded-xl p-3"
        :class="item.warn ? 'bg-n-amber-2' : 'bg-n-alpha-1'"
      >
        <dt class="text-xs text-n-slate-11">{{ t(`${NS}.${item.key}`) }}</dt>
        <dd class="m-0 text-2xl font-semibold tabular-nums text-n-slate-12">
          {{ n(Number(item.value)) }}
        </dd>
      </div>
    </dl>
  </section>
</template>
