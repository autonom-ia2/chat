<script setup>
// Filtro "Funil" da lista de conversas (multifunil #1150, aprovado pelo Rodrigo em 15/10).
// Até 4 funis: botões lado a lado, um toque troca. Mais de 4: campo de escolha (ChoiceSelect, sem <select> nativo).
// Os funis vêm de GET /crm/pipelines, que já mostra só os funis da pessoa (Crm::Access::VisiblePipelines).
// "Sem assunto" é a triagem: conversa sem card.
// #2202 (com `listaNova`, chave lista_quem_espera): "Todos" no lugar de "Sem filtro de funil", as pílulas
// rolam de lado numa linha só, o erro aparece com "Tentar de novo" e o slot `antes` põe o
// chip do status ("Adiadas ✕") no começo da linha. Quando sobra pílula para a direita, a borda direita
// esmaece, para a pílula cortada não parecer erro. Sem `listaNova`, o filtro de sempre.
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEventListener, useResizeObserver } from '@vueuse/core';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import {
  FUNNEL_ALL,
  FUNNEL_NONE,
  MAX_FUNNEL_BUTTONS,
  visibleFunnelChoice,
} from 'dashboard/composables/useFunnelFilterChoice';

const props = defineProps({
  listaNova: { type: Boolean, default: false },
});
const modelValue = defineModel({ type: String, default: FUNNEL_ALL });

const { t } = useI18n();
const pipelines = ref([]);
const erro = ref(false);

const carregar = async () => {
  erro.value = false;
  try {
    const { data } = await CrmKanbanAPI.getPipelines();
    pipelines.value = data?.payload || [];
  } catch {
    // Sem a lista de funis (rede, deploy) o filtro só some: a escolha guardada fica como está e volta na próxima vez.
    // Na lista nova, o erro aparece, com "Tentar de novo".
    erro.value = true;
    return;
  }
  const visible = visibleFunnelChoice(
    modelValue.value,
    pipelines.value.map(pipeline => pipeline.id)
  );
  const choice = pipelines.value.length ? visible : FUNNEL_ALL;
  if (choice !== modelValue.value) modelValue.value = choice;
};

const fileira = ref(null);
const temMaisAoLado = ref(false);
const medirFileira = () => {
  const el = fileira.value;
  if (!el || !props.listaNova) return;
  // scrollLeft é negativo em RTL; o que importa é quanto falta rolar.
  const falta = el.scrollWidth - el.clientWidth - Math.abs(el.scrollLeft);
  temMaisAoLado.value = falta > 1;
};
useResizeObserver(fileira, medirFileira);
useEventListener(fileira, 'scroll', medirFileira, { passive: true });

onMounted(async () => {
  await carregar();
  await nextTick();
  medirFileira();
});

const options = computed(() => [
  {
    value: FUNNEL_ALL,
    label: props.listaNova
      ? t('LISTA_DE_CONVERSAS.FUNIS.TODOS')
      : t('CONVERSATION_FUNNEL_FILTER.ALL'),
  },
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
  <div
    v-if="listaNova && !hasPipelines && (erro || $slots.antes)"
    data-funnel-filter
    class="flex items-center gap-2 px-4 pb-2"
  >
    <slot name="antes" />
    <p v-if="erro" class="m-0 text-sm text-n-slate-11" data-funnel-erro>
      {{ t('LISTA_DE_CONVERSAS.FUNIS.ERRO') }}
      <button
        type="button"
        class="p-0 font-medium bg-transparent border-0 text-n-blue-11 min-h-11"
        @click="carregar"
      >
        {{ t('LISTA_DE_CONVERSAS.FUNIS.TENTAR') }}
      </button>
    </p>
  </div>
  <div
    v-else-if="hasPipelines"
    data-funnel-filter
    :class="listaNova ? 'px-4 pb-2' : 'px-3 pb-2'"
  >
    <div
      v-if="usesButtons"
      ref="fileira"
      role="group"
      :aria-label="t('CONVERSATION_FUNNEL_FILTER.ARIA_LABEL')"
      class="flex"
      :class="
        listaNova
          ? [
              'gap-2 w-0 min-w-full flex-nowrap overflow-x-auto [scrollbar-width:none] py-1.5 -my-1.5',
              temMaisAoLado &&
                '[mask-image:linear-gradient(to_right,#000_calc(100%-3rem),transparent)] rtl:[mask-image:linear-gradient(to_left,#000_calc(100%-3rem),transparent)]',
            ]
          : 'flex-wrap gap-2'
      "
    >
      <slot name="antes" />
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
      <slot name="antes" />
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
