<script setup>
// Pesquisa de empresa e decisor no card do lead (#679): selos, linha do
// decisor por estado, confiança, data de verificação e "resultado
// reutilizado" (ResultsTable.tsx do Orth). Tudo muda pelo evento ao vivo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadResearchBadge from './LeadResearchBadge.vue';
import {
  confidencePercent,
  decisionLineKey,
  formatResearchDate,
  qualificationLabelKey,
  researchPhase,
} from '../../utils/leadResearch';

const props = defineProps({
  research: { type: Object, required: true },
  researchEnabled: { type: Boolean, default: true },
});

const META_SEPARATOR = ' · ';

const { t } = useI18n();

const decision = computed(() => props.research.decision || null);
const lineKey = computed(() =>
  decisionLineKey(props.research, { researchEnabled: props.researchEnabled })
);
const decisionText = computed(() => {
  if (lineKey.value || !decision.value) return t(lineKey.value);
  const roleKey = qualificationLabelKey(decision.value.role);
  const role = roleKey ? t(roleKey) : decision.value.role;
  return role ? `${decision.value.name} · ${role}` : decision.value.name;
});

// Confiança e data só com o resultado na mão: durante uma nova pesquisa os
// números antigos saem da linha.
const meta = computed(() => {
  if (lineKey.value || researchPhase(props.research) !== 'done') return '';
  const percent = confidencePercent(decision.value?.confidence);
  const date = formatResearchDate(
    decision.value?.verified_at || props.research.verified_at
  );
  return [
    percent === null ? null : t('PROSPECTING.RESEARCH.CONFIDENCE', { percent }),
    date ? t('PROSPECTING.RESEARCH.VERIFIED_ON', { date }) : null,
    props.research.reused ? t('PROSPECTING.RESEARCH.REUSED') : null,
  ]
    .filter(Boolean)
    .join(META_SEPARATOR);
});
</script>

<template>
  <div
    data-test="lead-research"
    class="grid gap-1.5 px-4 pb-2"
    aria-live="polite"
    aria-atomic="true"
  >
    <div class="flex flex-wrap gap-1.5">
      <LeadResearchBadge kind="company" :status="research.company_status" />
      <LeadResearchBadge kind="decision" :status="research.decision_status" />
    </div>
    <p
      data-test="lead-research-decision"
      class="truncate text-xs text-n-slate-11"
    >
      <span class="text-n-slate-10">
        {{ t('PROSPECTING.RESEARCH.DECISION_LABEL') }}
      </span>
      {{ decisionText }}
    </p>
    <p
      v-if="meta"
      data-test="lead-research-meta"
      class="text-[11px] text-n-slate-10"
    >
      {{ meta }}
    </p>
  </div>
</template>
