<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { ESTADO } from '../utils/estadoDoAgente';

// #1181 — pílula de estado: o estado vai em texto (Atendendo / Parado / Falta terminar / Cotação),
// o ponto colorido só reforça. Texto em slate 12 sobre fundo claro do tom, AA nos dois temas.
// Parado e Falta terminar são âmbar, como no protótipo (.pill-off e .pill-draft); o texto distingue.
const props = defineProps({
  estado: {
    type: String,
    required: true,
    validator: v => Object.values(ESTADO).includes(v),
  },
});

const { t } = useI18n();

const ESTILO = {
  [ESTADO.ATENDENDO]: { fundo: 'bg-n-teal-3', ponto: 'bg-n-teal-9' },
  [ESTADO.PARADO]: { fundo: 'bg-n-amber-3', ponto: 'bg-n-amber-9' },
  [ESTADO.FALTA_TERMINAR]: { fundo: 'bg-n-amber-3', ponto: 'bg-n-amber-9' },
  [ESTADO.COTACAO]: { fundo: 'bg-n-slate-3', ponto: 'bg-n-slate-9' },
};

const ROTULO = {
  [ESTADO.ATENDENDO]: 'ATENDENDO',
  [ESTADO.PARADO]: 'PARADO',
  [ESTADO.FALTA_TERMINAR]: 'FALTA_TERMINAR',
  [ESTADO.COTACAO]: 'COTACAO',
};

const estilo = computed(() => ESTILO[props.estado]);
const rotulo = computed(() =>
  t(`AGENTS.JORNADA.STATUS.${ROTULO[props.estado]}`)
);
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 px-2.5 py-0.5 text-xs font-medium rounded-full w-fit text-n-slate-12"
    :class="estilo.fundo"
  >
    <span
      data-ponto
      aria-hidden="true"
      class="rounded-full size-2"
      :class="estilo.ponto"
    />
    <span>{{ rotulo }}</span>
  </span>
</template>
