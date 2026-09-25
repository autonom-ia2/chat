<script setup>
// Progresso da pesquisa de empresa e decisor da busca aberta (#679), acima da
// lista (ResearchBatchProgress do Orth, sem o texto de cobrança). Falha conta
// como concluída e aparece à parte. Sem pesquisa, não aparece.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  progress: { type: Object, default: null },
});

const PERCENT = 100;

const { t } = useI18n();

const total = computed(() => Number(props.progress?.total || 0));
const failed = computed(() => Number(props.progress?.failed || 0));
const concluded = computed(
  () => Number(props.progress?.done || 0) + failed.value
);
const isFinished = computed(() => concluded.value >= total.value);
const countLabel = computed(() =>
  t('PROSPECTING.RESEARCH.PROGRESS.LABEL', {
    done: concluded.value,
    total: total.value,
  })
);
const statusLabel = computed(() =>
  isFinished.value
    ? t('PROSPECTING.RESEARCH.PROGRESS.FINISHED')
    : t('PROSPECTING.RESEARCH.PROGRESS.RUNNING')
);
// Largura calculada: o Tailwind não gera classe para um valor que só existe em
// tempo de execução (mesmo caso de FirstSteps.vue).
const barStyle = computed(() => {
  const percent = Math.min(
    PERCENT,
    Math.round((concluded.value / total.value) * PERCENT)
  );
  return { width: `${percent}%` };
});
</script>

<template>
  <section
    v-if="total > 0"
    data-test="research-progress"
    class="rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p data-test="research-progress-text" class="font-medium text-n-slate-12">
        {{ `${countLabel} · ${statusLabel}` }}
      </p>
      <span v-if="failed" class="text-xs text-n-ruby-11">
        {{ t('PROSPECTING.RESEARCH.PROGRESS.FAILED_COUNT', { count: failed }) }}
      </span>
    </div>
    <div
      class="mt-2 h-2 overflow-hidden rounded-full bg-n-slate-4"
      role="progressbar"
      aria-valuemin="0"
      :aria-valuemax="total"
      :aria-valuenow="Math.min(concluded, total)"
      :aria-label="countLabel"
    >
      <div
        class="h-full rounded-full bg-n-brand transition-[width] motion-reduce:transition-none"
        :style="barStyle"
      />
    </div>
  </section>
</template>
