<script setup>
import { computed } from 'vue';
import { I18nT } from 'vue-i18n';

// "Quanto confiar" (#1073, F2b; usado também no painel da F3a, #1088): conversas que vieram de anúncio nos
// últimos 30 dias, pelo melhor que sabemos de cada uma, do mais forte ao mais fraco. `fix` leva ao passo 3,
// onde está o texto que faz o anúncio de site ser identificado.
//
// No painel (#1110, F5, §5.2) segue o período da tela e ganha o número da Meta ao lado do nosso, por destino e
// até ontem (D5.8), com a explicação decidida no servidor. Os números vão em slots do <I18nT>, nunca em
// v-html. A aba Conexão não passa `comparison` e fica como era.
const props = defineProps({
  confidence: { type: Object, required: true },
  // panel.meta_comparison: { days, until, rows: [{ destination, meta, meta_visits, ours, explanation }],
  // explanation }. undefined fora do painel; null no painel quando não há linha.
  comparison: { type: Object, default: undefined },
});

const emit = defineEmits(['fix']);

const META = 'CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.META';
const inPanel = computed(() => props.comparison !== undefined);
const metaRows = computed(() => props.comparison?.rows || []);
const noMetaData = computed(
  () => props.comparison?.explanation === 'no_meta_data'
);

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
    class="flex flex-col gap-4 p-5 border border-solid rounded-xl border-n-weak bg-n-solid-1 sm:p-6"
  >
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <h4
        class="m-0 text-xs font-520 uppercase tracking-[0.08em] text-n-slate-11"
      >
        {{
          inPanel
            ? $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TITLE_PERIOD', {
                days: confidence.window_days,
              })
            : $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.TITLE')
        }}
      </h4>
      <span
        v-if="confidentShare !== null"
        data-summary-confidence-share
        class="font-interDisplay text-[32px] font-520 leading-none tracking-[-0.02em] tabular-nums text-n-slate-12"
      >
        {{
          $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.SHARE', {
            share: confidentShare,
          })
        }}
      </span>
    </div>
    <p class="m-0 text-sm font-420 leading-relaxed text-n-slate-11">
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
      class="grid p-0 m-0 list-none gap-y-2.5 gap-x-8 sm:grid-cols-2"
    >
      <li
        v-for="level in CONFIDENCE_LEVELS"
        :key="level.key"
        :data-confidence-level="level.key"
        class="flex items-center gap-2 text-sm font-440 text-n-slate-12"
      >
        <span
          class="flex-none rounded-full size-2.5"
          :class="level.dot"
          aria-hidden="true"
        />
        <span class="flex-1 min-w-0">
          {{ $t(`CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.${level.label}`) }}
        </span>
        <span class="font-520 tabular-nums">
          {{ confidence[level.key] }}
        </span>
      </li>
    </ul>
    <div
      v-if="metaRows.length || noMetaData"
      data-confidence-meta
      class="flex flex-col gap-3 pt-4 border-0 border-t border-solid border-n-weak"
    >
      <div
        v-for="row in metaRows"
        :key="row.destination"
        :data-confidence-meta-row="row.destination"
        :data-confidence-meta-explanation="row.explanation"
        class="flex flex-col gap-1"
      >
        <I18nT
          :keypath="`${META}.${row.destination.toUpperCase()}.LINE`"
          :plural="row.meta"
          tag="p"
          scope="global"
          class="m-0 text-sm leading-relaxed font-420 text-n-slate-12 tabular-nums"
        >
          <template #meta>
            <strong class="font-520">{{ row.meta }}</strong>
          </template>
          <template #ours>
            <strong class="font-520">{{ row.ours }}</strong>
          </template>
          <template #visits>
            <span>{{ row.meta_visits ?? 0 }}</span>
          </template>
        </I18nT>
        <p
          v-if="row.explanation"
          class="m-0 text-[13px] font-420 leading-relaxed text-n-slate-11"
        >
          {{
            $t(
              `${META}.${row.destination.toUpperCase()}.${row.explanation.toUpperCase()}`
            )
          }}
        </p>
      </div>
      <p
        v-if="noMetaData"
        data-confidence-meta-empty
        class="m-0 text-[13px] font-420 leading-relaxed text-n-slate-11"
      >
        {{ $t(`${META}.NO_META_DATA`) }}
      </p>
    </div>
    <button
      v-if="confidenceGap"
      type="button"
      data-summary-confidence-fix
      class="self-start p-0 text-[13px] font-460 text-left bg-transparent border-0 min-h-11 text-n-blue-11 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
      @click="emit('fix')"
    >
      {{ $t('CRM_KANBAN.META_ADS_HUB.SUMMARY.CONFIDENCE.FIX') }}
    </button>
  </div>
</template>
