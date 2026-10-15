<script setup>
// Filtro "Funil" da lista de conversas (multifunil #1150, aprovado pelo Rodrigo em 15/10).
// Até 4 funis: botões lado a lado, um toque troca. Mais de 4: campo de escolha (ChoiceSelect, sem <select> nativo).
// Os funis vêm de GET /crm/pipelines, que já mostra só os funis da pessoa (Crm::Access::VisiblePipelines).
// "Sem assunto" é a triagem: conversa sem card.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  FUNNEL_ALL,
  FUNNEL_NONE,
  MAX_FUNNEL_BUTTONS,
  visibleFunnelChoice,
} from 'dashboard/composables/useFunnelFilterChoice';

const modelValue = defineModel({ type: String, default: FUNNEL_ALL });

const { t } = useI18n();
const pipelines = ref([]);

onMounted(async () => {
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    pipelines.value = data?.payload || [];
  } catch {
    // Sem a lista de funis o filtro não aparece e a lista volta para todos os funis.
    pipelines.value = [];
  }
  const visible = visibleFunnelChoice(
    modelValue.value,
    pipelines.value.map(pipeline => pipeline.id)
  );
  const choice = pipelines.value.length ? visible : FUNNEL_ALL;
  if (choice !== modelValue.value) modelValue.value = choice;
});

const options = computed(() => [
  { value: FUNNEL_ALL, label: t('CONVERSATION_FUNNEL_FILTER.ALL') },
  ...pipelines.value.map(pipeline => ({
    value: String(pipeline.id),
    label: pipeline.name,
  })),
  { value: FUNNEL_NONE, label: t('CONVERSATION_FUNNEL_FILTER.NONE') },
]);

const hasPipelines = computed(() => pipelines.value.length > 0);
const usesButtons = computed(
  () => pipelines.value.length <= MAX_FUNNEL_BUTTONS
);
</script>

<template>
  <div v-if="hasPipelines" data-funnel-filter class="px-3 pb-2">
    <div
      v-if="usesButtons"
      role="group"
      :aria-label="t('CONVERSATION_FUNNEL_FILTER.ARIA_LABEL')"
      class="flex flex-wrap gap-2"
    >
      <button
        v-for="option in options"
        :key="option.value"
        type="button"
        data-funnel-chip
        :aria-pressed="modelValue === option.value"
        class="relative shrink-0 rounded-full border px-3 h-8 text-sm whitespace-nowrap transition after:absolute after:-inset-y-1.5 after:inset-x-0 after:content-['']"
        :class="
          modelValue === option.value
            ? 'border-n-brand bg-n-brand text-white font-medium'
            : 'border-n-weak bg-n-alpha-1 text-n-slate-12 hover:border-n-slate-7'
        "
        @click="modelValue = option.value"
      >
        {{ option.label }}
      </button>
    </div>
    <div v-else class="flex items-center gap-2">
      <span class="text-sm font-medium text-n-slate-11 shrink-0">
        {{ t('CONVERSATION_FUNNEL_FILTER.LABEL') }}
      </span>
      <ChoiceSelect
        v-model="modelValue"
        class="min-w-0 flex-1"
        compact
        :options="options"
        :aria-label="t('CONVERSATION_FUNNEL_FILTER.ARIA_LABEL')"
      />
    </div>
    <p
      v-if="modelValue === FUNNEL_NONE"
      class="mt-1.5 text-xs text-n-slate-11"
      data-funnel-none-hint
    >
      {{ t('CONVERSATION_FUNNEL_FILTER.NONE_HINT') }}
    </p>
  </div>
</template>
