<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useProspectingSearchContext } from '../../composables/useProspectingSearch';
import { decisionMakerChoices } from '../../utils/decisionMakerTypes';

const { t } = useI18n();
const { form } = useProspectingSearchContext();

// Tipo de decisor: frente de local (#677, E1 frente C).
const decisionMakerOptions = computed(() => decisionMakerChoices(t));
</script>

<template>
  <div class="grid gap-4 md:grid-cols-2">
    <label class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.RADIUS_KM') }}
      </span>
      <input
        v-model="form.radius_km"
        type="number"
        min="0.1"
        step="any"
        class="h-10 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
      />
    </label>
    <label class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.SEARCH.FIELDS.LIMIT') }}
      </span>
      <input
        v-model="form.requested_limit"
        type="number"
        min="1"
        max="60"
        class="h-10 rounded-md border border-n-weak bg-n-solid-2 px-3 text-sm text-n-slate-12"
      />
    </label>
    <label class="grid gap-1">
      <span class="text-xs font-medium text-n-slate-11">
        {{ t('PROSPECTING.DECISION_MAKER.LABEL') }}
      </span>
      <ChoiceSelect
        v-model="form.decision_maker_type"
        :options="decisionMakerOptions"
        :aria-label="t('PROSPECTING.DECISION_MAKER.LABEL')"
      />
    </label>
  </div>
  <label
    class="flex items-start gap-2 rounded-md border border-n-weak bg-n-solid-2 px-3 py-2"
  >
    <input
      v-model="form.auto_expand_radius"
      type="checkbox"
      class="mt-1 size-4"
      :disabled="form.area_type !== 'radius'"
    />
    <span class="grid gap-0.5">
      <span class="text-xs font-medium text-n-slate-12">
        {{ t('PROSPECTING.SEARCH.FIELDS.AUTO_EXPAND_RADIUS') }}
      </span>
      <span class="text-xs text-n-slate-10">
        {{ t('PROSPECTING.SEARCH.AUTO_EXPAND_RADIUS_HINT') }}
      </span>
    </span>
  </label>
</template>
