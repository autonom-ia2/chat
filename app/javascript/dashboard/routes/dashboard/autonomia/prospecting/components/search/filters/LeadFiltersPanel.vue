<script setup>
// Conteúdo da gaveta de filtros (Orth, FiltersDrawerV2): 4 grupos por intenção
// comercial, editados num rascunho. Nada muda para quem usa até "Aplicar";
// "Limpar tudo" aplica os filtros vazios na hora. O rascunho nasce dos filtros
// aplicados e volta para eles quando eles mudam por fora.
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import FilterGroupCard from './FilterGroupCard.vue';
import RankRangeSlider from './RankRangeSlider.vue';
import RatingOperatorField from './RatingOperatorField.vue';
import {
  RANK_SLIDER_MAX,
  RANK_SLIDER_MIN,
  advancedFilterGroupCounts,
  defaultAdvancedLeadFilters,
} from '../../../utils/advancedLeadFilters';

const props = defineProps({
  filters: { type: Object, required: true },
});

const emit = defineEmits(['apply']);

const { t } = useI18n();

const draftFrom = filters => ({ ...defaultAdvancedLeadFilters(), ...filters });
const draft = ref(draftFrom(props.filters));
// O operador da avaliação é estado do campo; a versão o recria junto do rascunho.
const draftVersion = ref(0);
watch(
  () => props.filters,
  filters => {
    draft.value = draftFrom(filters);
    draftVersion.value += 1;
  }
);

const groupCounts = computed(() => advancedFilterGroupCounts(draft.value));

const hasChoices = computed(() => [
  { value: '', label: t('PROSPECTING.SEARCH.FILTERS.ANY') },
  { value: 'yes', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.HAS') },
  { value: 'no', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.HAS_NOT') },
]);

const painFields = computed(() => [
  { key: 'has_website', label: t('PROSPECTING.SEARCH.FIELDS.HAS_SITE') },
  { key: 'has_photos', label: t('PROSPECTING.SEARCH.FIELDS.HAS_PHOTOS') },
]);
const yesOnlyFields = computed(() => [
  { key: 'open_now', label: t('PROSPECTING.SEARCH.FILTER_DRAWER.OPEN_NOW') },
  {
    key: 'has_opening_hours',
    label: t('PROSPECTING.SEARCH.FILTER_DRAWER.HAS_OPENING_HOURS'),
  },
]);

// A faixa 1 a 40 inteira não filtra: as alças nos extremos gravam vazio.
const rankMin = computed({
  get: () => Number(draft.value.outside_top || 0) + RANK_SLIDER_MIN,
  set: value => {
    draft.value.outside_top = value > RANK_SLIDER_MIN ? value - 1 : '';
  },
});
const rankMax = computed({
  get: () =>
    Math.min(
      Number(draft.value.search_rank_max || RANK_SLIDER_MAX),
      RANK_SLIDER_MAX
    ),
  set: value => {
    draft.value.search_rank_max = value < RANK_SLIDER_MAX ? value : '';
  },
});

const reviewsMin = computed({
  get: () => draft.value.reviews_min,
  set: value => {
    draft.value.reviews_min = value === '' ? '' : Math.max(0, Number(value));
  },
});

const toggleYesOnly = (key, checked) => {
  draft.value[key] = checked ? 'yes' : '';
};

const apply = () => emit('apply', { ...draft.value });
const clearAll = () => emit('apply', defaultAdvancedLeadFilters());
</script>

<template>
  <div class="grid gap-4">
    <FilterGroupCard
      :title="t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.PAIN.TITLE')"
      :subtitle="t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.PAIN.SUBTITLE')"
      icon="i-lucide-triangle-alert"
      tone="ruby"
      :count="groupCounts.pain"
    >
      <label
        v-for="field in painFields"
        :key="field.key"
        class="flex items-center justify-between gap-3"
      >
        <span class="text-sm text-n-slate-12">{{ field.label }}</span>
        <ChoiceSelect
          v-model="draft[field.key]"
          compact
          :options="hasChoices"
          :aria-label="field.label"
        />
      </label>
    </FilterGroupCard>

    <FilterGroupCard
      :title="t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.QUALIFICATION.TITLE')"
      :subtitle="
        t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.QUALIFICATION.SUBTITLE')
      "
      icon="i-lucide-circle-check"
      tone="teal"
      :count="groupCounts.qualification"
    >
      <label class="grid gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('PROSPECTING.SEARCH.FIELDS.REVIEWS_MIN') }}
        </span>
        <input
          v-model="reviewsMin"
          type="number"
          min="0"
          max="10000"
          :placeholder="
            t('PROSPECTING.SEARCH.FILTER_DRAWER.REVIEWS_PLACEHOLDER')
          "
          class="h-9 rounded-md border border-n-weak bg-n-solid-1 px-2 text-sm text-n-slate-12"
          @keydown.enter.prevent
        />
      </label>
      <RatingOperatorField
        :key="draftVersion"
        v-model:rating-min="draft.rating_min"
        v-model:rating-max="draft.rating_max"
      />
    </FilterGroupCard>

    <FilterGroupCard
      :title="t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.VISIBILITY.TITLE')"
      :subtitle="
        t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.VISIBILITY.SUBTITLE')
      "
      icon="i-lucide-eye"
      tone="iris"
      :count="groupCounts.visibility"
    >
      <RankRangeSlider v-model:min="rankMin" v-model:max="rankMax" />
    </FilterGroupCard>

    <FilterGroupCard
      :title="t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.OPERATIONAL.TITLE')"
      :subtitle="
        t('PROSPECTING.SEARCH.FILTER_DRAWER.GROUPS.OPERATIONAL.SUBTITLE')
      "
      icon="i-lucide-phone"
      tone="amber"
      :count="groupCounts.operational"
    >
      <label class="flex items-center justify-between gap-3">
        <span class="text-sm text-n-slate-12">
          {{ t('PROSPECTING.SEARCH.FIELDS.HAS_PHONE') }}
        </span>
        <ChoiceSelect
          v-model="draft.has_phone"
          compact
          :options="hasChoices"
          :aria-label="t('PROSPECTING.SEARCH.FIELDS.HAS_PHONE')"
        />
      </label>
      <label
        v-for="field in yesOnlyFields"
        :key="field.key"
        class="flex min-h-11 cursor-pointer items-center justify-between gap-3"
      >
        <span class="text-sm text-n-slate-12">{{ field.label }}</span>
        <span class="inline-flex items-center gap-2 text-sm text-n-slate-11">
          <Checkbox
            :model-value="draft[field.key] === 'yes'"
            @update:model-value="checked => toggleYesOnly(field.key, checked)"
          />
          {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.YES') }}
        </span>
      </label>
    </FilterGroupCard>

    <div class="flex items-center justify-between gap-2">
      <button
        type="button"
        class="h-11 rounded-md px-2 text-sm font-medium text-n-ruby-11 hover:bg-n-ruby-3"
        @click="clearAll"
      >
        {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.CLEAR_ALL') }}
      </button>
      <button
        type="button"
        class="h-11 rounded-md bg-n-brand px-4 text-sm font-medium text-white"
        @click="apply"
      >
        {{ t('PROSPECTING.SEARCH.FILTER_DRAWER.APPLY') }}
      </button>
    </div>
  </div>
</template>
