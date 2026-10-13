<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// "Sugerir horários com IA" no formulário do Google/Microsoft: o botão, os
// horários sugeridos (com o motivo na dica) e o aviso quando não há nenhum. A
// lógica é de useMeetingAi; escolher um horário fica com quem usa.
defineProps({
  suggestions: { type: Array, default: () => [] },
  suggesting: { type: Boolean, default: false },
  loaded: { type: Boolean, default: false },
  timeLabel: { type: Function, required: true },
  reason: { type: Function, required: true },
});
defineEmits(['suggest', 'pick']);

const { t } = useI18n();
const S = 'CRM_KANBAN.CALENDAR.MEETING_SCHEDULER';
</script>

<template>
  <div class="mt-1 flex flex-col gap-1.5">
    <div class="flex flex-wrap items-center gap-2">
      <Button
        type="button"
        variant="ghost"
        color="slate"
        size="xs"
        icon="i-lucide-sparkles"
        :label="t(`${S}.AI_SUGGEST_BUTTON`)"
        :is-loading="suggesting"
        :disabled="suggesting"
        @click="$emit('suggest')"
      />
      <span v-if="suggesting" class="text-xs text-n-slate-10">
        {{ t(`${S}.AI_SUGGEST_LOADING`) }}
      </span>
    </div>

    <div v-if="suggestions.length" class="flex flex-wrap items-center gap-2">
      <span
        class="i-lucide-sparkles size-3.5 text-n-iris-11"
        aria-hidden="true"
      />
      <button
        v-for="suggestion in suggestions"
        :key="suggestion.starts_at"
        type="button"
        :title="reason(suggestion.reason)"
        class="inline-flex items-center gap-1 rounded-lg bg-n-iris-3 px-2.5 py-1 text-xs font-medium tabular-nums text-n-iris-11 outline outline-1 outline-n-iris-5 transition-colors hover:bg-n-iris-4"
        @click="$emit('pick', suggestion)"
      >
        {{ timeLabel(suggestion.starts_at) }}
      </button>
    </div>

    <p v-else-if="loaded && !suggesting" class="mb-0 text-xs text-n-slate-10">
      {{ t(`${S}.AI_SUGGEST_EMPTY`) }}
    </p>
  </div>
</template>
