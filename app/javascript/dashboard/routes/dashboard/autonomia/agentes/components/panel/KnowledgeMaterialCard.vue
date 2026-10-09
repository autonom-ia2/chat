<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { toLocaleTag } from 'dashboard/helper/localeTag';

const props = defineProps({
  source: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  resyncing: { type: Boolean, default: false },
  removing: { type: Boolean, default: false },
});

const emit = defineEmits(['resync', 'remove']);
const { t, locale } = useI18n();

const STATE_KEYS = {
  uploading: 'UPLOADING',
  reading: 'READING',
  unreadable: 'UNREADABLE',
  needs_another_file: 'NEEDS_ANOTHER_FILE',
  not_reviewed: 'NOT_REVIEWED',
  out_of_business_not_used: 'OUT_OF_BUSINESS_NOT_USED',
  out_of_business_used: 'OUT_OF_BUSINESS_USED',
  ready: 'READY',
};

const screenState = computed(() => props.source.screen_state || 'unreadable');
const usesValue = computed(() => {
  if (props.source.uses === true) return 'true';
  if (props.source.uses === false) return 'false';
  return 'unknown';
});
const review = computed(() => props.source.review || {});
const title = computed(
  () =>
    props.source.reference ||
    props.source.title ||
    t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL')
);
const stateKey = computed(() => STATE_KEYS[screenState.value] || 'UNREADABLE');
const statusText = computed(() => {
  switch (stateKey.value) {
    case 'UPLOADING':
      return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.UPLOADING');
    case 'READING':
      return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.READING');
    case 'UNREADABLE':
      return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.UNREADABLE');
    case 'NEEDS_ANOTHER_FILE':
      return t(
        'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.NEEDS_ANOTHER_FILE'
      );
    case 'NOT_REVIEWED':
      return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.NOT_REVIEWED');
    case 'OUT_OF_BUSINESS_NOT_USED':
      return t(
        'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.OUT_OF_BUSINESS_NOT_USED'
      );
    case 'OUT_OF_BUSINESS_USED':
      return t(
        'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.OUT_OF_BUSINESS_USED'
      );
    default:
      return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.READY');
  }
});
const statusDescription = computed(() => {
  const descriptions = {
    unreadable:
      props.source.error || props.source.uses_reason || review.value.reason,
    needs_another_file:
      props.source.error || props.source.uses_reason || review.value.reason,
    not_reviewed: t(
      'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.NOT_REVIEWED_DESC'
    ),
    out_of_business_not_used: t(
      'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.OUT_OF_BUSINESS_NOT_USED_DESC'
    ),
    out_of_business_used: t(
      'AGENTS.PANEL.REDESIGN_KNOWLEDGE.MATERIAL_STATES.OUT_OF_BUSINESS_USED_DESC'
    ),
  };
  return descriptions[screenState.value] || '';
});

const icon = computed(() => {
  if (screenState.value === 'ready') return 'i-lucide-check-circle-2';
  if (['unreadable', 'needs_another_file'].includes(screenState.value)) {
    return 'i-lucide-file-x';
  }
  if (screenState.value === 'not_reviewed') return 'i-lucide-info';
  return 'i-lucide-loader';
});

const statusClass = computed(() => {
  if (screenState.value === 'ready') return 'text-n-teal-11';
  if (['unreadable', 'needs_another_file'].includes(screenState.value)) {
    return 'text-n-amber-11';
  }
  return 'text-n-slate-11';
});

const borderClass = computed(() => {
  if (screenState.value === 'ready') return 'border-n-teal-8';
  if (['unreadable', 'needs_another_file'].includes(screenState.value)) {
    return 'border-n-amber-8';
  }
  return 'border-n-weak';
});

