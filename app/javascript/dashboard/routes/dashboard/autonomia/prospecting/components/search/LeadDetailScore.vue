<script setup>
import { useI18n } from 'vue-i18n';
import * as detail from '../../utils/leadDetail';

defineProps({
  lead: { type: Object, required: true },
});

const { t } = useI18n();
const { negativeFactors, scoreNumber, scoreWeight } = detail;
const scoreBreakdownEntries = lead => detail.scoreBreakdownEntries(lead, t);
const negativeFactorLabel = factor => detail.negativeFactorLabel(factor, t);
</script>

<template>
  <div class="rounded-md border border-n-weak bg-n-solid-2 p-4">
    <div class="flex items-start justify-between gap-3">
      <div>
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ t('PROSPECTING.SEARCH.SCORE_EVALUATION_TITLE') }}
        </h3>
        <p class="mt-1 text-xs text-n-slate-10">
          {{ t('PROSPECTING.SEARCH.SCORE_EVALUATION_HINT') }}
        </p>
      </div>
      <span
        class="shrink-0 rounded-full bg-n-solid-1 px-2.5 py-1 text-xs font-semibold text-n-slate-12"
      >
        {{
          t('PROSPECTING.SEARCH.SCORE_VALUE', {
            score: lead.priority_score || lead.score || '-',
          })
        }}
      </span>
    </div>

    <div v-if="scoreBreakdownEntries(lead).length" class="mt-4 grid gap-2">
      <div
        v-for="entry in scoreBreakdownEntries(lead)"
        :key="entry.key"
        class="grid gap-2 rounded-md border border-n-weak bg-n-solid-1 p-3 sm:grid-cols-[minmax(0,1fr)_auto_auto]"
      >
        <div class="min-w-0">
          <div class="truncate text-sm font-medium text-n-slate-12">
            {{ entry.label }}
          </div>
          <div class="mt-1 text-xs text-n-slate-10">
            {{
              t('PROSPECTING.SEARCH.SCORE_SIGNAL', {
                value: scoreNumber(entry.signal),
              })
            }}
          </div>
        </div>
        <div class="text-xs text-n-slate-10 sm:text-right">
          <div>{{ t('PROSPECTING.SEARCH.SCORE_WEIGHT') }}</div>
          <div class="mt-1 font-medium text-n-slate-12">
            {{ scoreWeight(entry.weight) }}
          </div>
        </div>
        <div class="text-xs text-n-slate-10 sm:text-right">
          <div>{{ t('PROSPECTING.SEARCH.SCORE_CONTRIBUTION') }}</div>
          <div class="mt-1 font-medium text-n-slate-12">
            {{ scoreNumber(entry.weightedScore) }}
          </div>
        </div>
      </div>
    </div>

    <div
      v-if="negativeFactors(lead).length"
      class="mt-4 rounded-md border border-amber-100 bg-amber-50 p-3"
    >
      <div class="text-xs font-semibold text-amber-900">
        {{ t('PROSPECTING.SEARCH.NEGATIVE_FACTORS_TITLE') }}
      </div>
      <ul class="mt-2 grid gap-1 text-sm text-amber-950">
        <li
          v-for="factor in negativeFactors(lead)"
          :key="
            typeof factor === 'string' ? factor : factor.key || factor.reason
          "
          class="flex items-start gap-2"
        >
          <span
            class="i-lucide-triangle-alert mt-0.5 size-3.5 shrink-0 text-amber-700"
          />
          <span class="break-words">
            {{ negativeFactorLabel(factor) }}
          </span>
          <span
            v-if="factor?.points"
            class="ml-auto shrink-0 font-mono text-xs text-red-600"
          >
            {{ `-${factor.points}` }}
          </span>
        </li>
      </ul>
    </div>
  </div>
</template>
