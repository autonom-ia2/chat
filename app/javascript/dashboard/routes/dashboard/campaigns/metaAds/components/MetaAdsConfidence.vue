<script setup>
import { computed } from 'vue';

// "Quanto confiar" (#1073, F2b; usado também no painel da F3a, #1088): conversas que vieram de anúncio nos
// últimos 30 dias, pelo melhor que sabemos de cada uma, do mais forte ao mais fraco. `fix` leva ao passo 3,
// onde está o texto que faz o anúncio de site ser identificado.
const props = defineProps({
  confidence: { type: Object, required: true },
});

const emit = defineEmits(['fix']);

const CONFIDENCE_LEVELS = [
  { key: 'ad', label: 'AD', dot: 'bg-n-teal-9' },
  { key: 'ad_name', label: 'AD_NAME', dot: 'bg-n-teal-7' },
  { key: 'campaign', label: 'CAMPAIGN', dot: 'bg-n-amber-9' },
  { key: 'unknown', label: 'UNKNOWN', dot: 'bg-n-slate-8' },
];
const confidentShare = computed(() => {
  const data = props.confidence;
  if (!data.conversations) return null;
  return Math.round(((data.ad + data.ad_name) / data.conversations) * 100);
});
const confidenceGap = computed(
  () => (props.confidence.campaign || 0) + (props.confidence.unknown || 0)
);
</script>

<template>
  <div
    data-summary-confidence
    class="flex flex-col gap-3 p-4 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 sm:p-5"
  >
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <h4 class="m-0 text-base font-semibold text-n-slate-12">
        {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TITLE') }}
      </h4>
      <span
        v-if="confidentShare !== null"
        data-summary-confidence-share
        class="text-2xl font-semibold text-n-slate-12"
      >
        {{
          $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.SHARE', {
            share: confidentShare,
          })
        }}
      </span>
    </div>
    <p class="m-0 text-sm text-n-slate-11">
      {{
        confidence.conversations
          ? $t(
              'CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TOTAL',
              {
                days: confidence.window_days,
                count: confidence.conversations,
              },
              confidence.conversations
            )
          : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.EMPTY')
      }}
    </p>
    <ul
      v-if="confidence.conversations"
      class="grid gap-2 p-0 m-0 list-none sm:grid-cols-2"
    >
      <li
        v-for="level in CONFIDENCE_LEVELS"
        :key="level.key"
        :data-confidence-level="level.key"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <span
          class="flex-none rounded-full size-2.5"
          :class="level.dot"
          aria-hidden="true"
        />
        <span class="flex-1 min-w-0">
          {{ $t(`CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.${level.label}`) }}
        </span>
        <span class="font-semibold tabular-nums">
          {{ confidence[level.key] }}
        </span>
      </li>
    </ul>
    <button
      v-if="confidenceGap"
      type="button"
      data-summary-confidence-fix
      class="self-start p-0 text-sm font-medium text-left bg-transparent border-0 min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('fix')"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.FIX') }}
    </button>
  </div>
</template>