const isWorking = computed(() =>
  ['uploading', 'reading'].includes(screenState.value)
);
const canResync = computed(() =>
  ['unreadable', 'needs_another_file', 'not_reviewed'].includes(
    screenState.value
  )
);
const qualityLabel = computed(() => {
  const labels = {
    otima: 'OTIMA',
    ótima: 'OTIMA',
    boa: 'BOA',
    fraca: 'FRACA',
  };
  const key = labels[String(review.value.label || '').toLowerCase()];
  if (key === 'OTIMA') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_LABELS.OTIMA');
  }
  if (key === 'BOA') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_LABELS.BOA');
  }
  if (key === 'FRACA') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_LABELS.FRACA');
  }
  return '';
});
const confidenceLabel = computed(() => {
  const labels = {
    alta: 'HIGH',
    media: 'MEDIUM',
    média: 'MEDIUM',
    baixa: 'LOW',
  };
  const key = labels[String(review.value.confidence || '').toLowerCase()];
  if (key === 'HIGH') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_CONFIDENCE.HIGH');
  }
  if (key === 'MEDIUM') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_CONFIDENCE.MEDIUM');
  }
  if (key === 'LOW') {
    return t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_CONFIDENCE.LOW');
  }
  return '';
});
const score = computed(() => {
  if (
    review.value.quality_score === null ||
    review.value.quality_score === undefined
  )
    return null;
  return new Intl.NumberFormat(toLocaleTag(locale.value), {
    maximumFractionDigits: 1,
  }).format(review.value.quality_score / 10);
});
</script>

<template>
  <article
    class="flex flex-col min-w-0 gap-3 p-4 border rounded-xl bg-n-solid-1"
    :class="borderClass"
    :data-state="screenState"
    :data-uses="usesValue"
    data-testid="knowledge-material"
  >
    <div class="flex flex-wrap items-start min-w-0 gap-3">
      <span
        class="flex items-center justify-center shrink-0 rounded-lg size-9 bg-n-alpha-2 text-n-slate-11"
        aria-hidden="true"
      >
        <i
          :class="
            source.source_type === 'link'
              ? 'i-lucide-link'
              : 'i-lucide-file-text'
          "
          class="size-4"
        />
      </span>

      <div class="flex flex-col min-w-0 gap-0.5 grow">
        <span class="text-sm font-medium break-words text-n-slate-12">{{
          title
        }}</span>
        <span
          v-if="source.external_link && source.external_link !== title"
          class="text-xs break-words text-n-slate-11"
        >
          {{ source.external_link }}
        </span>
      </div>

      <div
        class="flex min-w-0 max-w-full items-start gap-1.5"
        :class="statusClass"
      >
        <Spinner v-if="isWorking" :size="16" />
        <i v-else :class="icon" class="size-4" aria-hidden="true" />
        <span class="text-xs font-medium break-words">{{ statusText }}</span>
      </div>

      <Button
        v-if="canManage"
        ghost
        slate
        size="md"
        icon="i-lucide-trash-2"
        class="min-h-11 min-w-11"
        :aria-label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.REMOVE')"
        :is-loading="removing"
        data-action="remove"
        @click="emit('remove', source.id)"
      />
    </div>

    <div
      v-if="screenState === 'ready'"
      class="flex flex-col gap-2"
      data-testid="material-quality"
    >
      <div class="flex flex-wrap items-center gap-2">
        <span
          v-if="score !== null"
          class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-md bg-n-teal-3 text-n-teal-12"
        >
          <i class="i-lucide-gauge size-3" aria-hidden="true" />
          {{ t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.QUALITY_SCORE', { score }) }}
        </span>
        <span
          v-if="qualityLabel"
          class="px-2 py-1 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-12"
        >
          {{ qualityLabel }}
        </span>
        <span v-if="confidenceLabel" class="text-xs text-n-slate-11">
          {{ confidenceLabel }}
        </span>
      </div>
      <p
        v-if="review.summary"
        class="m-0 text-xs leading-relaxed text-n-slate-11"
      >
        {{ review.summary }}
      </p>
    </div>

    <div
      v-else-if="statusDescription"
      class="flex items-start gap-2 px-3 py-2 text-xs leading-5 rounded-lg bg-n-alpha-2 text-n-slate-11"
      :class="statusClass"
    >
      <i class="i-lucide-info size-3.5 mt-0.5 shrink-0" aria-hidden="true" />
      <span class="min-w-0">{{ statusDescription }}</span>
    </div>

    <div v-if="canManage && canResync" class="flex">
      <Button
        outline
        slate
        size="sm"
        icon="i-lucide-refresh-cw"
        class="min-h-11"
        :label="t('AGENTS.PANEL.REDESIGN_KNOWLEDGE.RESEND')"
        :is-loading="resyncing"
        data-action="resync"
        @click="emit('resync', source.id)"
      />
    </div>
  </article>
</template>
