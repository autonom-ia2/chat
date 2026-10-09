<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// One uploaded material with its Revisor verdict. Drives four visual states from
// the backend `review` payload:
//   - ingesting / awaiting review -> Spinner + "Enviando/Analisando"
//   - accepted                    -> nota + rótulo + resumo (teal)
//   - needs_resend                -> "revisar" (amber, qualidade) + Reenviar
//   - failed                      -> "falha ao ler" (amber, técnico) + Reenviar
//   - needs_review                -> "confiança baixa" (neutral, non-blocking)
// All tokens adapt to light/dark; nothing here renders raw white/black.
const props = defineProps({
  source: {
    type: Object,
    required: true,
  },
  resyncing: {
    type: Boolean,
    default: false,
  },
  removing: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['resync', 'remove']);

const { t } = useI18n();

const review = computed(() => props.source.review || {});
const reviewStatus = computed(() => review.value.status || null);

// Still working while ingesting OR ready-but-unreviewed.
const isIngesting = computed(() => {
  const status = props.source.status;
  return (
    status === 'pending' ||
    status === 'processing' ||
    (status === 'ready' && reviewStatus.value == null)
  );
});

const isAnalyzing = computed(
  () => props.source.status === 'ready' && reviewStatus.value == null
);

const isFailed = computed(() => props.source.status === 'failed');
const isAccepted = computed(() => reviewStatus.value === 'accepted');
const isNeedsResend = computed(() => reviewStatus.value === 'needs_resend');
const isNeedsReview = computed(() => reviewStatus.value === 'needs_review');

const fileIcon = computed(() =>
  props.source.source_type === 'link' ? 'i-lucide-link' : 'i-lucide-file-text'
);

const title = computed(
  () =>
    props.source.title ||
    props.source.reference ||
    t('AGENTS.MATERIALS.STATUS.SENDING')
);

// Map the Revisor label (ótima|boa|fraca) to a translated chip.
const labelText = computed(() => {
  const key = (review.value.label || '').toUpperCase();
  const map = {
    OTIMA: t('AGENTS.MATERIALS.LABEL.OTIMA'),
    BOA: t('AGENTS.MATERIALS.LABEL.BOA'),
    FRACA: t('AGENTS.MATERIALS.LABEL.FRACA'),
  };
  return map[key] || '';
});

const confidenceText = computed(() => {
  const key = (review.value.confidence || '').toUpperCase();
  const map = {
    ALTA: t('AGENTS.MATERIALS.CONFIDENCE.ALTA'),
    MEDIA: t('AGENTS.MATERIALS.CONFIDENCE.MEDIA'),
    MÉDIA: t('AGENTS.MATERIALS.CONFIDENCE.MEDIA'),
    BAIXA: t('AGENTS.MATERIALS.CONFIDENCE.BAIXA'),
  };
  return map[key] || '';
});

const statusText = computed(() => {
  // `failed` = technical ingestion failure (we couldn't read the file);
  // `needs_resend` = the content was read but its quality needs another pass.
  // Same amber accent, distinct copy/icon so the user knows which one it is.
  if (isFailed.value) return t('AGENTS.MATERIALS.STATUS.FAILED');
  if (isAnalyzing.value) return t('AGENTS.MATERIALS.STATUS.ANALYZING');
  if (isIngesting.value) return t('AGENTS.MATERIALS.STATUS.SENDING');
  if (isNeedsResend.value) return t('AGENTS.MATERIALS.STATUS.REVIEW');
  return t('AGENTS.MATERIALS.STATUS.READY');
});

// Border/accent tint per verdict, all token-based so they read in dark mode.
const accentClass = computed(() => {
  if (isAccepted.value) return 'border-n-teal-8';
  if (isNeedsResend.value || isFailed.value) return 'border-n-amber-8';
  return 'border-n-weak';
});

const statusIcon = computed(() => {
  if (isAccepted.value) return 'i-lucide-check-circle-2';
  // Technical failure reads as a broken file; quality resend as a caution.
  if (isFailed.value) return 'i-lucide-file-x';
  if (isNeedsResend.value) return 'i-lucide-alert-triangle';
  if (isNeedsReview.value) return 'i-lucide-info';
  return 'i-lucide-loader';
});

const statusIconClass = computed(() => {
  if (isAccepted.value) return 'text-n-teal-11';
  if (isNeedsResend.value || isFailed.value) return 'text-n-amber-11';
  return 'text-n-slate-11';
});

const reason = computed(() => review.value.reason || '');
const summary = computed(() => review.value.summary || '');
const score = computed(() =>
  Number.isFinite(review.value.quality_score)
    ? review.value.quality_score
    : null
);
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 transition-colors border rounded-xl bg-n-solid-1"
    :class="accentClass"
  >
    <div class="flex items-start gap-3">
      <span
        class="flex items-center justify-center rounded-lg size-9 shrink-0 bg-n-alpha-2 text-n-slate-11"
      >
        <i :class="fileIcon" class="size-4" />
      </span>

      <div class="flex flex-col min-w-0 flex-1 gap-0.5">
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ title }}
        </span>
        <span
          v-if="source.reference && source.reference !== title"
          class="text-xs truncate text-n-slate-11"
        >
          {{ source.reference }}
        </span>
      </div>

      <div class="flex items-center gap-1.5 shrink-0">
        <Spinner v-if="isIngesting" :size="16" class="text-n-slate-11" />
        <i v-else :class="[statusIcon, statusIconClass]" class="size-4" />
        <span class="text-xs font-medium" :class="statusIconClass">
          {{ statusText }}
        </span>
      </div>

      <NextButton
        ghost
        slate
        xs
        class="min-h-11 min-w-11"
        icon="i-lucide-trash-2"
        :aria-label="t('AGENTS.MATERIALS.REMOVE')"
        :is-loading="removing"
        @click="emit('remove', source.id)"
      />
    </div>

    <!-- Accepted: nota + rótulo + resumo -->
    <div v-if="isAccepted" class="flex flex-col gap-2">
      <div class="flex flex-wrap items-center gap-2">
        <span
          v-if="score !== null"
          class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium rounded-md bg-n-teal-3 text-n-teal-12"
        >
          <i class="i-lucide-gauge size-3" />
          {{ t('AGENTS.MATERIALS.SCORE', { score }) }}
        </span>
        <span
          v-if="labelText"
          class="px-2 py-0.5 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-12"
        >
          {{ labelText }}
        </span>
        <span v-if="confidenceText" class="text-xs text-n-slate-11">
          {{ confidenceText }}
        </span>
      </div>
      <p v-if="summary" class="text-xs leading-relaxed text-n-slate-11">
        {{ summary }}
      </p>
    </div>

    <!-- Needs review (low confidence, non-blocking) -->
    <div
      v-else-if="isNeedsReview"
      class="flex items-start gap-2 px-3 py-2 text-xs rounded-lg bg-n-alpha-2 text-n-slate-11"
    >
      <i class="i-lucide-info size-3.5 mt-0.5 shrink-0" />
      <span class="flex-1">
        {{ summary || t('AGENTS.MATERIALS.REVIEWING') }}
      </span>
    </div>

    <!-- Needs resend (quality) / failed (technical): motivo + Reenviar.
         Same amber surface, but distinct icon + fallback copy per cause. -->
    <div
      v-else-if="isNeedsResend || isFailed"
      class="flex flex-col gap-2 px-3 py-2 rounded-lg bg-n-amber-9/10"
    >
      <p class="flex items-start gap-2 text-xs text-n-amber-11">
        <i
          :class="isFailed ? 'i-lucide-file-x' : 'i-lucide-alert-triangle'"
          class="size-3.5 mt-0.5 shrink-0"
        />
        <span class="flex-1">
          {{
            isFailed
              ? reason || t('AGENTS.MATERIALS.FAILED_REASON')
              : reason || t('AGENTS.MATERIALS.STATUS.REVIEW')
          }}
        </span>
      </p>
      <div class="flex">
        <NextButton
          outline
          amber
          xs
          class="min-h-11"
          icon="i-lucide-refresh-cw"
          :label="t('AGENTS.MATERIALS.RESEND')"
          :is-loading="resyncing"
          @click="emit('resync', source.id)"
        />
      </div>
    </div>
  </div>
</template>
