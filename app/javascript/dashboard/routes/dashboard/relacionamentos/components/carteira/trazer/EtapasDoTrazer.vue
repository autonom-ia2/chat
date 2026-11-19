<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// #3057 — as etapas da jornada de trazer, no topo de "Trazer por PDFs" e "Do
// Agger": onde a pessoa está e o que falta (Enviar → Conferir → Pronto; no
// Agger, Buscar → Conferir → Pronto). É uma sequência de verdade, por isso
// numerada; a que já passou ganha o ✓ e a de agora fica marcada
// (aria-current="step"). Só mostra: as telas é que andam.
//   etapas: ['ENVIAR', 'CONFERIR', 'PRONTO']   atual: o índice da de agora
const props = defineProps({
  etapas: { type: Array, required: true },
  atual: { type: Number, required: true },
});

const { t } = useI18n();

const TOM_DO_NUMERO = {
  agora: 'bg-n-slate-12 text-n-slate-1',
  feita: 'bg-n-teal-9 text-white',
  falta: 'bg-n-alpha-2 text-n-slate-11',
};
const momento = indice => {
  if (indice === props.atual) return 'agora';
  return indice < props.atual ? 'feita' : 'falta';
};

const itens = computed(() =>
  props.etapas.map((chave, indice) => ({
    tom: TOM_DO_NUMERO[momento(indice)],
    chave,
    numero: indice + 1,
    nome: t(`RELACIONAMENTOS_CARTEIRA.ETAPAS.${chave}`),
    feita: indice < props.atual,
    agora: indice === props.atual,
  }))
);
</script>

<template>
  <ol
    data-carteira="etapas"
    :aria-label="t('RELACIONAMENTOS_CARTEIRA.ETAPAS.ROTULO')"
    class="flex items-center gap-2 p-0 m-0 list-none"
  >
    <li
      v-for="(etapa, indice) in itens"
      :key="etapa.chave"
      :data-etapa="etapa.chave"
      :aria-current="etapa.agora ? 'step' : undefined"
      class="flex items-center min-w-0 gap-2"
      :class="{ 'flex-1': indice < itens.length - 1 }"
    >
      <span
        aria-hidden="true"
        class="flex items-center justify-center text-sm font-semibold rounded-full size-8 shrink-0 tabular-nums"
        :class="etapa.tom"
      >
        <span v-if="etapa.feita" class="i-lucide-check size-4" />
        <template v-else>{{ etapa.numero }}</template>
      </span>
      <span
        class="text-sm whitespace-nowrap"
        :class="
          etapa.agora
            ? 'font-semibold text-n-slate-12'
            : 'font-medium text-n-slate-11'
        "
      >
        {{ etapa.nome }}
      </span>
      <span
        v-if="indice < itens.length - 1"
        aria-hidden="true"
        class="flex-1 h-px min-w-4"
        :class="etapa.feita ? 'bg-n-teal-9' : 'bg-n-weak'"
      />
    </li>
  </ol>
</template>
