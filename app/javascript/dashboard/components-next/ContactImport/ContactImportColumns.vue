<script setup>
// Importar contatos (#1006): "Colunas encontradas" with "Trocar" (ChoiceSelect, never a
// native select) and "Outras colunas", which become contact attributes.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  NO_COLUMN,
  columnsOf,
  columnLabel,
  columnEvidence,
  visibleTargets,
  attributeColumns,
  attributeProblems,
  formatCount,
} from './contactImportView';

const props = defineProps({
  contactImport: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
  showAttributes: { type: Boolean, default: false },
});

const mapping = defineModel({ type: Object, required: true });

const NS = 'CONTACT_IMPORT_JOURNEY';
const { t, locale } = useI18n();
const n = value => formatCount(locale.value, value);

const columns = computed(() => columnsOf(props.contactImport));
const fallback = number => t(`${NS}.COLUMNS.COLUMN_FALLBACK`, { number });

const options = computed(() => [
  { value: NO_COLUMN, label: t(`${NS}.COLUMNS.NONE`) },
  ...columns.value.map(column => ({
    value: column.index,
    label: columnLabel(column, fallback),
  })),
]);

const targetLabel = target => t(`${NS}.COLUMNS.TARGETS.${target.toUpperCase()}`);

const rows = computed(() =>
  visibleTargets(props.contactImport).map(target => {
    const column = columns.value.find(
      item => item.index === mapping.value[target]
    );
    const evidence = columnEvidence(target, column);
    return {
      target,
      label: targetLabel(target),
      evidence: evidence
        ? t(`${NS}.COLUMNS.${evidence.kind}`, { count: n(evidence.count || 0) })
        : null,
    };
  })
);

const attributes = computed(() => attributeColumns(props.contactImport));
const problems = computed(() => attributeProblems(props.contactImport));

const choose = (target, value) => {
  mapping.value = { ...mapping.value, [target]: value };
};
</script>

<template>
  <section
    class="overflow-hidden rounded-xl border border-n-weak"
    :aria-label="t(`${NS}.COLUMNS.TITLE`)"
  >
    <div
      class="flex flex-wrap items-center justify-between gap-2 border-b border-n-weak bg-n-slate-2 px-4 py-3"
    >
      <h2 class="mb-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.COLUMNS.TITLE`) }}
      </h2>
      <span class="text-xs text-n-slate-11">{{ t(`${NS}.COLUMNS.HINT`) }}</span>
    </div>
    <div
      v-for="row in rows"
      :key="row.target"
      class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3 last:border-0"
      :data-target="row.target"
    >
      <strong class="min-w-[7.5rem] text-sm text-n-slate-12">
        {{ row.label }}
      </strong>
      <div class="flex min-w-0 flex-wrap items-center gap-3">
        <span
          v-if="row.evidence"
          class="rounded-full bg-n-teal-3 px-2.5 py-1 text-xs font-medium text-n-teal-11"
        >
          {{ row.evidence }}
        </span>
        <ChoiceSelect
          :model-value="mapping[row.target]"
          :options="options"
          :disabled="disabled"
          :aria-label="t(`${NS}.COLUMNS.CHANGE`, { target: row.label })"
          @update:model-value="choose(row.target, $event)"
        />
      </div>
    </div>
    <div
      v-if="showAttributes"
      class="flex flex-wrap items-start justify-between gap-3 border-t border-n-weak px-4 py-3"
      data-test="attributes"
    >
      <div>
        <strong class="text-sm text-n-slate-12">
          {{ t(`${NS}.ATTRIBUTES.TITLE`) }}
        </strong>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t(`${NS}.ATTRIBUTES.HINT`) }}
        </p>
      </div>
      <ul v-if="attributes.length" class="m-0 flex list-none flex-wrap gap-2 p-0">
        <li
          v-for="attribute in attributes"
          :key="attribute.key"
          class="rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1 text-xs text-n-slate-12"
          :data-attribute="attribute.key"
        >
          {{ attribute.column }}
          <span v-if="!attribute.existing" class="ms-1 text-n-blue-11">
            · {{ t(`${NS}.ATTRIBUTES.NEW`) }}
          </span>
        </li>
      </ul>
      <p v-else class="mb-0 text-xs text-n-slate-11">
        {{ t(`${NS}.ATTRIBUTES.NONE`) }}
      </p>
      <p
        v-if="problems.kept"
        class="mb-0 w-full text-xs text-n-slate-11"
        data-test="attribute-kept"
      >
        {{
          t(
            `${NS}.ATTRIBUTES.KEPT`,
            { count: n(problems.kept) },
            problems.kept
          )
        }}
      </p>
      <div
        v-if="problems.count"
        class="w-full rounded-lg bg-n-amber-2 px-3 py-2 text-xs text-n-slate-12"
        data-test="attribute-problems"
      >
        <p class="mb-1 font-semibold">
          {{
            t(
              `${NS}.ATTRIBUTES.PROBLEMS`,
              { count: n(problems.count) },
              problems.count
            )
          }}
        </p>
        <ul class="m-0 list-none p-0">
          <li
            v-for="problem in problems.rows"
            :key="`${problem.row_number}-${problem.attribute}`"
          >
            {{
              t(`${NS}.ATTRIBUTES.PROBLEM_ROW`, {
                row: problem.row_number,
                attribute: problem.attribute,
              })
            }}
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>
