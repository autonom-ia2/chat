<script setup>
// "Colunas encontradas" + "Outras colunas" of Novo público (#993, PRD §6.6-1, B2). When
// the columns were not found for sure (needs_column_choice) every target is a choice;
// otherwise each one shows its column with "Trocar". Applying calls PATCH columns.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  NO_COLUMN,
  columnOptions,
  columnRows,
  currentMapping,
  hasContactColumn,
  mappingWith,
  otherColumns,
  sameMapping,
} from './columnChoice';

const props = defineProps({
  campaignImport: { type: Object, required: true },
  busy: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: true },
});

const emit = defineEmits(['apply']);

const NS = 'CAMPAIGN_JOURNEY.NEW_AUDIENCE.COLUMNS';
const { t, n } = useI18n();

const resolution = computed(() => props.campaignImport.schema_resolution || {});
const saved = computed(() => currentMapping(resolution.value));
const mapping = ref({ ...saved.value });
const editing = ref(new Set());

watch(saved, value => {
  mapping.value = { ...value };
  editing.value = new Set();
});

const isChoosing = computed(
  () => props.campaignImport.status === 'needs_column_choice'
);
const rows = computed(() => columnRows(resolution.value, mapping.value));
const options = computed(() =>
  columnOptions(resolution.value, t(`${NS}.NONE`))
);
const extras = computed(() => otherColumns(props.campaignImport, mapping.value));
const isChanged = computed(() => !sameMapping(mapping.value, saved.value));
const hasContact = computed(() => hasContactColumn(mapping.value));
const showApply = computed(
  () => props.canEdit && (isChoosing.value || isChanged.value)
);

const targetLabel = target => t(`${NS}.TARGETS.${target.toUpperCase()}`);
const countLabel = row =>
  ['phone', 'email'].includes(row.target)
    ? t(`${NS}.COUNT_VALID`, { count: n(row.count) })
    : t(`${NS}.COUNT_FILLED`, { count: n(row.count) });

const isEditing = target =>
  props.canEdit && (isChoosing.value || editing.value.has(target));

const startEditing = target => {
  editing.value = new Set([...editing.value, target]);
};

const choose = (target, value) => {
  mapping.value = mappingWith(mapping.value, target, value);
};

const choiceValue = row => (row.index === null ? NO_COLUMN : String(row.index));

const apply = () => {
  if (!hasContact.value) return;
  emit('apply', { ...mapping.value });
};
</script>

<template>
  <section
    class="overflow-hidden rounded-2xl border border-n-weak"
    data-test="audience-columns"
  >
    <header
      class="flex flex-wrap items-baseline justify-between gap-2 border-b border-n-weak bg-n-alpha-1 px-4 py-3"
    >
      <h2 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ isChoosing ? t(`${NS}.CHOOSE_TITLE`) : t(`${NS}.TITLE`) }}
      </h2>
      <p class="m-0 text-xs text-n-slate-11">
        {{ isChoosing ? t(`${NS}.CHOOSE_HINT`) : t(`${NS}.HINT`) }}
      </p>
    </header>
    <ul class="m-0 list-none p-0">
      <li
        v-for="row in rows"
        :key="row.target"
        :data-target="row.target"
        class="flex flex-wrap items-center justify-between gap-3 border-b border-n-weak px-4 py-3"
      >
        <strong class="min-w-28 text-sm text-n-slate-12">
          {{ targetLabel(row.target) }}
        </strong>
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <template v-if="isEditing(row.target)">
            <ChoiceSelect
              :model-value="choiceValue(row)"
              :options="options"
              :aria-label="
                t(`${NS}.CHOICE_ARIA`, { target: targetLabel(row.target) })
              "
              :disabled="busy"
              :data-choice="row.target"
              @update:model-value="value => choose(row.target, value)"
            />
          </template>
          <template v-else>
            <span v-if="row.header" class="text-sm text-n-slate-12">
              {{ t(`${NS}.COLUMN`, { header: row.header }) }}
            </span>
            <span v-else class="text-sm text-n-slate-11">
              {{ t(`${NS}.NOT_FOUND`) }}
            </span>
          </template>
          <span v-if="row.example" class="text-xs text-n-slate-11">
            {{ t(`${NS}.EXAMPLE`, { example: row.example }) }}
          </span>
          <span
            v-if="row.header"
            class="rounded-full bg-n-teal-3 px-2 py-0.5 text-xs font-medium text-n-teal-11"
          >
            {{ countLabel(row) }}
          </span>
          <span
            v-if="row.uncertain && !isChoosing && !isEditing(row.target)"
            class="rounded-full bg-n-amber-3 px-2 py-0.5 text-xs font-medium text-n-amber-11"
          >
            {{ t(`${NS}.UNCERTAIN`) }}
          </span>
          <Button
            v-if="canEdit && !isEditing(row.target)"
            :label="t(`${NS}.CHANGE`)"
            :aria-label="t(`${NS}.CHANGE_ARIA`, { target: targetLabel(row.target) })"
            variant="ghost"
            color="slate"
            size="sm"
            class="!min-h-11"
            :data-change="row.target"
            @click="startEditing(row.target)"
          />
        </div>
      </li>
      <li
        class="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
        data-test="other-columns"
      >
        <div>
          <strong class="text-sm text-n-slate-12">
            {{ t(`${NS}.OTHER_TITLE`) }}
          </strong>
          <p class="m-0 text-xs text-n-slate-11">{{ t(`${NS}.OTHER_HINT`) }}</p>
        </div>
        <ul v-if="extras.length" class="m-0 flex list-none flex-wrap gap-1.5 p-0">
          <li
            v-for="extra in extras"
            :key="extra"
            class="rounded-lg bg-n-alpha-2 px-2 py-1 text-xs font-medium text-n-slate-12"
          >
            {{ extra }}
          </li>
        </ul>
        <span v-else class="text-xs text-n-slate-11">
          {{ t(`${NS}.OTHER_NONE`) }}
        </span>
      </li>
    </ul>
    <footer
      v-if="showApply"
      class="flex flex-wrap items-center justify-end gap-3 border-t border-n-weak px-4 py-3"
    >
      <p v-if="!hasContact" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ t(`${NS}.NEED_CONTACT`) }}
      </p>
      <Button
        :label="t(`${NS}.APPLY`)"
        :disabled="!hasContact || busy"
        :is-loading="busy"
        class="!min-h-11 !rounded-xl"
        data-test="apply-columns"
        @click="apply"
      />
    </footer>
  </section>
</template>
