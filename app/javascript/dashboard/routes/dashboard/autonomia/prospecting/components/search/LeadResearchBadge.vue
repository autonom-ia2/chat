<script setup>
// Selo de uma capacidade da pesquisa (#679): "Empresa: <estado>" ou
// "Decisor: <estado>", com ícone e tom do estado (ResearchStatusBadge do Orth).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { researchStatePresentation } from '../../utils/leadResearch';

const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['company', 'decision'].includes(value),
  },
  status: { type: String, default: 'not_researched' },
});

const TONE_CLASS = {
  neutral: 'border-n-weak bg-n-solid-2 text-n-slate-11',
  info: 'border-n-blue-5 bg-n-blue-2 text-n-blue-11',
  success: 'border-n-teal-5 bg-n-teal-2 text-n-teal-11',
  warning: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
  danger: 'border-n-ruby-5 bg-n-ruby-2 text-n-ruby-11',
};

const LABEL_KEY = {
  company: 'PROSPECTING.RESEARCH.BADGE.COMPANY',
  decision: 'PROSPECTING.RESEARCH.BADGE.DECISION',
};

const { t } = useI18n();
const presentation = computed(() => researchStatePresentation(props.status));
</script>

<template>
  <span
    :data-research-badge="kind"
    :data-state="status"
    class="inline-flex min-h-6 items-center gap-1 rounded-full border px-2 text-[11px] font-medium"
    :class="TONE_CLASS[presentation.tone]"
  >
    <span
      class="size-3.5 shrink-0"
      :class="[
        presentation.icon,
        { 'animate-spin motion-reduce:animate-none': status === 'researching' },
      ]"
      aria-hidden="true"
    />
    {{ t(LABEL_KEY[kind], { state: t(presentation.labelKey) }) }}
  </span>
</template>
