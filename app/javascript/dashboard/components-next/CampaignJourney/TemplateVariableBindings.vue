<script setup>
// "De onde vem cada parte da mensagem" (#993, PRD §6.3, B1, B1b). Each template variable
// comes from a contact field, an audience column or a fixed text. Prefilled choices from
// variable_suggestions carry the "Sugerido" badge. The coverage line says how many people
// are left out for a missing value, with an optional default text per variable.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import { BINDING_SOURCES, CONTACT_FIELDS } from './templateVariables';

const props = defineProps({
  variables: { type: Array, default: () => [] },
  bindings: { type: Object, default: () => ({}) },
  defaults: { type: Object, default: () => ({}) },
  columns: { type: Array, default: () => [] },
  // variable_coverage payload, or null while unknown
  coverage: { type: Object, default: null },
});

const emit = defineEmits(['bind', 'default']);

const NS = 'CAMPAIGN_JOURNEY.NEW_CAMPAIGN.VARIABLES';
const { t, n } = useI18n();

const SEPARATOR = ':';
const FIXED = BINDING_SOURCES.FIXED;

const display = key => `{{${key}}}`;

const groups = computed(() => [
  {
    label: t(`${NS}.GROUPS.CONTACT`),
    options: CONTACT_FIELDS.map(field => ({
      value: `${BINDING_SOURCES.CONTACT}${SEPARATOR}${field}`,
      label: t(`${NS}.CONTACT_FIELDS.${field.toUpperCase()}`),
    })),
  },
  ...(props.columns.length
    ? [
        {
          label: t(`${NS}.GROUPS.COLUMN`),
          options: props.columns.map(column => ({
            value: `${BINDING_SOURCES.COLUMN}${SEPARATOR}${column}`,
            label: t(`${NS}.COLUMN_OPTION`, { column }),
          })),
        },
      ]
    : []),
  {
    label: t(`${NS}.GROUPS.FIXED`),
    options: [{ value: FIXED, label: t(`${NS}.FIXED_OPTION`) }],
  },
]);

const choiceOf = binding => {
  if (!binding?.source) return '';
  if (binding.source === FIXED) return FIXED;
  return `${binding.source}${SEPARATOR}${binding.value}`;
};

const choose = (key, choice) => {
  if (choice === FIXED) {
    emit('bind', key, { source: FIXED, value: '' });
    return;
  }
  const at = choice.indexOf(SEPARATOR);
  emit('bind', key, {
    source: choice.slice(0, at),
    value: choice.slice(at + 1),
  });
};

const missing = computed(() =>
  Object.entries(props.coverage?.missing_by_variable || {})
    .filter(([, count]) => Number(count) > 0)
    .map(([key]) => key)
);
const excluded = computed(() => Number(props.coverage?.excluded_count) || 0);
const defaultKeys = computed(() => [
  ...new Set([
    ...missing.value,
    ...Object.keys(props.defaults).filter(key => props.defaults[key]),
  ]),
]);
</script>

<template>
  <section class="flex flex-col gap-2" data-test="variable-bindings">
    <h3 class="m-0 text-sm font-medium text-n-slate-12">{{ t(`${NS}.TITLE`) }}</h3>
    <ul class="m-0 list-none overflow-hidden rounded-xl border border-n-weak p-0">
      <li
        v-for="variable in variables"
        :key="variable.key"
        class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3 last:border-0"
        :data-variable="variable.key"
      >
        <div class="min-w-0">
          <strong class="text-sm text-n-slate-12">
            {{ display(variable.key) }}
          </strong>
          <p class="m-0 truncate text-xs text-n-slate-11">
            {{ variable.label }}
          </p>
        </div>
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <span
            v-if="bindings[variable.key]?.suggested"
            class="rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
            data-test="suggested"
          >
            {{ t(`${NS}.SUGGESTED`) }}
          </span>
          <ChoiceSelect
            :model-value="choiceOf(bindings[variable.key])"
            :groups="groups"
            :aria-label="t(`${NS}.SOURCE_ARIA`, { variable: display(variable.key) })"
            :placeholder="t(`${NS}.CHOOSE`)"
            @update:model-value="choice => choose(variable.key, choice)"
          />
          <Input
            v-if="bindings[variable.key]?.source === 'fixed'"
            :model-value="bindings[variable.key].value"
            :placeholder="t(`${NS}.FIXED_PLACEHOLDER`)"
            :aria-label="t(`${NS}.FIXED_ARIA`, { variable: display(variable.key) })"
            custom-input-class="!h-11"
            data-test="fixed-text"
            @update:model-value="
              value => emit('bind', variable.key, { source: 'fixed', value })
            "
          />
        </div>
      </li>
    </ul>
    <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.HINT`) }}</p>
    <div
      v-if="coverage && (excluded > 0 || defaultKeys.length)"
      class="flex flex-col gap-3 rounded-xl bg-n-amber-2 px-4 py-3"
      data-test="coverage-warning"
    >
      <p v-if="excluded > 0" class="m-0 text-sm text-n-slate-12" role="status">
        {{
          t(
            `${NS}.COVERAGE`,
            {
              count: n(excluded),
              variables: missing.map(display).join(', '),
            },
            excluded
          )
        }}
      </p>
      <p v-else class="m-0 text-sm text-n-teal-11" role="status">
        {{ t(`${NS}.COVERAGE_OK`) }}
      </p>
      <Input
        v-for="key in defaultKeys"
        :key="key"
        :model-value="defaults[key] || ''"
        :label="t(`${NS}.DEFAULT_LABEL`, { variable: display(key) })"
        :placeholder="t(`${NS}.DEFAULT_PLACEHOLDER`)"
        :message="t(`${NS}.DEFAULT_HINT`)"
        custom-input-class="!h-11"
        :data-default="key"
        @update:model-value="value => emit('default', key, value)"
      />
    </div>
    <p
      v-else-if="coverage"
      class="m-0 text-xs text-n-teal-11"
      data-test="coverage-ok"
    >
      {{ t(`${NS}.COVERAGE_OK`) }}
    </p>
  </section>
</template>
