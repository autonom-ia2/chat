<script setup>
// Calendário Ouro — um item em pouco espaço (semana e mês): a cor do tipo na
// borda, a hora (ou "Dia todo") e o título. Atrasado fica em vermelho.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { TIPOS } from './itensDoCalendario';
import { formatarHora } from './tempoNaConta';

const props = defineProps({
  item: { type: Object, required: true },
  hoje: { type: String, required: true },
  fuso: { type: String, required: true },
  idioma: { type: String, required: true },
  compacto: { type: Boolean, default: false },
});
defineEmits(['abrir']);
const { t } = useI18n();
const tipo = computed(() => TIPOS[props.item.tipo]);
const atrasado = computed(
  () => props.item.atrasado && props.item.chave < props.hoje
);
const hora = computed(() =>
  props.item.diaTodo
    ? t('CRM_CALENDARIO.ITEM.DIA_TODO')
    : formatarHora(props.item.inicio, props.fuso, props.idioma)
);
</script>

<template>
  <button
    type="button"
    :data-pilula="item.id"
    class="flex w-full min-w-0 gap-1.5 rounded-lg bg-n-alpha-1 text-start transition hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :class="[
      compacto
        ? 'min-h-11 items-center px-1.5 text-xs'
        : 'min-h-11 flex-col px-2 py-1.5 text-sm',
      item.feito ? 'opacity-50 line-through' : '',
    ]"
    :title="item.titulo"
    @click="$emit('abrir', item)"
  >
    <span class="flex shrink-0 items-center gap-1.5">
      <span
        class="size-2 shrink-0 rounded-full"
        :class="atrasado ? 'bg-n-ruby-9' : tipo.ponto"
        aria-hidden="true"
      />
      <span
        v-if="item.diaTodo && compacto"
        class="i-lucide-flag size-3 text-n-amber-11"
        :aria-label="hora"
      />
      <span
        v-else
        class="tabular-nums"
        :class="atrasado ? 'font-semibold text-n-ruby-11' : 'text-n-slate-10'"
      >
        {{ hora }}
      </span>
      <span
        v-if="item.repete && !compacto"
        class="i-lucide-repeat size-3.5 text-n-slate-10"
        aria-hidden="true"
      />
    </span>
    <span
      class="min-w-0 text-n-slate-12"
      :class="compacto ? 'flex-1 truncate' : 'line-clamp-3 w-full font-medium'"
    >
      {{ item.titulo }}
    </span>
  </button>
</template>
